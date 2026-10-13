---
name: talk-venue-briefing
description: Use when receiving a turn prompt from a NextCloud Talk venue bridge as a role agent, when wondering why no conversation history was included, or when deciding whether to answer via talk-post_post or talk-delegate. Covers the briefing header format (From: sender / To: You (role) / ---), why message bodies are intentionally omitted (a measured session was 2,074 messages / 484,663 chars), that identity comes from the talk-post plugin's system prompt injection, that history is fetched only on explicit request, and that bot-to-bot replies MUST use talk-delegate because bot-posted messages never trigger bots. Trigger keywords: Talk venue, briefing, turn prompt, From To header, no history, /ctl/session messages, context budget, role agent, talk-delegate, talk-roles, talk-post_post, bot to bot delivery.
---

---
name: talk-venue-briefing
description: Use when receiving a turn prompt from a NextCloud Talk venue bridge as a role agent, or when wondering why no conversation history was included. Covers the briefing header format (From: sender / To: You (role) / ---), why message bodies are intentionally omitted (a measured session was 2,074 messages / 484,663 chars), that identity comes from the talk-post plugin's system prompt injection, and that history is fetched only on explicit request. Trigger keywords: Talk venue, briefing, turn prompt, From To header, no history, /ctl/session messages, context budget, role agent, talk-delegate, talk-roles, talk-post_post.
---

# Talk venue の briefing を読む（role エージェントの turns）

bridge が渡す briefing は **ヘッダと指針だけ**。会話本文は含まれないのが仕様。
したがって「履歴が消えた」と誤認しないこと。

## いつ使うか

- NextCloud Talk の venue（bridge）から turn prompt を受け取った直後
- 「会話履歴が無い」状態での作業になるとき
- 過去発言の引用が必要になったとき（**明示要求時のみ**取得する）

## 手順

### 1. ヘッダを読む

```
From: <sender> (human|role)
To: You (<role)>
---
<本文>
```

- `From` は送信源（人間 or role）。`To` は自分の role。
- 旧 `[role]` マーカーと hop 数は**廃止**。役割は `To:` で明示される。

### 2. 自分の identity は system prompt から取得

- talk-post plugin が system prompt に**毎リクエスト注入**する（compaction 後も残る）。
- briefing の `To:` と一致するはず。一致したらそれを使う。

### 3. 本文が無いのは仕様

- 会話履歴は**全量渡さない**。実測で 1 セッション = 2,074 messages / 484,663 chars あり、渡すと**文脈が破壊される**。

### 4. 過去発言が要るときだけ取得する

- trigger は「leader が明示的に求めた」「失敗の検証に具体 log が要る」の 2 つだけ。挨拶や背景説明のために取らない。
- 取得は `GET /ctl/session/<id>/messages?limit=` を**明示要求時のみ**。

### 5. 返答は短く

- venue の会話は chat なので、要約 1〜数行。作業内容は turn 内に持つ。

## 返答の送り先（bot → bot では `talk-post_post` が届かない）

**送り先は送信元で決める。Talk は bot の投稿に bot を起動しない（`No bots for bots`）。**

| 送信元 | 返答する tool | 届く先 |
| --- | --- | --- |
| human | `talk-post_post` | 会話（人間に読める） |
| **role**（leader 含む） | **`talk-delegate`** | その role の session |

- role からの依頼に `talk-post_post` すると、**Posted は成功でも相手 role には届かない**。
  相手は DB を直接読むしかなく、催促される。2026-10-07 に `procon-osm` が `procon-lead` へ調査結果を `talk-post_post` で送り、`procon-lead` が DB から回収した（`procon-review` が同じ指摘）。
- `talk-delegate` は「投稿 + 相手への配信」を同時に行う。`talk-roles` で role 名を確認してから呼ぶ。
- 人間にも可见にしたい場合は `talk-delegate` の後 `talk-post_post` で要約を 1 行残す。

## 検証方法

- briefing の**文字数を実測**する。1 セッションの本文を渡した場合**即座に破綻する**
- 要求していないのに履歴本文を取得していないこと（`/ctl/session/<id>/messages` の呼び出し履歴を見る）
- 本文を引用せず、要点だけを返している
- 返答した tool が送信元（`From:`）の種別と合っている

## 落とし穴

| # | 症状 | 真因 |
|---|---|---|
| 1 | 文脈が突然壊れる / 回答が的外れ | briefing に会話本文（数十万文字）が入っている |
| 2 | 「履歴が消えた」 | **消えていない。渡されない設計** |
| 3 | 本文を要求もせず再取得 | 明示要求なしの取得は文脈を浪費する |
| 4 | 自分の発言を前提に会話している | 「既読」「既 replied」の情報は briefing に無い |
| 5 | session 状態が空 | 知りたいなら `/session` 系は **`directory` フィルタが必要**。省略で 0 件 |
| 6 | Posted したのに相手が「届いていません」と言う | `talk-post_post` は bot を起動しない。role へは `talk-delegate` |

## 関連

- 委任: `talk-delegate` / ロール一覧: `talk-roles` / 人間向け投稿: `talk-post_post`
- venue の実装詳細は dotfiles の project memory `design/nextcloud-talk-venue` が正。
- Talk 側の契約は `nextcloud-talk-webhook` を参照（`No bots for bots` の根拠）。
