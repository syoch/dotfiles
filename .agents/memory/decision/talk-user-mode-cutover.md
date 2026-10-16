# Talk user モードへの切替（bot 廃止）

2026-10-13、Kumo を試験場にして bot 経路を user 経路へ切替。ロール全体展開はまだ。

## 最終アーキテクチャ

- **受信**: user には webhook が無いので long-poll。
  `GET /ocs/v2.php/apps/spreed/api/v1/chat/<token>?lookIntoFuture=1&limit=20&format=json&timeout=20&lastKnownMessageId=<cursor>`
  - 新着 200 + ヘッダ `X-Chat-Last-Given` が真の cursor
  - 新着なし 304（空 body、正常系）
  - **`ocs.data` はそのままメッセージ配列**。`{messages:[]}` ではない。
  - フィールドは `actorId` / `actorType` / `actorDisplayName` / `systemMessage`。`authorId` 系ではない。
  - `actorId` は human では数値、他 actor では `"cli"` のような文字列。int 変換すると落ちる。
  - `systemMessage` 付き（"An administrator added you" 等）は system 通知なので除外。
- **送信**: `POST .../chat/<token>?format=json` body `{"message":...}`。
  **201 Created が成功**（200 判定 simplistic だと false negative になる）。
- どちらの送受信も NextCloud ユーザー app password で行う。bridge は経由しない。
  Cloudflare Access は app password の OCS アクセスを阻害しない（2026-10-13 実測で 200）。
- 資格情報は long-poll receiver 側だけが保持し、plugin は読まない。
  receiver が `POST 127.0.0.1:8790/ctl/post` を公開し、talk-post はここを先に試して
  404 のときだけ既存の bridge に fallback する（bot セッションとの互換維持）。

## 落とし穴（すべて実際に踏んだ）

1. **`ldapctl.py ensure-agent` は既存 uid では no-op**。新規生成した LDAP パスワードが
   反映されず、`user:auth-tokens:add --password-from-env` が古いパスワードで走るため
   **限定 token（49 文字）が発行され、OCS 認証は 401**。
   正しいのは「作ってから必ず `set-password`」。full token は 72 文字。
2. **`user:auth-tokens:list` のパース**: 表の罫線 `+-----+` や `lastActivity` の
   タイムスタンプをトークン ID と誤読すると `auth-tokens:delete` が壊れる。
   awk で ID 列だけを拾う。`grep -oE '[0-9]+'` は全数字を拾うので不可。
3. **occ の出力構造**: `app password:` の次に秘密が次の行。`$(...)` は末尾改行を落とすので
   秘密は `tail -n 1` で取得する。
4. **Cloudflare は python-urllib の既定 User-Agent を弾く**。HTML ’interstiが返り、
   遠い原因で `JSONDecodeError` に見える。`User-Agent: Mozilla/5.0` を必ず付ける。
5. **cursor は処理完了後にだけ保存する**。先に保存してパースが失敗すると、
   未配信メッセージが「既読」扱いになって永久に失われる（実際に 1 件失った）。
6. 自作の long-poll で sv01 自身から大量認証すると **bruteforce 429** になる。
   認証確認は laptop から。throttle 状態は Redis (`LDAP-user_ldap-s01-*`) に居る。
7. `prompt_async` の `delivery` は必ず `"queue"`。既定 `"steer"` は走行中の turn に
   注入し、返信が親 policyless で回収されず消える。

## 切替手順（踏んだ順序）

1. 事前告知を Talk に流す（切断前に必ず通知）
2. talk-post を user モード優先に書き換え → **opencode 再起動で反映**
   - `~/.config/opencode/tools/` は repo への生 symlink なので編集は即反映されるが、
     ロードは再起動時。`opencode.service` 内で動いているセッションから素の
     `systemctl --user restart` は自分を殺すので `systemd-run --user` の別ユニットにする。
3. user identity で発話できることを確認（bot が居る状態でも確認する）
4. Registers `DELETE /ctl/bot?token=...&role=...` で bot を撤去（bridge registry も消える）
5. 撤去後に再度送受信を確認

**教訓**: bot 撤去は必ず「新しい送信経路が user identity で実証済み」の**後**に行う。
先に消すと返信が途絶える。

## role 間ルーティングは @mention 方式(2026-10-13 決定)

`talk-delegate`(bridge 実装) は使わず、**純粋に @mention** で役割分担する。
bridge を撤去しても Mention 経路が生き残るので、bot 廃止の前提になる。

受信側 rule (`should_deliver`):
- `is_leader=1` → 人間のメッセージは**常に**受け取る
- `is_leader=0` → **@自分 が付いた時だけ**
- 他の role からのメッセージ → **@自分 が付いた時だけ**
- 自分の投稿・`systemMessage` は除外(ループ防止)

判定は本文の `@名前` ではなく `messageParameters` の **`mention-id` / `id`** で行う。
表示名は後から変更され得るので本文パースは壊れる。
実測構造: `messageParameters.<placeholder> = {type, id, name, mention-id}`。

user モードでは role の発言も人間の発言も actorType が `users` になるので、
**どちらの role 宛かを判別するには talk_bind 全行の numeric actor id を控えておく**
必要(`role_index()`)。これが 1 会話に複数のロールが居る場合の前提。

## receiver は systemd user unit(`talk-poll.service`)

`~/.config/systemd/user/talk-poll.service`、自動起動 + `Restart=always`。
`--serve 8790` で user 身份的 送信 API も公開。
スクリプトは `/tmp` ではなく **repo 内** `modules-hm/apps/opencode/talk-poll.py`
(autostart が参照するので repo に置かない)。

## 移行完了 (2026-10-13)

B (置換してから削除) で全 15 ロールを user モードへ移行済み。
bot 0 個 / bridge registry 0 行 / talk_bind 15 行。

**会話**: procon(9) / kumo / iwara-rev / circuitmaker2 / dotfiles(2) / esp32

**切替手順(この順序が正)**:
1. その会話の bot を撤去 (webhook が解決されなくなる = bot が沈黙)
2. **bot 撤去後に** cursor (`X-Chat-Last-Given`) を読む
3. talk_bind にその cursor で投入

cursor を 1 の**前**に読むと、bot が既に回答済みのメッセージを poller が
再処理して**二重回答**になる。無応答は 2〜3 秒で済むが、これは避けられない。
逆順にすると無応答 0 の代わりに二重回答が増えるので、そちらを選ぶ方が悪い。

**自分自身の会話は必ず最後に回す**。移行中に報告手段を失うとMLE できない。

**group 名**: セッションの working directory の basename を小文字化
(`CircuitMaker2` → `circuitmaker2`)。会話 token(ハッシュ)ではない。
セッション API の `directory` から解決するのでスキーマ変更が要らない。

**Provisioning の順序**: LDAP user 作成 → NextCloud の LDAP キャッシュを
Redis flush → **LDAP パスワードで 1 回認証**(ここで NextCloud がユーザーを
自動 provisioning) → room:add → app password 発行 → 検証。
`room:add` は NextCloud にユーザーが存在.Insertial 必要なので順序を逆にしない。
app password の検証を `room:add` の**前**に chat endpoint で行うと
「未入室だから当然 404」になり、全ロール FAIL に見える。

** backs**: bridge registry の dump は `/tmp/opencode/talk_agent_backup.sql.gz.b64`。

## 受信テストで見つかったバグ: rich-object placeholder (2026-10-13)

spreed の `message` フィールドは**生のテンプレート**を返す。mention を含む
メッセージは `{mention-user1}` という placeholder 入りで、表示名は
`messageParameters` 側にある。これをそのまま agent に渡すと
「mention が届いていない」と誤解される(実際は配送は成功している)。

`render()` で `messageParameters` を辿り `{key}` を実際の名前へ置換する。
key が `mention` で始まれば `@` を付ける。それ以外は `name` をそのまま使う。

**判断の原則**: テストで「壊れている」と見えても、まず
`messageParameters` を確認して**ルーティング自体は成功していないか**を切る。
ルーティング判定は `mention-id` で行っているので、placeholder の表示と
配送は別のレイヤーである。

## 重複看起来した误会の切り分け

「同じ文言が 2 本ある」→ 二重配送と誤認しやすい。確認手順:
1. receiver ログの `delivered` 件数を数える
2. 会話の message `id` に重複がないか見る(別 id なら別メッセージ)
3. poller は cursor 基準で 1 メッセージ 1 回だけ delivery する

なお **at-least-once**: 配送成功と cursor 保存の間でプロセスが落ちると
再起動時にその 1 通を再生する。 通常運用の重複は出ないが、
厳密には at-most-once ではない。

## 移行後に壊れる tool

`talk-roles` / `talk-delegate` は bridge 経由で venue を解決するため、
bot 撤去後は `this session is not bound to a Talk venue` で失敗する。
`talk-post` と同じく user モード(または talk_bind 直読み)へ移す必要があり、
反映には opencode の再起動が要る。

## 共有フォルダは lead 所有・`/shared` に一本化 (2026-10-13 決定)

ファイルごとに共有するのではなく、**lead アカウントの `/shared/` を作り、
group に perms=31(read|update|create|delete|share)で共有**する。
各ロールはそこに書き込む。

理由:
- **パスが一致する**。ファイル単位の共有は受け手のルートへ flat マウントされ
  `/report.md` に化けてフォルダ構造が消える。フォルダ共有なら全員 `/shared/`。
- **書き込みが自然に成立する**。perms=31 なので各ロールが自分で置ける。
  lead が全部書く集中管理は不要。

**代替案は却下**: 専用の共有アカウント(`dotfiles-share` 等)を所有者にすると
lead アカウントの寿命から切り離せるが、構成要素が増えて運用が難しくなるので
lead 所有が simplicity(要素の少なさ)を優先して採用。所有者とバックアップが lead アカウントに
帰属する、というトレードオフは承知の上。

**`nextcloud_files` の `publish`**:
- 既定パス `/shared/<title>.md`
- lead なら `/shared` が無ければ MKCOL → group 共有(冪等。既に group 共有済みなら何もしない)
- lead 以外で `/shared` が無い、または共有されていない場合は、**黙って失敗せず**
  「lead に先に publish してください」と返す
- 戻り値は `/f/<fileid>` リンク(トークン無し・認証必須)+ 文字数 + 共有先

**実測**: lead が作成→非 lead が `/shared` を見える(207)、lead のファイルを
読める(200)、`/shared` に書き込める(201)、lead が書き戻しを読める(200)。

`share_link`(公開リンク)action は**削除**した。`/f/<id>` ならアクセス制御を
保ったままリンクを貼れるので、公開リンクを作る必要がない。

## Deck の venue ごとの board (lead 所有) (2026-10-13)

`/shared` と同じく **lead 所有**で統一。board は会話ごとに 1 枚。

**作成手順(実測済み)**
1. `POST /ocs/v2.php/apps/deck/api/v1.0/boards` — **`title` と `color` が両方必須**。
   `color` を省くと 400 `color must be provided and must be not empty`。
   BoardOcsController::create の引数が `string $title, string $color` で非 nullable。
2. `POST .../stacks` を 3 枚 (To Do / In Progress / Done)。`boardId` と `title` が必要
3. `POST .../boards/{id}/acl` で各ロールを追加。`type=0`(user) + `participant=<uid>`、
   `permissionEdit=true` / `permissionShare=true` / `permissionManage=false`(lead 以外は false)

ACL を入れると非 lead ロールも board を読めるWRITE できる
(`PERMISSION_MANAGE` は lead だけが true)。

**dotfiles 会話の board: id=5 "dotfiles tasks"** (owner=dotfiles-lead, stacks 24/25/26)。

## Deck API の落とし穴(すべて実測)

Deck 1.19.0 / NC 35 では **ocs セクションと非 ocs セクションで URL が違う**:

| 操作 | 動く URL |
|---|---|
| board 一覧 | `GET /ocs/v2.php/.../boards?format=json` |
| stacks(+カード埋め込み) | `GET /ocs/v2.php/.../stacks/{boardId}?format=json` |
| カード作成 | `POST /ocs/v2.php/.../cards` (form: title/stackId/type/description) |
| 自分への assign | `POST /ocs/v2.php/.../cards/{id}/assign` (form: `userId=<uid>`) |
| **カード削除** | **`DELETE /index.php/apps/deck/cards/{id}`** ← ocs ではない! |

- `GET /index.php/apps/deck/api/v1.0/boards/{id}/stacks` は **200** だが
  `/ocs/v2.php/.../boards/{id}/stacks` は **404**。`/index.php` 側だけが生き残る変 則がある。
- `/cards` 系の GET は**全部 405**。カード一覧は stacks 応答に埋め込まれて返る
  (`cards[]`)ので、平坦化して使う。
- `card_ocs#update`(PUT /ocs/.../cards/{id}) は**引数が全部非 nullable で
  400 になる**ため実質使えない。 Boards/cards を触るときは**削除だけ非 ocs 経路**を使う。
- 削除済みカードは `DELETE` を重ねると **403 `Card is deleted`** になる。

**タスク管理は read-modify-write なので競合注意**: 更新はカード全体を送り返す
必要があり、2 ロールが同時に触ると後勝ちで片方の変更が黙って消える。
Deck を hot path の排他協調には使わない。人が読む進捗 board として使うのが安全。

**`assignedUsers` の形**: `[{id, participant:{primaryKey,uid,displayname,type}, cardId, type}]`。
「自分にアサインされた open カード」は
`boards[].stacks[].cards[]` を走査し `assignedUsers[].participant.uid == 自分の uid`
かつ `archived !== true` で判定できる。**API 側に assignee フィルタは無い**ので必ず全走査。

## Deck の書き込み操作は使える(訂正) (2026-10-13)

**前の記述は誤り**。Deck はタスク管理に十分使える。

実測した OCS 書き込み(すべて 200):
| 操作 | URL / パラメータ |
|---|---|
| カード作成 | `POST /ocs/v2.php/.../cards` (title/stackId/type/description) |
| 自分へ assign | `POST /ocs/v2.php/.../cards/{id}/assign` (`userId=<uid>`) |
| **stack 間移動** | `PUT /ocs/v2.php/.../cards/{id}/reorder` (`stackId`,`boardId`,`order`) |
| **Done 列にする** | `PUT /ocs/v2.php/.../stacks/{stackId}/done` (`boardId`,`isDone`) |
| カード削除 | `DELETE /index.php/apps/deck/cards/{id}` (ocs ではない) |

- `reorder` で 24 To Do → 25 In Progress へ実際に移動することを確認。
- `setDoneStack` は **`boardId` と `isDone` が両方必須**。片方だと 400。
  設定すると stack の `isDoneColumn=true` になり、完了判定に使える。
- `card_ocs#update`(カード本文の編集)だけが非 nullable 引数で 400。
  タスク管理には不要(タイトル/本文のHumans による編集は UI で十分)。

**read-modify-write の競合は過小評価していた**。ロールは自分の担当カードを
触るため同一カードの同時編集はほぼ起きない。ただし移動が read-modify-write なので、
同一 stack 内の `order` 調整は排他していない点だけ留意。

**Board 作成の必須引数**: `title` と `color`(非 nullable)。
`POST /ocs/v2.php/.../boards` に両方 있어야 200。

**「open カード」の定義**: `archived != true` かつ、その stack の
`isDoneColumn != true`。`Done` 列を `setDoneStack` で有効にしておけば
stack の位置だけで判定できる。

## board ACL は Project Group 単位 (2026-10-13 決定)

board ごとにユーザーを列挙せず、**group 単位の ACL 1 個**配备する。

`POST /ocs/v2.php/apps/deck/api/v1.0/boards/{id}/acl` に
`type=1`(group) + `participant=<group名>` + `permissionEdit=true` /
`permissionShare=true` / `permissionManage=false`。

**これが全 Project Group ユーザーの書き込み可能を満たす**。
検証: board 5 の ACL を group エントリだけにしたら、ACL に明記されていない
`dotfiles-skill-writer` が board を読めて・カード作成・assign・move できた。

- **group エントリだけで十分**。ユーザーを個別に足すと、ロールが増えたときに
  差分を更新し続けることになる。
- **group エントリでも MANAGER 権限は要らない**。作成/assign/move は全部通る。
  board 自体 EXPECT 版の削除や stack の Done 化は lead が行う。
- 所有者(lead)の type=0 エントリは自動生成されるので触らない。

**注意: `board_ocs#addAcl` は 200 を返すが、411/404 の経路がある。**
ACL の削除は **非 ocs** 経路 `DELETE /index.php/apps/deck/boards/{id}/acl/{aclId}`。

**group ACL 削除の事故**: user エントリを消すつもりで group エントリも
一緒に消した。id を必ず確認してから削除する。

## nextcloud-deck の action 一覧

| action | 動作 |
|---|---|
| `mine` | **自分にアサインされた open カードを列挙**(主用途) |
| `take` | 未アサインのカードを自分の take にclaim |
| `create` | カード作成 + 自動 assign 自分 |
| `move` | stack 間移動 (stack は**タイトル**指定) |
| `boards` / `stacks` / `cards` | 参照のみ |

- `mine` は全 board を走査し `isDoneColumn` の stack を除外してから
  `assignedUsers[].participant.uid == 自分の uid` で絞る。
  **API に assignee フィルタは無い**ので必ず全走査。
- `board_id` は `mine` では任意(見えている board 全部)、他では必須。

**reorder は `order` が必須**: `card_ocs#reorder(int $id, int $boardId,
int $stackId, int $order)` で全引数非 nullable。`order` を落とすと
**body 空の 400** になり、権限不足と区別がつかない。常に `order=999` を渡す。

**card 本文の編集はできない**: `card_ocs#update` が非 nullable で 400。
タスク管理には不要( humans が UI で編集する)。

## nextcloud-files publish の冪等性バグ(2026-10-13 実測・修正済み)

2 つ続けて踏んだ。どちらも「空か存在しないか」の判定方法が原因。

**1. PROPFIND 404 で abort する**
`propfind()` は 2xx 以外を throw する。存在しないコレクションは WebDAV が 404 を
返すので、venue で最初の publish した瞬間に bootstrap に到達せず必ず失敗する。
→ 404 を「未作成」として捕捉する。

**2. 「エントリ数 0 = 未作成」は誤り**
`propfind()` は自分自身の `<d:response>` を slice で落とすので、
**存在して空のフォルダは 0 件**として返る。存在しないフォルダも 0 件。
区別する唯一の方法は **PROPFIND の status コード**(`folderExists()`)。
判定基準をエントリ数にすると、publish のたびに bootstrap が再実行され、
**group 共有がpublish 回数だけ重複して増える**。
MKCOL が 405(=既に存在)を返すのが徵候。

**検証**: 3 回連続で publish して group 共有が 1 件のままであること、
別ロールから 200 で読めることを確認。

## tool の実測結果 (dotfiles board 5)

- `mine` / `create` / `move` / `take` すべて期待どおり動作
- `move` で Done 列に入れると `mine` から消える(`isDoneColumn` で除外)
- `/shared` は group 共有 1 件のみ、内容は空

## project-provision: プロジェクト作成の 4 ステップ (2026-10-13 決定)

`scripts/project-provision`。作成は **lead だけ**に絞って単純に:

1. lead ユーザー作成(opencode セッションも作成)+ `talk_bind` 書き込み
2. Talk room 作成(lead 所有)
3. Deck board 作成(lead 所有、group ACL)
4. 共有フォルダ `/shared` 作成(lead 所有、group 共有)

`add-role` でロール追加、`bind` で既存セッション紐付け、`status`、`teardown --yes`。

**レシーバーは 10 秒ごとに `talk_bind` を読むので新規ロールは再起動不要で拾う。**

### 実装中に踏んだ罠(全部 401 という同じ症状で出る)

1. **LDAP 作成後に NextCloud の Redis を flush しないと 401**。
   NextCloud は LDAP 照会を Redis にキャッシュし、**存在しなかった uid の
   負キャッシュ**も持つ。Bad パスワードに見えて原因はキャッシュ。
2. **ssh の環境変数でパスワードを渡すと空になる**。ssh は既定で
   リモートへ env を転送しない(`SendEnv` 未設定)→ occ が NC_PASS="" を受け
   **限定 token** を発行 → 401。パスワードは**スクリプト本文**(stdin)へ埋め込む。
3. `occ()` に `shift` を入れたせいで `$1`(サブコマンド)が落ちていた。
   スクリプト本文が関数定義だけなら `shift` しないこと。
4. **Deck の非 ocs ルートには `OCS-APIRequest` ヘッダが必須**(無いと 412 CSRF)。
   対象は board / card / acl の DELETE。
5. `ldapctl.py list_groups()` は型注釈 `list[str]` だが実際は
   `(cn, gidNumber, members)` タプルのリスト → `cn=(...)` で malformed filter。

### ldapctl.py に追加したコマンド

`delete-user`(グループ所属を先に除去してから uid を削除)/
`delete-group`(メンバーが残っている場合は拒否)。
provision と後片付けが対で揃わないと孤立が残るので必須。

### teardown の限界

**失敗した run の孤児は消せない**(manifest に無い session/board)。
board の所有者が LDAP 削除済みだと認証できなくなるので、
その場合は**一時的に LDAP user を復活させてから削除**する。
