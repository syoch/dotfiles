---
name: nextcloud-talk-webhook
description: Use when building or debugging a NextCloud Talk (spreed 25) HTTP bot webhook bridge: bot feature exclusivity (webhook/response/reaction vs event), signing header direction (X-Nextcloud-Talk-Signature for users vs X-Nextcloud-Talk-Bot-Signature for bots, HMAC(random+body), random >= 32 bytes), Activity Streams payload dispatch where only type "Create" is a chat message and the body lives in object.content as a JSON string, the 5-second webhook timeout, the 404 during talk:bot:setup, and the fact that bot-posted messages never trigger bots ("No bots for bots") so bot-to-bot delivery does not work through Talk. Trigger keywords: NextCloud Talk, spreed, talk:bot, webhook bridge, bot signature, X-Nextcloud-Talk-Signature, X-Nextcloud-Talk-Bot-Signature, object.content, Create payload, webhook timeout 5s, No bots for bots, bot to bot webhook, talk:bot:setup 404, feature event exclusive.
---

# NextCloud Talk webhook 契約（spreed 25）

実測に基づく（sv01: NextCloud 35.0.0 / spreed **v25.0.0**）。**stable31 = Talk 21** なので stable 系の記述を鵜呑みにしない。

この skill は **Talk 側の契約だけ**を扱う。turn 完了判定や bridge 内 routing の実装は
dotfiles の project memory `design/nextcloud-talk-venue` が正なので二重管理しない。

## いつ使うか

- NextCloud Talk の bot を **外部 HTTP ブリッジ**経由で動かすとき（webhook 受信 → 自前処理 → 応答）
- 複数 role の bot を 1 つの会話に置いて運用するとき（**bot→bot は Talk では成立しない**）
- 署名検証、payload パース、feature 指定を実装するとき

## 手順

### 1. feature の指定

`event` は v25 で **`webhook` / `response` / `reaction` と排他**（install が exit 1 で拒否）。
外部 HTTP ブリッジに正解の組み合わせは 3 つだけ:

```
talk:bot:install <name> <secret> <webhook-url> \
  --feature webhook --feature response --feature reaction
```

exit code（1/2/3）の意味と引数形は `nextcloud-talk-occ` を参照。

`event` は NextCloud アプリとして組み込まれた bot 専用（`nextcloudapp://` URL、ローカルイベントから読む）。
**外部 HTTP サービスには構造的に不要。**

### 2. 署名ヘッダは方向で非対称

| 方向 | ヘッダ | 署名対象 |
|---|---|---|
| **user → bridge**（受信） | `X-Nextcloud-Talk-Random` / `X-Nextcloud-Talk-Signature` | `HMAC(secret, random + rawBody)` |
| **bot → NextCloud**（投稿） | `X-Nextcloud-Talk-Bot-Random` / `X-Nextcloud-Talk-Bot-Signature` | `HMAC(secret, random + message)` |

- `Bot-` が付くのは **bot が NextCloud を呼ぶ側だけ**。受信側に付けると 401。
- どちらも `random` 単体ではなく **`random + データ`連結**。random は **32 バイト以上**。
- 受信側は **生 body 文字列**で検証する。JSON を再シリアライズするとバイト列が変わって一致しない。
- 出典: `ChecksumVerificationService::validateRequest` = `hash_hmac('sha256', $random . $data, $secret)`

### 3. ⚠ bot→bot の webhook は原理的に成立しない

`spreed/lib/Service/BotService.php`:

```php
public function afterChatMessageSent(ChatMessageSentEvent $event, MessageParser $messageParser): void {
    $attendee = $event->getParticipant()?->getAttendee();
    if (!$attendee instanceof Attendee) {
        // No bots for bots
        return;
    }
```

**bot が投稿したメッセージは mention の有無に関係なく bot を起動しない。**
したがって `Bot-` ヘッダ付きの webhook は到達しない前提になる
（「bot からの投稿を検証する受信側」を設計しても届かない）。

→ **role 間の routing は bridge 内で実装する。** role の返信に `@role` が
含まれていれば、bridge がその role の turn を自分で実行し Talk に投稿する。
人間も Talk の mention も介在しない。再委任は許可、連鎖長だけ制限（`MAX_HOPS` 既定 4）。

「**別の** bot のメッセージは届く」という観測もあるが、上記コードとは
噛み合わないため **要実測**（どちらを前提にしても bot→bot を Talk に期待しないこと）。

### 4. payload は Activity Streams。本文は `object.content`

```json
{ "type": "Create",
  "actor":  { "type": "Person", "id": "users/syoch", "name": "Syoch" },
  "object": { "type": "Note", "id": "4242", "name": "message",
              "content": "{\"message\":\"...\",\"parameters\":{}}",
              "mediaType": "text/markdown" },
  "target": { "type": "Collection", "id": "<token>", "name": "<room>" },
  "published": "..." }
```

`payload.type` で dispatch 可否が決まる。**`Create` のみ chat メッセージ**。

| type | 意味 | dispatch |
|---|---|---|
| `Create` | chat メッセージ | ✅ 入口 |
| `Activity` | システムメッセージ | ❌ |
| `Like` / `Undo` | リアクション | ❌ |
| `Join` / `Leave` | 参加者変更 | ❌ |

本文は `object.content`（**さらに JSON 文字列**。`{"message":...,"parameters":{}}`）。
**`payload.content` ではない。**

### 5. webhook は 5 秒で切れる

`BotService::sendAsyncRequest` が `'timeout' => 5`。1 回の応答生成は 30 秒以上かかるのが普通。

→ **1 秒未満で 200 を返し、処理は非同期に回す。** 同期で待つと
NextCloud 側が全メッセージをタイムアウト扱いにする。

### 6. `talk:bot:setup` 中の webhook は 404 になる

`talk:bot:setup` は**その場で webhook を POST する**。この時点では
bot registry の行がまだ無いので 404 になる。

→ **`setup` の失敗を握り潰さない。** 握り潰すと「venue 作成成功”而、実体は
壊れた bot になる。ログで 404 を確認してから登録手順を続けること。

`allow_local_address: true` が付くので 127.0.0.1 宛 webhook は通る。

## 検証方法

- **署名**: `random+body` は受理 / `random` 単体・改竄 body・`Bot-` ヘッダを
  受信側に入れる・random<32B はすべて 401
- **payload**: `type` 全 6 種（Create/Activity/Like/Undo/Join/Leave）で dispatch 可否を検証。
  本文が `object.content` から取れること
- **非同期**: webhook が 1 秒未満で 200 を返し、処理はその後
- **setup**: `talk:bot:setup` 直後の 404 が握り潰されていないこと（ログで）
- payload を**自作しない**。実 event ログから作る（`Activity` を自分で作ると PASS した前例）

## 落とし穴

| # | 症状 | 真因 |
|---|---|---|
| 1 | bot からの返信が次の bot を起動しない | `afterChatMessageSent` の "No bots for bots"。**routing は bridge 内で実装** |
| 2 | `Bot-` ヘッダの webhook を待って設計する | 到達しない。上の Early return が原因 |
| 3 | 全 chat メッセージが捨てられる | `type !== "Activity"` を条件にしている。**`Create` が入口**（`Activity` はシステムメッセージ） |
| 4 | 署名が一致しない | JSON を再シリアライズしている。**生 body**で検証 |
| 5 | webhook が 5 秒で切れる | 同期 response。**即 200 + 非同期** |
| 6 | install が exit 1 で失敗 | `event` と `webhook`/`response`/`reaction` を併記した |
| 7 | 壊れた bot を含む venue が「作成成功」 | `setup` の 404 を握り潰した |
| 8 | テストだけずっと PASS | payload を自作して、切りたい対象を自分で再現した |
| 9 | 実装が API に合わない | stable31（Talk 21）の記述を当てた。`event` の排他制約自体が別 |
