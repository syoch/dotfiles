# NextCloud Talk venue（opencode 役割エージェントの議論の場）

## 概要

sv01 の NextCloud 35 に Talk（spreed 25.0.0）を導入し、プロジェクトごとに
グループ会話（roomType=2, 非公開）を用意する。プロジェクト開発が終了するまで
**役割（role）は削除せず**、同じ役割は**同じ opencode セッションを使い回す**。

 Bridges: `components/host/sv01/talk-bridge/`（Bun/TypeScript）
 module: `components/host/sv01/services/talk-bridge.nix`

## 確定した設計判断

| 論点 | 決定 | 根拠 |
|---|---|---|
| agent の身元 | agent ごとに独立 Talk bot | 発言源が明確。`occ talk:bot:install` |
| bot の能力 | 全機能有効（webhook/response/event/reaction） | |
| 発言順 | **自己申告**。メンションは turn signal に留める | 応答判断は agent 側 |
| 人間の位置づけ | **完全に対等**。別枠なし。プロンプトを仲介しない | 承認者を置かないことで HITL の精度低下（PLOS One 2024）を回避 |
| 可視範囲 | 会話履歴を全量。**本文は渡さない** | 実測で 1 セッションが 470,032 文字あり、渡すと文脈を破壊する |
| 役割の同一性 | **プロンプト上**（opencode agent にはしない） | opencode は agent 設定を起動時キャッシュし、動的追加不可 |
| セッション | 使い捨てではない | |
| 登録簿 | PostgreSQL 1 表 | 動的管理・列挙が要件 |

## 命名規則

```
<project-slug>-<role-slug>     例: dotfiles-lead / infra-portal-cache
```

- **小文字 ASCII + ハイフンのみ**（URL 安全・エンコード不要）
- `role-slug` は**責務の粒度**。`cache` であり `cache-redis` でない
  - 実装名まで入れると leader の「再利用か新規か」の判断が矛盾する
- Talk bot 名は**不変**（`talk:bot:rename` が存在しない）
- bot はサーバーエンティティなので**インスタンス全体で一意**が必要
  → `project-slug` を接頭辞にすることで充足

移行済みセッションの改名は `<prefix> · <元題名>`。旧題名を保持し、
`isMigratedTitle` で二重適用を防ぐ。

## スキーマ（1 表）

```sql
CREATE TABLE talk_agent (
  token       text NOT NULL,   -- 会話 token（venue 識別子）
  role        text NOT NULL,   -- 役割（永続）
  secret      text NOT NULL,   -- HMAC secret（動的生成なので DB 平文）
  server_url  text NOT NULL,
  session_id  text NOT NULL,   -- 使い回すセッション
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (token, role)
);
```

`talk_bot` と `talk_session` は統合された。`talk_venue`（プロジェクト表）は
**削除**。leader は自分のプロジェクト工作在 Halifax しているため不要。

## API

### A. webhook（Talk → bridge）

```
POST /hook/<token>/<role>
```

パスに token と role を含むことで、署名の照合対象シークレットが一意に決まる
（シークレットの総当たりを避ける）。

応答を `POST /ocs/v2.php/apps/spreed/api/v1/bot/<token>/message` で投稿。

### B. control API（leader / 人間 → bridge）

| endpoint | 用途 |
|---|---|
| `GET /ctl/sessions?project_path=&limit=&offset=&prefix=` | 移行候補を判断材料付きで列挙 |
| `POST /ctl/venue` | venue 作成（9 手順を 1 コールで） |
| `GET /ctl/venues` | venue 一覧 |
| `DELETE /ctl/venue?token=` | venue 全体を削除（role 行 + bot + conversation） |
| `GET /ctl/occ?args=` | occ 診断。bridge と**同一権限・同一ラッパー**で実行する |
| `GET /ctl/agents?token=` | 役割一覧（再利用判断の材料） |
| `POST /ctl/bot` | 役割を動的作成 |
| `POST /ctl/session` | session_id を記録（既存セッションの採用） |
| `DELETE /ctl/bot?token=&role=` | 役割を削除（uninstall） |
| `GET /ctl/session/<id>/messages?limit=` | 過去セッション本文の取得（leader が明示要求時のみ） |
| `GET /healthz` | 健全性 |

## venue 作成の 9 手順

```
1. slug 重複チェック
2. occ talk:room:create <slug> --user <human> --listable 0   → token
3. secret 生成（40〜128 文字）
4. occ talk:bot:install <slug>-lead <secret> <webhook> --feature ...
5. bot-id 取得（talk:bot:list -v --output json を url で照合）
6. occ talk:bot:setup <bot-id> <token>
7. opencode でセッション作成（directory=<project_path>）
8. talk_agent に行を INSERT
9. migration（改名 + leader への引き継ぎ）
```

**途中失敗時は逆順で全巻き戻しする**（DB 行削除 → bot remove → bot uninstall
→ conversation 削除）。片方だけ消すと孤児が残る。

## 検証済みの外部 API の正確な形

### nextcloud/spreed occ（**v25.0.0** = NC35。stable31=Talk21 なので別物）

**バージョンを確認せずに stable31 を読むと誤る。** sv01 は
`pkgs.nextcloud35` = NC 35.0.0 / spreed **v25.0.0**。stable31 は Talk 21 で、
`event` feature の排他制約などが異なる。

| command | 事実 |
|---|---|
| `talk:room:create` | `--public` は VALUE_NONE。**既定が既に TYPE_GROUP(2)**。`--user` は複数可。`--listable 0`=非掲載。出力は `Room token: <token>` |
| `talk:room:add` | **`token` が positional**。`--user` は option。`room:add <token> --user U` |
| `talk:bot:install` | **`--output` が無い。id を返さない**。終了コード 1=パラメータ/排他違反、2=url 重複、3=secret 重複 |
| `talk:bot:setup` | `talk:bot:setup <bot-id> <token>...` |
| `talk:bot:uninstall` | `[id]` か `--url <url>`。**url 照合が確実**（bot 名は衝突しうる） |
| `talk:bot:list` | `writeTableInOutputFormat` なので `--output json` が使える。**`-v` が無いと `url` 列が除去される** |
| secret | 40〜128 文字（`validateBotParameters`） |

token 解析は `/Room token:\s*(\S+)/` の行マッチで行う。緩い
`/[a-z0-9]{8,64}/` だと会話名や説明文の単語を掴む。

### ⚠ FEATURE "event" は v25 で排他（設計を変えた）

```
if ($featureFlags & FEATURE_EVENT
    && ($featureFlags & FEATURE_WEBHOOK || FEATURE_RESPONSE || FEATURE_REACTION)) {
    'Bots with feature "event" can not support "webhook", "response" or
     "reaction" feature. They are mutual exclusive'
    return 1;
}
```

当初の「全機能有効」は **v25 では install が exit 1 で拒否する**。
`event` は NextCloud アプリとして組み込まれた bot 専用（`nextcloudapp://`
URL、ローカルイベントから読む）。**HTTP ブリッジには webhook + response +
reaction が正解**。bridge は外部 HTTP サービスなので event は構造的に不要。

決定: `BOT_FEATURES = ["webhook", "response", "reaction"]`

### ⚠⚠ turn を blocking POST で待つと回答が永久に失われる（最重要）

**これが「応答が Talk に戻ってこない」バグの原因だった。**

bridge は `POST /session/{id}/message` を **turn 完了まで blocking** で待っていた。
このリクエストには HTTP timeout があるので:

```
turn 300 秒超 → fetch abort → bridge は例外を受け取って応答を post しない
                → しかしモデル自体は server 側で生成を完了している
                → **完成した回答が破棄される**（session には done=Y で残る）
```

実測: 名前の質問への回答（1813 文字, done=Y）が bridge には届かなかった。

原因を探る: `AbortError: The operation was aborted.` が唯一のログ。

**対策: `POST /session/{id}/prompt_async`（204 で即座に返る）＋ 完了をポーリング。**

```ts
const before = await oc.lastMessageId(sessionId)     // GET ?limit=1
await oc.promptAsync(sessionId, { text })             // 204、待たない
const r = await oc.awaitReply(sessionId, before, { pollMs: 2000, maxWaitMs: cfg.turnWaitMs })
```

`awaitReply` は `GET /session/{id}/message?limit=2` を 2 秒間隔で読み、
`prevMessageId` より新しく **かつ** `info.time.completed` を持つ assistant を待つ。

設定の分離が要点:

| 変数 | 範囲 | 既定 | 意味 |
|---|---|---|---|
| `OPENCODE_TIMEOUT_MS` | HTTP 1 回 | 300000 | 単発リクエストの上限 |
| `TURN_WAIT_MS` | turn 全体 | 1800000 | 回答が返るまでの予算 |

`TURN_WAIT_MS` 切れ時は**沈黙せず**「まだ応答を作成中です」と通知を post する
（provider が死んでいても人間を待たせない）。

**副次的に**: venue 作成時の migration briefing も `promptAsync` 化。
これを awaited のままだと、モデルが遅いだけで**健全な venue が丸ごとロールバック**
されていた。

### ⚠ テスト stub の `time.completed: 0` は falsy

「まだ生成中」と判定される。実サーバは epoch ms なので 0 にならないが、
stub で `completed: i`（i=0）と書くと**無限に生成中に見える**。必ず非 0 を入れる。

### ⚠ 遅い turn は沈黙しないこと（ack）

「応答が来ない」=”消失”jor disappearance で区別できない。
実測（この host, assistant 35 turn）: **median 19s / p90 62s / max 384s、20 秒超が 49%**。

→ `ACK_AFTER_MS`（既定 30000）を超えた turn だけ先に
「受信しました。調べています。」を post する。**reply が先に来たら取り消す**ので、
速い turn は 1 通のまま（既存会話のノイズが増えない）。

ack が要る理由は UX だけでなく**診断**でもある。返事が無い 事象と、
到着 acknowledgement の無い 事象は区別がつかない。

### ⚠⚠⚠⚠⚠ bridge は turn を直列化してはいけない（opencode が既に queue する）

`SessionInputAdmitted` に `delivery: "steer" | "queue"` と
`admittedSeq` / `promotedSeq` がある。**busy な session への `prompt_async` は
opencode 自身が queue する。**

bridge 側で `roleQueues` を作ると**キューが二重**になり、
`enqueue` の内側でしか ack を発火できないため
**待ち行列が無音になる**（= 送信したのに返事が来ない／消えたように見える）。

→ **bridge 側の直列化は撤廃した。** `prompt_async` をすぐ呼び、
opencode に順序を任せる。

### ⚠⚠⚠⚠ reply の照合は `parentID` で（二位位置の推測は不可）

`prompt_async` の body に **`messageID`（`^msg` パターン）を自分で指定できる**。
そして **assistant message の `parentID` は、その返答に対応する user message id**。

実測で確認（9 件中 7 一致、残り 2 件は `limit` 切り詰めによる先頭欠落）:

```
POST /session/{id}/prompt_async  body: { messageID: "msg_<uuid>", parts: [...] }
GET  /session/{id}/message
  → m.info.parentID === "msg_<uuid>" かつ role==="assistant" かつ time.completed
     → これが「自分が送ったメッセージの返答」
```

これで一度に解決する:
- 「どの assistant が自分のものか」を推測しなくてよい（バグ 8/10/11 の根）
- turn が重なっても返答を取り違えない
- bridge のキューが不要になる

**メッセージウィンドウは最初は 30 件。** 5 件だと先行 turn のメッセージが
範囲外に出て、その turn だけ拡大して**より遅く**解決し、**返答が逆順になる**。

### ⚠⚠⚠⚠⚠ `parentID` 一致だけでは「最終回答」と「途中経過」を区別できない

**1 turn の全ステップが同じ `parentID` を共有する。** 実測:

```
08:13:27 assistant  89ch  parent=4453a0267  "lousy 承知しました..."   ← 誤投稿された
08:13:42 assistant  33ch  parent=4453a0267  "役割ができました"
08:13:53 assistant 980ch  parent=4453a0267  "和要求されたdynamic..."  ← 本当の答え
```

判定には **2 条件が両方要る**。

| 条件 | 役割 |
|---|---|
| `parentID === promptMessageId` | **どの** turn の返答か（区別） |
| turn が完了していること | **いつ**完成したか（タイミング） |

完了判定は 2 つ。**先に idle を読む**（message→status の順だと、turn が
2 リクエストの間で完了すると「古い本文 + idle」で誤判定する）:

```
1. GET /session/status          → idle?
2. GET /session/<id>/message   → 本文
3. idle なら最終回答を返す
```

queue だと自分の turn が終わった瞬間に次が busy になるので、idle 待ちだけだと
**次の turn の latency が上乗せされる**。補助条件として
**本文が `settleMs`（既定3秒）変わらなければ完成と見なす**を併記する。
poll 回数ではなく実時間で判定すること（間隔が短いと同じ穴が再発する）。

### ⚠⚠⚠⚠⚠ `reverse()` で上書きすると「最も古いテキスト」が残る

```ts
for (const m of [...mine].reverse()) if (text) lastText = text   // ← 逆順に上書き
```
`mine` の並びは `tool → commentary → final`。fin から逆順に見て cm で**上書き**
され、最終的に**最初に見たテキスト**が残る（= 途中経過が投稿される）。
**正向走査で上書き**すれば最新ステップが残る。
### ⚠⚠⚠⚠⚠ bot→bot は Talk の webhook では原理的に成立しない

`spreed/lib/Service/BotService.php`:

```php
public function afterChatMessageSent(ChatMessageSentEvent $event, MessageParser $messageParser): void {
    $attendee = $event->getParticipant()?->getAttendee();
    if (!$attendee instanceof Attendee) {
        // No bots for bots
        return;
    }
```

**bot のメッセージは mention に関係なく一切 bot を起動しない。**
したがって `Bot-` 付きヘッダの webhook は存在せず、受理逻辑の検討自体が誤り。

→ **role 間の routing は bridge 内で実装する。**
role の返信に `@role` が含まれていれば、bridge がその role の turn を自分で実行し、
Talk に投稿する。人間も Talk の mention も介在しない。

- 再委任は**許可**（レビュー依頼・依頼元への回答が通常パターン）
- 連鎖長だけ制限（`MAX_HOPS` 既定 4）
- 宛先に「誰が・どの venue・何 hop 目か」を渡す。outhern不然応対できない

### ⚠⚠⚠⚠ 同一セッションの返信は**受付順**で Morris なければならない

同じ poll window 内で完了した turn は**全部 `idle` を見���る**ため、
settle が先になった turn が先に投稿する（質問と回答がずれる）。

対策: **投稿だけを受付順で直列化**（dispatch はそのままでよい）。
ただし slot は**返信できた時ではなく受付時に確保**する。確保が遅れると
「完了順」になってレースに負ける。

- 実装は promise チェーン。`prev.then(post, post)` 相当で、
  **前の投稿が失敗しても後続を固めない**こと
- **全ての exit で release する**（error / timeout / 例外）。
  忘れると以降が全部固まる
- テストは 4 回連続で ALL PASS を確認すること（1 回通っただけで信用しない）

**bot が自分で投稿したメッセージは webhook が届かないが、
「別の bot」のメッセージは届く。** そのため role 間の delegation が成立する。

### ⚠⚠⚠⚠⚠ 新規ファイルは `git add` するまで flake に入らない

flake は **git tree** を入力にするため、`??`（未追跡）のファイルは
`nixos-rebuild` に silently に欠ける。

```
error: Cannot find module './pending.ts' from /nix/store/...-src/index.ts
→ talk-bridge.service: Failed with result 'exit-code'（無限再起動）
```

**新規 .ts を作ったら必ず `git add` してから dry-build。**
`dry-build PASS` は「追跡済みファイル」のみを検証するため、
未追跡ファイル的存在を検出しない。

### ⚠⚠⚠⚠⚠ `talk:bot:setup` 中の webhook は 404 を返すと bot が hearing 失う

`/ctl/venue` の順序は「install → setup → insert」。
**setup は registry 行が無い状態で webhook を probe する**ため 404 になり、
NextCloud が `error_count` を加算して**その bot の webhook 配信を止める**。
`talk:bot:list` は `state=1` のままなので**壊れた bot にpositions 見分けられない**。

対策: setup 中の role を `pendingVenues`（db.ts）に登録し、
その間の webhook には 200 + `skipped` を返す。

### ⚠⚠⚠⚠⚠ plugin は「ファイル内の全 export」を plugin 関数として呼ぶ

`~/.config/opencode/plugins/x.ts` は**named export を全部** plugin として呼ぶ。
`export const FOO = "bar"` を 1 個混ぜただけで **ファイル全体がロード失敗**する。

```
export const TALK_POST_TOOL = "talk-post_post"   ← これで全体が死んだ（無言）
export default TalkPost                          ← これが唯一の正解
```

`/config` にはプラグインが**並んでいるように見える**ので、`event` が来ないだけだと
「読み込まれている」と誤解する。**判別は hook のログを 1 本出してから確かめることだけ**。

### ⚠⚠⚠⚠⚠ tool 名は `<file>_<export>`（ハイフンは保持）

```
tools/talk-post.ts  の  export const post  →  モデルは talk-post_post と呼ぶ
tools/agents.ts     の  export const list  →  agents_list
```

plugin の `tool: {}` マップは**モデルに見えない**（実測）。
briefing に書く名前も実際の名前と一致させること。

### ⚠⚠⚠⚠⚠ nudge 自身は nudge しない（テキスト目印）

`chat.message` は**nudge 自身のユーザーメッセージ**でも turn を新規登録する。
`nudged` を引き継ぐと `nudge → idle → nudge` の**無限ループ**になる。
プロンプトに `[talk-bridge-nudge]` を付けて**その turn は nudge 済みに**する。

### ⚠⚠⚠⚠⚠ `input.messageID` は undefined で来ることがある

turn の追跡には `output.message.id` を使う。`input.messageID` が無いと
`state=none` になり nudge が永久に鳴らない。

### ⚠⚠⚠⚠⚠ desktop から Talk API への直接投稿は Cloudflare Access に弾かれる

```
desktop → https://nextcloud.syoch.org/… → 302（サインインページ）
sv01    → loopback                    → 到达
```

したがって**投稿は bridge に代理させる**（`POST /ctl/post { session_id, message }`）。
**bot secret が sv01 の外に出ないので secret の配布问题的も消える**。

### ⚠⚠⚠⚠ `/session/status` は directory フィルタが無いと**空**を返す

**「何もしないで 30 分待って投稿しない」症状の真因。**

```
GET /session/status              → {}            ← busy な session がいても空
GET /session/status?directory=X → {ses_x: {...}}  ← 正しい
```

`directory` を付けずに呼ぶと **0 件**が返る。因此
`status?.[sessionId]` は常に `undefined` で `idle` に**一度もならず**、
`waitForTurnIdle` は毎回 30 分の `turnWaitMs` を超えて `timedOut` になる。
**症状として現れるのは「応答が永久に返らない」だけ。** エラーもログも出ない。

**対策: `directory` は caller に任せず、session 自身から取る。**

```ts
const directory = opts.directory ?? await this.sessionDirectory(sessionId)
// GET /session/{id} → { directory: "/home/syoch/ghq/github.com/syoch/dotfiles" }
```

`talk_agent` に project path を持たなくても解決できる。
schema を変えずに済むので、好みの設計。

**この一类の誤りは「型が optional だから省略できる」ことに起因する。**
optional な filter が**省略すると結果が変わる**API は、
`required` にすべきか、**サーバ側で「絞り込みなし」を拒否する**べき。

### ⚠⚠⚠ turn は複数の assistant step を出す。「最初の非空」も「最初の完了」も誤り

実測（この host、1 turn = 1 user message）:
```
21:35:41 user  (デプロイしました)
21:35:41 assistant done=Y txt=0ch      ┐
21:35:52 assistant done=Y txt=0ch      │ tool 呼び出し専用 step
21:36:04 assistant done=Y txt=0ch      │ （1 回の呼び出しごとに 1 つ）
21:36:18 assistant done=Y txt=0ch      │
21:36:29 assistant done=Y txt=0ch      │
21:36:42 assistant done=Y txt=0ch      ┘
21:37:03 assistant done=Y txt=145ch    ← 途中経過（text あり）
21:37:12 assistant done=Y txt=805ch    ← 最終回答（text あり）
```

**2 つの誤り:**

| 実装 | 結果 |
|---|---|
| 最初の completed assistant を返す | tool step（text 空）を掴む → **全 tool 使用 turn で返信が消える** |
| 最初の非空 completed を返す | 途中経過を投稿 → **最終回答が取り残される** |

後者では「21:37:03 の 145ch は届いたが 21:37:12 の 805ch は届かない」という
**部分的な欠落**として現れる。 evidently「届く時と届かない時がある」ように見える。

**正解: `GET /session/status?directory=` の idle を待って、最後の text step を返す。**

```ts
const [status, msgs] = await Promise.all([
  oc.sessionStatus(directory),                          // { ses_x: {type:"idle"|"busy"|"retry"} }
  oc.req("GET", `/session/${id}/message`, { limit: 5 }),
])
// 最悪でも idle でなければ投稿しない。返答は「最後の非空 text」。
if (sawNew && status[id]?.type === "idle" && lastText) return { text: lastText }
```

message の状態だけでは「まだ生成中」と「完了」を区別できない。
**`/session/status` が唯一の信頼できる turn 終了シグナル。**

### ⚠⚠ opencode は答えの前に「空の assistant message」を出す

**間欠的な「応答が出ない」原因。** `awaitReply` が
「最初の completed assistant」を掴む実装だと、空 message を掴んで
`text: ""` を返し、caller は `if (reply.text)` で投稿をスキップする。
**エラーもログも出ない**ので「何もない」ように見える。

実測（この host）: turn の**約半数が** `done=Y` かつ `txt=0ch` の
assistant message を先に発行してから、本物の回答を数秒後に出す。

```
21:17:44 user
21:17:45 assistant done=Y  txt=0ch     ← 空（中間）
21:18:00 assistant done=Y  txt=1171ch  ← 本物
```

対策: `awaitReply` は **completed かつ text が非空**のものだけを返す。
空は「まだ本質的な答えが届いていない」として**継続して待つ**。

`info.error` は text の有無に関わらず hard failure として即座に返す。

### ⚠ テストが「何もしない」ことで PASS する（4 度目）

この回帰テストを最初に書いたとき、stub の TDZ 参照エラーで
空 message 分岐が**一度も実行されず**て PASS していた。

対策 2 つ:
1. stub の分岐に**実行されたことを表明する counter**を置き、
   `check("stub actually served ...", counter > 0)` で**実行を強制**する
2. **反転テスト**（修正を戻した copy に対して同じテストを走らせ、
   FAIL することを確認する）を必ず作る

前夜から同じ罠に 4 度嵌まった。傾向：**テストの PASS は
「意図した経路を通った」証明ではない**。

### ⚠ 検証プローブの構造的限界

**被測定対象の turn が測っている agent 自身である場合、検証できない。**
- `dotfiles` venue は leader が「私」。私が tool を呼び続ける限り turn が終わらない。
- プローブは自分の分身待っている状態で、ack も reply も観測できない。

さらに: **ack は Talk に投稿される**ので、opencode session を探しても出てこない
（プローブはここを誤った）。Talk の会話を読むには user 認証が要るため、
結果として**人による目視確認**が唯一の手段になる。

教訓: 「テストが通らない」と言ったときは、まず**テストが測る対象と、
テスト自身の期待構造が矛盾していないか**を疑う。

### ⚠ 署名方向が 2 方向で非対称

| 方向 | ヘッダ | 署名対象 |
|---|---|---|
| Talk → bridge（webhook 受信） | `X-Nextcloud-Talk-Random` / `X-Nextcloud-Talk-Signature` | `HMAC(secret, random + rawBody)` |
| bridge → Talk（応答投稿） | `X-Nextcloud-Talk-Bot-Random` / `X-Nextcloud-Talk-Bot-Signature` | `HMAC(secret, random + message)` |

- **`Bot-` が付くのは「bot が NextCloud を呼ぶ」側だけ。** webhook 受信側に
  `Bot-` を付けると 401 になる。
- どちらも `random` 単体ではなく **`random + データ`連結**。random は 32 バイト以上。
- webhook は **body を含めて**検証する（生 body 文字列）。JSON 再シリアライズ
  するとバイト列が変わり一致しない。
- 出典: `ChecksumVerificationService::validateRequest` = `hash_hmac('sha256', $random . $data, $secret)`

### ⚠ webhook payload は Activity Streams。本文は `object.content`

**そして `type` で turn かどうかが決まる。** spreed v25 の BotService が送出する type:

| type | 意味 | turn? |
|---|---|---|
| **`Create`** | **chat メッセージ** | ✅ これが本作の入口 |
| `Activity` | システムメッセージ | ❌ |
| `Like` | リアクション追加 | ❌ |
| `Undo` | リアクション削除 | ❌ |
| `Join` / `Leave` | 参加者変更 | ❌ |

→ `payload.type === "Create"` のみ受理。それ以外は `skipped` を返す。

```json
{ "type": "Create",
  "actor":  { "type": "Person", "id": "users/syoch", "name": "Syoch" },
  "object": { "type": "Note", "id": "4242", "name": "message",
              "content": "{\"message\":\"...\",\"parameters\":{}}",
              "mediaType": "text/markdown" },
  "target": { "type": "Collection", "id": "<token>", "name": "<room>" },
  "published": "..." }
```

- 本文は **`object.content`（さらに JSON 文字列）**。`payload.content` ではない。

**実害（最重要）**: 当初 `type !== "Activity"` を条件にしていたため、
**すべての会話メッセージを破棄**していた（`Activity` はシステムメッセージ）。
しかも**ハーネスが自ら `Activity` を生成していたため、PASS していた**。
payload を自作するテストは、切りたい対象を自分で再現してしまう危険がある。
**実 event ログで type を確認してからテストを作ること。**

教訓: 「E2E で PASS した」と報告する前に、**そのテストが本番と同じ入力形を
作れているか**を疑う。本次は webhook 契約 7 項目中 6 項目まで正しかったのに、
肝心の payload type だけ 180 度逆で、通過していた。
- `allow_local_address: true` が付くので 127.0.0.1 宛 webhook は通る。

### ⚠ webhook の timeout は 5 秒

`BotService::sendAsyncRequest` が `'timeout' => 5`。opencode の 1 turn は
30 秒以上かかるため、**webhook は即 200 で返し dispatch はキューに回す**。
同期で待つと全メッセージが NextCloud 側でタイムアウト扱いになる。

→ `enqueue(token/role, task)` で role ごとに直列化。1 role = 1 session の
ため、並行 prompt は interleave する。順序保証もテスト済み。

### opencode HTTP（live server の OpenAPI 3.1.0 で確認）

| endpoint | 事実 |
|---|---|
| `GET /session?directory=` | `Session.time = {created, updated}`。**`time_created`/`time_updated` は存在しない** |
| `PATCH /session/{id}` | body `{title}` で改名可 |
| `POST /session/{id}/message` | body `{agent, parts}` → `{info: AssistantMessage, parts}`。`info.error` に失敗が入る |
| `GET /session/{id}/message` | **`parts` は埋め込み済み**。`/message/{id}/part` は存在しない（404） |
| `GET /session/{id}/message/{messageID}` | GET のみ。part 取得用ではない |

実測: dotfiles の 1 セッション = 8,082 parts / 1,228 text parts /
484,663 chars / 2,074 messages。messages 取得は 1 リクエストで足りる
（N+1 で part を取る必要はない）。

### Bun subprocess

`Bun.spawn` の `proc.exited` は**終了コードしか返さない**。
stdout/stderr は `new Response(proc.stdout).text()` で drain する。
`const [out, err, code] = await Promise.race([proc.exited, timer])` は
code が `undefined` になり、`r.code !== 0` が常に真になる。

## セッション移行

移行対象は**個数を指定せず、ID を明示する**。候補は判断材料付きで提示する:

```json
{ "id": "ses_x", "title": "環境構築", "already_renamed": false,
  "stats": { "messages": 2074, "text_parts": 1228, "chars": 484663 } }
```

`chars` と `text_parts` が判断の鍵。件数だけ見えない設計は不可。
ただし統計は候補ごとに全 message 一覧が要るため、`stats=1` の
オプトインにしている（キャッシュは将来課題）。

処理は**改名と ID 参照の提示のみ**。本文は渡さない。leader が必要と判断した
時に `GET /ctl/session/<id>/messages` で自分で取る。

## 実装上の重要な制約

### loopback 限定
bridge は `hostname: "127.0.0.1"` で bind する。systemd unit では
`IPAddressAllow/Deny` を使わず、**ソケット側の bind で担保**する
（firewall ではなく）。

### DB パスワードを unit に出さない
`Environment=` に書くと `systemctl show` で見える。`preStart` で SOPS から
読んで `RuntimeDirectory`（0700）内の 0600 ファイルに書き出し、`script` で source する。

### postgresql.authentication の上書き
portal.nix が素の文字列で設定しているため、nixpkgs のデフォルト
（`127.0.0.1/32` ルールを含む）を置き換えてしまう。`lib.mkAfter` で追記する。

### occ の呼び出し
`environment.systemPackages` に入る `nextcloud-occ` ラッパーを使う。
php と拡張.phps が設定済みのため、`php` を直接呼ばない。
`pkgs.nextcloud` は存在しない（`nextcloud35` 等が実体）。

### secret は DB 平文
動的生成される bot のため SOPS（宣言的）を排除せざるを得ない。
loopback + sv01 限定が補償している。**既知の割り切り**。

## 検証結果

| テスト | 件数 | 結果 |
|---|---|---|
| naming（slug/改名/逆引き/webhook パス） | 28 | PASS |
| db（スキーマ/PK/prefix/venue 集計/採用/削除） | 21 | PASS |
| occ+opencode ラッパ（実 API 照合） | 15 | PASS |
| bridge live（v25 契約どおりに署名・payload type 表・非同期を検証） | 40 | PASS |
| `nixos-rebuild dry-build .#sv01` | — | PASS |

live テストで確認した挙動:
- `random+body` 署名は受理、`random` 単体署名は 401（旧バグの回帰防止）
- `Bot-` 付きヘッダは 401（方向を取り違えない）
- random 32 バイト未満は 401
- 本文が `object.content` から取れる
- `type` 全 6 種（Create/Activity/Like/Undo/Join/Leave）で dispatch の可否を検証。`Create` のみ true
- **webhook は 1 秒未満で 200 を返し、dispatch はその後**（5 秒 timeout 対策）
- role ごとに turn が直列化され、順序が保たれる
- 応答投稿の署名が `random+message` で一致し random は 32 バイト以上
- 不正な role 名（大小文字/スラッシュ/先頭/連続 hyphen）は 400
- 他プロジェクトの接頭辞を持つ role は 400、role 重複は 409
- `project_path` 欠落は 400（`.` に落とすと bridge の cwd に作られてしまう）
- 一覧 API で secret は露出しない
- `occ.run()` が終了コードと stdout/stderr を正しく返す

### 実機 E2E で検証できたこと（2026-10-05、sv01 実物）

NextCloud 35.0.0 / spreed **25.0.0** 上で確認済み:

| 項目 | 結果 |
|---|---|
| `app:list --enabled` | exit 0、**spreed: 25.0.0** 有効（64 apps） |
| `talk:room:create e2e --user syoch --listable 0` | exit 0、`Room token: <token>` |
| `talk:room:delete <token>` | exit 0 |
| `talk:bot:install ... --feature webhook --feature response --feature reaction` | exit 0、`Bot installed\nID: 1` |
| `talk:bot:list -v --output json` | `features: webhook, response, reaction`。**`-v` 时 `secret` と `url` を含む**（`url` 韭菜に bot 特定に使う） |
| `talk:bot:uninstall --url <url>` | exit 0。**`--url` を宣言するのはこれだけ** |
| `POST /ctl/venue` | room → bot install → setup → session 作成まで通し成功 |
| webhook 署名（v25 方式） | `random+body` は受理。`random` 単体・改竄 body・`Bot-` ヘッダ・random<32B はすべて 401 |
| `type` 全 6 種 | 仕様どおり `Create` のみ dispatch（Create/Activity/Like/Undo/Join/Leave） |
| dispatch の非同期性 | 1 秒未満で 200、dispatch はその後（5 秒 timeout 対策） |
| opencode 到達性 | reverse tunnel 経由で `GET /session → 200` |

### 実機 E2E で判明した実装起因の問題（すべて修正済み）

1. **occ の権限モデル** — `nextcloud-occ` ラッパーは root 権限で `nextcloud` ユーザーへ
   昇格する。しかも sudo されるのは wrapper ではなく `env`+`php`+`occ` なので、
   **wrapper パスを sudoers で許可しても一致しない**。専用ユーザーでは全 occ が失敗。
   → bridge は `User = nextcloud` で実行する。

2. **2 つのディレクトリ** — occ は両方を検査する。どちらかを写到ないと全滅。

   | 名前 | 内容 | sv01 の値 |
   |---|---|---|
   | `configDatadir` | `config.php`。ラッパーが `NEXTCLOUD_CONFIG_DIR` に設定 | `/var/lib/nextcloud` |
   | `dataDirectory` | ユーザーファイル。occ が**書き込み可否を毎回**検査 | `/srv/NAS/nextcloud` |

   `settings.datadirectory`（= `dataDirectory`）は module option ではないため
   `services.nextcloud.settings.datadirectory` から読む。どちらも `ReadWritePaths` が必要。

3. **`--url` を全コマンドに付けていた** — NextCloud 35 で `--url` を宣言するコマンドは
   `talk:bot:uninstall` **だけ**。`OC\Core\Command\Base::configure()` は `--output` のみ。
   `talk:room:create` は `parent::configure()` を呼びすら呼ばない（`--output` も無い）。
   Symfony は未宣言オプションで必ず失敗する。→ 許可リストは空（uninstall のみ例外）。

4. **`talk:bot:install` は id を出す** — `--output` は無いが stdout 2 行目に `ID: N`。
   `talk:bot:list` への往復は不要（`-v` は secret を漏らす）。直接パースする。

5. **bot setup の時点で 404** — `talk:bot:setup` が即 webhook を POST し、この時点では
   registry 行がまだ無い（step 8/9 の後）。`setupBot` の失敗を握り潰すと venues 作成が
   成功扱いで壊れた venue になる。ログで発見した。

6. **role turn のモデルが既定に依存** — role identity は prompt で運ぶため bridge は
   必ず built-in `general` agent を駆動し、global default model を継承する。この host の
   default は `opencode-go/glm-5.3-flash`。quota 枯渇時は**エラーでなくハング**するため、
   全 role が `OPENCODE_TIMEOUT_MS`（既定 300 秒）まで停止する。
   → `services.talk-bridge.model` で明示固定（既定 `opencode/space-bunny-free`、
   `""` で既定委譲）。

### 実機 E2E 完成（2026-10-05 08:35）

最後に人間が実際に Talk で発言して、通過した:

```
user      payload type "Create" → dispatch 成功
assistant provider=opencode model=space-bunny-free completed=True
          「こんにちは。何かお手伝いできることがあれば教えてください。」
```

つまり **Talk → webhook → bridge → reverse tunnel → opencode → bot → Talk** の
双方向が実機で閉じた。`BRIDGE_MODEL` の固定も効いている
（`opencode-go` ではなく `space-bunny-free` が選ばれている）。

### 実機 E2E で**まだ**未確認

- NextCloud からの**実** webhook Delivery（ハーネスで署名を再現して 200 までは確認。
  NextCloud 自身からの送信は spreed の会話に人が発言する必要があり未実施）
- 複数 agent の同時発言と直列化（ハーネスは 1 role のみ）
- `POST /ctl/bot` による動的 role 追加の実機経路
- migration（改名 + leader への引き継ぎ）の実機経路

## 未実装（確定事項の範囲外）

- dotfiles リポジトリ自身の gdm（制御平面）。bootstrap のみ CLI が必要
- leader の生成方式（未決）
- 役割の自己申告の閾値ロジック
- session 本文の統計キャッシュ（ユーザー判断で一旦不要。`stats=1` で都度計算）
- sv01 実機への deploy / webhook E2E（`nextcloud-occ` の実挙動は未確認）

## 関連

- [[opencode/provider-availability]] — orchestration fleet の単一 provider 依存

---

## 2026-10-06 再設計: hub-and-spoke + 明示委任 (talk-delegate)

### 実測した旧 relay の欠陥
- **lastText 問題**: bridge の relay は turn の「最後の assistant テキスト」のみ走査する（`opencode.ts` の `lastText`）。複数ステップ turn では mention が途中ステップにあると取りこぼす。実測: 委任 turn の 2 assistant メッセージ（`msg_113792ca...` = mention あり / `msg_11379e08...` = mention なし）が同一 parentID で、lastText は mention なしの方だったため relay されず、skill-writer が発火しなかった。
- **broadcast 問題**: Talk は人間メッセージを会話内の全 bot に webhook 配信する。全 role が人間の全メッセージを受けて「関係なければ黙れ」で自粛する設計のため、過剰反応する。実測: skill-writer は人間のメッセージを briefing 付きで受信していた。
- **turn 起点依存**: OpenCode に直接入力した turn は bridge webhook を通らないため relay が動かない（plugin の talk-post / nudge は turn 起点に依らず動く）。

### 採用方針 (hub-and-spoke)
- **配送**: 人間メッセージは lead role のみに配送。人間が @role を明示した時はその role にも配送。
- **`talk-delegate(role, message)`**: メッセージを Talk に投稿しつつ、bridge 経由で対象 role の session に turn として配送（= talk-post 相当の投稿 + 配送。戻り値なし）。全 role が呼べる。重複投稿を避けるため「投稿」もこのツールが担う。
- **`talk-roles()`**: venue の role 一覧＋スコープを返すツール。briefing を膨らませないため都度取得。
- **role スコープ**: `POST /ctl/bot` に description を追加し registry に保存、talk-roles が返す。
- **旧 relay 撤去**: アシスタント生テキストの @role 走査は行わない（誤爆源）。
- **hop 上限撤廃**: lead⇔specialist の往復対話を許容。代わりに 1 人間メッセージあたりの軽い turn 上限で暴走を防ぐ。
- 委任は plugin ツール経由とし、bridge webhook パスに依存させない（直接入力 turn でも動く）。

### 未確定
- bridge のエンドポイント: `/ctl/post` + `/ctl/delegate` に分けるか、1 endpoint にまとめるか。
- 暴走防止の軽い上限の具体値。

### briefing / 受信ヘッダの書式
- 現状 `[<role>]` を本文の前に素で置くため「送信元」と誤解される（実測: procon-lead が "This message is addressed to @procon-lead ..." と解釈）。relay では `[<target>]` と `[from <role> in <token>, hop N]` が並び、plugin の system 注入も `[<role>] You are ...` で始まる。
- **決定**: 自己 identity は平文「You are the `<role>` role agent for Talk conversation `<token>`」に統一し、`[<role>]` マーカーを廃止。
- 受信ヘッダは明示形式 `From: <sender> (human|role)` / `To: you (<self>)` に統一。relay の hop もこのヘッダに含める。

---

## 2026-10-07 モデル選択 (venue 単位・ランタイム)

- **bridge は prompt 送信時に model を渡さない**。`session.model` が唯一の真実（実測: session テーブルに `model`/`agent` 列。未設定ならセッション作成時のモデルが使われる）。
- **`/ctl/venue` は `model` 必須**（`"<provider>/<id>"`、例 `opencode/space-bunny-free`）。leader session に適用。
- **新規 role は leader のモデルを継承**（`/ctl/bot`。`model` で個別上書き可）。leader のモデル = venue のモデル。
- **`/ctl/model { token, model }`** で venue の全 session の model を一括切替。opencode の `POST /api/session/<id>/model`（body `{model:{providerID,id,variant?}}` → 204, "Switch the model used by subsequent provider turns"）を各 session に呼ぶ。**ランタイム・再起動不要**。
- 個別 session の切替は opencode API / TUI でそのまま可能。
- registry に `model` 列（`ALTER TABLE ... ADD COLUMN IF NOT EXISTS`）。`/ctl/roles` が model も返す。
- **既定値は持たない**（フォールバック注入なし）。
- 実測: `/ctl/model` で kumo-lead の session.model が `opencode-go/glm-5.3-flash` → `opencode/space-bunny-free` に切替わることを確認。

### delegate の Talk 投稿は短い通知のみ (2026-10-07)
- `/ctl/delegate` は委任本文を全量投稿せず、**短い通知**だけを出す:
  `（システム）<target> にプロンプトを投げました: <先頭60字>…`（60 文字超は省略、改行は空白に畳む）
- 送信者は delegator の bot。**対象 role へは全文を turn として配送**（配送は不変）
- 理由: 全量投稿が Talk 履歴を思った以上に占領したため

### モデル運用: session.model は drift する（2026-10-07 実測）
- `/ctl/model` は `session.model` を書くだけで**自己修復しない**。设置为 1 分後に別のモデルへ revert され、3 時間そのままだった実測がある（procon-lead: `deepseek-v4.1-flash` → space-bunny-free → 1 分後に deepseek に戻る → compaction 後に戻る）
- 原因: opencode はモデル切替を info ログに残さないので、TUI 操作か自動再解決かを区別できなかった
- **決定: dispatch 時のモデル強制は実装しない**（監視で足りるとの判断）
-  defenses は billing 側: **console の `Use balance` を OFF** にする。OFF なら Go 上限時に「課金」ではなく「失敗」になるので、silent な課金は起きない
- 運用: drift 発見時は `/ctl/model` を 1 回叩く。新規 role は venue model を継承するので Go には乗らない
- Go usage の権威値は API key で取得可: `curl -H "Authorization: Bearer $(jq -r '.["opencode-go"].key' ~/.local/share/opencode/auth.json)" https://opencode.ai/zen/go/v1/usage`。2026-10-07 時点で monthly=rate-limited 100%（rolling/weekly は 0%）。Zen 残高は API key では取れず console の auth cookie が要る

---

## syoch.org 側 LDAP + agent アカウント設計（2026-10-07 決定）

nnctrobo 側の LDAP 実装（`~/ghq/github.com/nnctroboticsclub/infrastructure`）が
設計の雛形。nnctrobo は部活名前空間なので **syoch.org 側に独立して導入**する。

### 名前空間
- suffix: **`dc=id,dc=syoch,dc=org`**
- OU: `ou=Users` / `ou=Groups` / `ou=Services` / **`ou=Meta`**
- **決定: lastUID / lastGID カウンタを `ou=Meta` へ移動**（nnctrobo では `ou=Groups` の
  `objectClass: device` に置かれており、グループと型が混在していた）
- 已知の弱点（受け入れる）: `fetch → +1 → modify` は **read-then-write で非原子**。完全並列化すると
  uid 重複の恐れがある。`max(uidNumber)+1` 採番に置き換える案は不採用

### 名前付け（命名規則を二重に持たない）
- **uid = venue の role 名そのまま**（`procon-lead`, `kumo-lead` …）。唯一の出典は registry
- **グループ cn = venue slug**（`cn=procon`）。NextCloud のグループと 1:1 になり
  Deck / Calendar / Talk の共有がネイティブに効く

### 認証
- **1 agent = 1 LDAP アカウント、per-agent ランダムパス**
- パスは**非対称鍵（age）で暗号化して** opencode クライアント側に渡す。プレーンでは残さない
- 鍵は SOPS 用の `keys/` と**分離**（共用だと SOPS で復号できる鍵で agent 鍵も解けてしまう）
- sssd は nss/pam 用の**配角**。agent はログインせず WebDAV/OCS に直接 LDAP bind する
- NextCloud `user_ldap` は bind でユーザ解決し `ldapGroupMemberAssocAttr=memberUid` でグループ化

### API（最小 2 つ）
- `POST /ctl/role { token, role }` — uid 作成 + `cn=<slug>` へ memberUid を追加。冪等
- `GET /ctl/role?token=` — role 一覧と LDAP 状態
- **作らないもの**: グループ専用 API / パス再発行専用 API（`rotate: true` で要件）/
  NextCloud read endpoint（LDAP 経由adeh で直接読める）/ 独自テーブル（registry が既に source of truth）

### 実装フェーズ
1. `services/openldap.nix`（`dc=id,dc=syoch,dc=org`、inetOrgPerson + posixGroup + device スキーマ）
2. `ldifs/initial.ldif`（`ou=Meta` に lastUID/lastGID、Admins/Everyone/Services グループ）
3. `services/sssd.nix`（nss+pam、ログイン用）
4. NextCloud `extraApps` に **`ldap`** を追加（現状 `app:enable user_ldap` は**断言だけ**で app が無く無言で通っている）
5. `ldap:set-config` を `nextcloud-custom-config` に追加
6. `/ctl/role` を新設（occ と同じ `nextcloud` user で `ldapadd`/`ldapmodify` を呼ぶ）
7. 既存 14 セッション分の uid を batch 投入

---

## 2026-10-13 opencode 側で Talk 統合を持つ案 — 実測した制約

ユーザー提案: 「bridge を挟まず、opencode 側で bot secret を持ち webhook サーバーを持つ」。
以下は実機で確認した事実。

### 追い風: desktop から Talk OCS API に直接届く（旧前提の撤回）
- `POST https://nextcloud.syoch.org/ocs/v2.php/apps/spreed/api/v1/bot/<token>/message` を
  desktop から叩くと **本物の OCS XML（statuscode 400, 署名なし）** が返る。`server: nginx`、
  CF Access の 302 は出ない。
- **旧記述「desktop から Talk API への直接投稿は Cloudflare Access に弾かれる」は現在は該当しない**。
  → **opencode（desktop）が bot secret を持って直接投稿する設計は成立する**。
- sv01 origin へも tailnet（`https://100.96.100.1`）で到達可能。

### 障害 1: plugin は HTTP ルートを生やせない
- `@opencode-ai/plugin` の `Hooks` は `event` / `config` / `tool` / `auth` / `provider` /
  `chat.message` / `chat.params` / `chat.headers` / `permission.ask` /
  `command.execute.before` / `tool.execute.before|after` / `shell.env` /
  `experimental.*` のみ。**ルート登録フックは存在しない**。
- → webhook 受信を plugin 単体では実装できない。選択肢は
  (a) 薄い inbound sidecar（HMAC 検証 + ローカル opencode へ転送だけ）か
  (b) Talk を定期 poll して inbound を無くす（bot が会話を読めるかは未確認。bot は通常 session を持たない）

### 障害 2: bot lifecycle は occ 必須
- `talk:bot:install` は occ 専用（OCS では install できない）→ install は sv01 側が要る
  （SSH exec で叩く / bot を事前プロビジョニングする）。

### 障害 3: inbound 到達性
- 現 bot URL は `http://127.0.0.1:8787/hook/<token>/<role>`（**sv01 の loopback**）。
  受信を desktop に移すなら **tailnet アドレスの URL** に変える必要がある（Talk → desktop は tailnet で届く）。

### 運用メモ
- `talk:bot:list -v` は **secret を出力する**。実測で dotfiles-lead の live secret をセッションに
  露出させた（2026-10-13、要 rotate 検討）。`-v` は使わない。id は `install` の stdout `ID: N` を直接パース。
- イベント読み取りは **SSE + 定期 reconcile** で合意（ユーザー）。

### nudge ゲートを [talk-msg] マーカー方式へ (2026-10-15)

- 症状: nudge が全セッションで無条件に発火し、NextCloud 認証情報を持たない
  セッションやローカル入力のターンでも "nothing to say" の空ターンを生んでいた。
- 修正: talk-poll.py の deliver() が Talk 由来プロンプト先頭に `[talk-msg]` を
  付与し、plugins/talk-post.ts はそのマーカーを持つターンだけを nudge 対象に
  する。マーカーは「Talk への返答が期待されるターン」の唯一の signal で、
  未绑定セッションにはそもそも配送されない（user 提案の方式）。
- nudge の結末を `[talk-post] nudge accepted|declined` としてログ出力
  （ハーネスフィードバック収集の第一歩。nudge が元を取っているかの計測用）。
- 実測: smoke test 8/8 PASS、実セッションへの deliver で `[talk-msg] ...` を
  確認済み。レシーバーは再起動済み。**プラグイン反映には opencode 再起動が
  必要**（再起動までは旧挙動のまま）。
- 発見（未修正）: system.transform の briefing は resolveRoute が空のブリッジ
  registry を見るため bound:false を返し、全 venue セッションで注入されない
  （dotfiles 2 セッションで実測確認）。talk_bind を情報源に移す必要がある。
- 付記: nudge の promptAsync は SDK v1 に delivery 型が無く未指定のまま
  （idle 直後の race は軽微と判断し放置）。
