# NextCloud Talk: bot → LDAP user 移行計画（2026-10-13 design 確定）

現状 = talk-bridge（sv01, Postgres `talk_agent`, HMAC webhook）が 6 venue / 11 role を bot で運用。
目標 = agent を LDAP 認証の NextCloud user 化し、bot と talk:bot:install を廃止。受信は opencode plugin の
long-poll supervisor、投稿は desktop→OCS 直（CF Access 阻害なし＝2026-10-13 実測）。

## 実測で確定した事実（brief の誤りを訂正）
- **`user_ldap` は NC35 本体に同梱済み**（`/nix/store/...nextcloud-35.0.1/apps/user_ldap`）。`app:enable user_ldap` は
  実際に有効化できる見込み。**`nextcloud35Packages.apps.ldap` という attr は存在しない**（apps 一覧に無い）。
  → 「extraApps に ldap を追加」は不能／不要。Phase2 の正しい作業は `ldap:set-config` + `app:enable`。
- NC35。spreed は `nextcloud35Packages.apps.spreed`（extraApps 経由）。Talk は本体同梱ではない。
- **`nextcloud35Packages.apps.notify_push` は存在**（現状未使用）。long-poll の worker 消費が問題化した場合の回避策。
- flake は `nixos-26.05` 固定（nextcloud35=35.0.1）。

## フェーズ（目的 / 手順 / 検証 / ロールバック）
- **P0 事前準備**: ①`/ctl/venues`,`/ctl/agents` で 6/11 の token・role・session_id・model をダンプ ②sv01 full backup
  （NC data+DB+config, `/srv/NAS/nextcloud`,`/var/lib/nextcloud`）+ opencode SQLite snapshot ③backup を別ディレクトリへ
  展開して復元ドライラン ④branch 凍結。検証=復元成功。RB=なし。
- **P1 LDAP 基盤（sv01）**: `services/openldap.nix`（dc=id,dc=syoch,dc=org / OU Users,Groups,Services,Meta /
  inetOrgPerson+posixAccount+posixGroup+device / lastUID,lastGID は ou=Meta）。`ldifs/initial.ldif`。
  nnctrobo `ldap.py` を CLI 移植。127.0.0.1:389 bind。検証=ldapsearch で OU/カウンタ可読、発行 round-trip、
  カウンタ read-then-write 非原子は許容と明記。RB=LDAP は新規なので unit disable（NC 無傷）。
- **P2 user_ldap 有効化（sv01・最高リスク）**: ①**人間 admin `syoch` が local に残ることを確認**（最重要安全装置）
  ②LDAP スコープを agent-only に絞る（human は当面 local）③`nextcloud-custom-config` に `ldap:set-config`
  （host/port/basedn/binddn/filter/`ldapGroupMemberAssocAttr=memberUid`）を追加 ④`app:enable user_ldap` の直前に
  直前スナップショット ⑤`occ ldap:test-config s01`→active=1→`app:enable user_ldap`。
  検証=test-config 成功 / `occ user:list` に test LDAP user 出現 / human が web login 継続可能 / group が見える。
  RB=`ldapConfigurationActive 0`→`app:disable user_ldap`；最悪 config.php/backup 復元。LDAP users は login 不能になるがデータは残る。
- **P3 agent アカウント + 認証（sv01+laptop）**: uid=role、group cn=slug を冪等発行（既存 11 role batch）。
  **NC app password を発行**（要契約確認: 自前生成 LDAP パスワードで Basic bind→OCS `core/getapppassword`。
  以後は app password のみ使用で LDAP パスは使い捨て化可）。app password を **SOPS 鍵と分離した age 鍵**で
  laptop へ暗号化配布（平文を残さない）。Talk 会話へ user を member 追加（`talk:room:add <token> --user <uid>`、
  LDAP 追加→NC 検出待ち→room:add の順）。
  検証=ldapsearch / agent user で OCS Basic 認証 200 / NC グループ所属 / 会話 member。
  RB=ldapdelete→group 除外→app password revoke→会話 member 除去。冪等。
- **P4 long-poll supervisor plugin（laptop・P1 と並列可）**: `talk_bind`(session_id PK, talk_token, uid,
  kind('bot'|'user'), secret, description, created_at, updated_at) を **opencode とは別 SQLite ファイル**に置く案を推奨
  （同居は WAL でも write 競合/SQLITE_BUSY リスク）。起動時に全 binding 列挙→per-binding async loop
  `chat/{token}?lookIntoFuture=1&timeout=30&lastKnownMessageId=`、lastKnownMessageId 永続、指数+jitter backoff、
  `session.deleted`+定期 reconcile で orphan 削除。**配送ポリシー（hub-and-spoke: human→lead+@mention、role→@mention のみ）
  を bridge から plugin へ移送**（全配送だと broadcast 爆発）。投稿は `talk-post_post` を OCS 直叩きへ変更、
  `talk-delegate`/`talk-roles` を plugin 内完結へ。自分の投稿 actor==self uid は無視（echo 防止）。
  検証=単体（binding 列挙/lastKnownMessageId/backoff）+1 venue E2E+反転テスト。
  RB=plugin 無効化（binding kind で bot と両立）。
- **P5 段階カットオーバー（1 venue ずつ）**: pilot=活動最少 venue。**role 単位で atomic**（bot webhook 停止
  →user long-poll 有効を同時に、kind 切替で排他）。切替時 lastKnownMessageId を切替直前から開始し gap を replay。
  検証=human 発言に lead 応答/Role 間 delegate/二重投稿なし/沈黙なし。RB=kind を戻し bot 再 install（session_id 不変）。
- **P6 bot 全廃 + bridge 縮小**: 全 venue user 化後 `talk:bot:uninstall` 全除去。bridge/registry を停止（削除は
  1〜2 週間遅延）。tunnel の `-L 8787` を外す。検証=`talk:bot:list` 空/bridge 停止でも全 venue 動作。

## クリティカルパス / 並列
CP = P0 → P1 → P2 → P3 → P5 → P6。P4（laptop）は最初から並列可（E2E のみ P3 依存）。

## 混在運用の注意
- 二重投稿防止は「同一 role に bot webhook と user poll を同時に生かさない」を kind で厳守。
- 二重管理破綻（Postgres と SQLite の drift）: 遷移中は role がどちらか一方のみに存在する不変条件 + 両方に
  現れたら alert する reconcile。P5 以降 SQLite を唯一の真実に。
- long-poll は 1 binding = PHP-FPM worker 1 個を常時占有（webhook と違い数に比例）。11 件は許容だが
  binding 増で pool(120) 枯渇→site-wide 502 の恐れ。binding 上限 or notify_push 導入を用意。

## 決定 / 未決 / 残存懸念
- 決定: user_ldap は同梱なので extraApps 不要 / long-poll supervisor は opencode 側 / kind で bot・user 両立 /
  release-26.05 固定のまま実施（unstable 移行は migration 後に分離）。
- 未決: binding を opencode SQLite 同居 vs 別ファイル（別ファイル推奨）/ NC app password の正確な発行契約 /
  人間ユーザを LDAP へ移す時期 / pilot venue の選定。
- 残存懸念: user_ldap 有効化の login ブラスト半径（local admin 温存で緩和）/ CF Access 再導入時の long-poll 死 /
  user mention 抽出の実契約（`{mention-...}` の user 版）/ カウンタ非原子。

---

## Round 2 確定（2026-10-13・read-only 実測で事実対立を決着）

### 事実の決着（すべて実コマンド）
- **`user_ldap` は NC35 本体に同梱＋sv01 で既に有効**（brief/critic の「app 不在で no-op」は誤り）:
  - `ls .../nextcloud-35.0.1/apps` → `user_ldap` あり（57 apps、`notify_push`/`spreed` は非同梱）。
  - sv01 `sudo nextcloud-occ app:list` → `- user_ldap: 2.0.0-dev.0` が Enabled。
  - `nextcloud35Packages.apps` に `ldap` は無い（design 正）、`notify_push` は有る（design 正）。
  - → **extraApps 追加は不要**。P2 の作業は `ldap:set-config` + active=1 のみ。
- **LDAP ディレクトリは未稼働**（critic 正）: sv01 `systemctl list-unit-files|grep slapd`=NONE、`ss -ltn|grep :389`=NOPORT、`occ ldap:show-config`=空、`config:list user_ldap`= `configuration_prefixes: []`。→ P1 は greenfield。
- **バージョン更新（memory 旧記述の訂正）**: NC **35.0.1** / spreed **25.0.5**（旧 35.0.0/25.0.0）。NC が `notify_push` 非同梱＝push 未導入は正しい。
- **long-poll 契約（spreed 25.0.5 ChatController::receiveMessages）**: `GET /ocs/v2.php/apps/spreed/api/v1/chat/{token}`、`#requireParticipant`。`timeout` は **既定30・最大30**（`min(30,$timeout)`。memory の「最大60」は誤り）。**304 は正常（無メッセージ）**。更新カーソルは応答ヘッダ `X-Chat-Last-Given`。app password(Basic) 認証で participant なら成立。
- **app password 発行の制約（core AppPasswordController::getAppPassword）**: `GET /ocs/v2.php/core/getapppassword` は **app-password セッションでは発行不可**（`session->exists('app_password')` で 403）。→ P3 は生成 LDAP/実パスワードの非 app-password セッションで一度だけ mint する必要。
- **cleanup の実体（user_ldap Jobs/CleanUp.php）**: `isCleanUpEnabled()=(bool)getSystemValue('ldapUserCleanupInterval',60)` → **0 で無効化**。`checkUser` は `mapping->getList()`（＝LDAP マップ済ユーザのみ）を回り `dui->markUser()`（isDeleted フラグ）を立てるだけで、**ローカル(Database backend)ユーザは一切対象外**。critic「ローカルユーザ削除の不可逆」は過大（フラグのみ・データ削除なし）。

### routing 再設計（fan-out 抑制）
- **bridge の hub-and-spoke 判定を supervisor へ移設**。各 binding が room を long-poll し、以下で自分の turn だけ起動:
  - 自己投稿（actor uid==自分）は無視。system/non-chat は無視。
  - author=human → **leader は常に**、他 role は **@自分 のときのみ**。
  - author=role → **@自分 のときのみ**。
  - leader は talk_bind の `is_leader`（=venue 最古 role）で表現。
  - mention は本文 regex でなく構造化 `mentions`（`mention-user`）を優先（要実契約確認）。
  - human 1 通あたりの delegate budget を supervisor 内で維持（旧 bridge と同値）。暴走上限。
- 1 通で起動する turn は最大 `1 + #mention` に有界。

### 真実源の確定
- **移行期（P4–P5）は Postgres registry（bridge）を authoritative**、laptop SQLite は **cursor/キャッシュ（非・真実）**。plugin は startup + 定期 reconcile で bridge から binding を取得（`/ctl/route` 拡張）。理由: plugin は既に tunnel 経由で bridge に到達でき、両書きを避けられる（critic#3 解決）。
- 切替 commit は **`UPDATE talk_agent SET kind='user'` の 1 行**。bridge は kind='user' の webhook を dispatch しない、plugin は kind='user' のみ long-poll。単一 writer。
- **P6 で bridge 退役時に SQLite を authoritative へ昇格**（registry 移設）。
- 不変条件: 任意の (token,role) は bot XOR user の一方のみ。reconcile が「Postgres と SQLite の不一致」「talk:bot:list に在るのに registry が user（ghost）」を alert。session.deleted はクラッシュで来ないため **定期 reconcile で opencode の session 列挙と突合**して orphan 削除。
- supervisor は **(uid) 単位の lease**（owner pid + TTL）で多重起動を排他。

### user_ldap ロールバック（cleanup 無効化込み）
- 事前: local admin 温存、`ldapUserCleanupInterval=0`（cleanup 無効）、直前 full backup。
- 手順: `occ ldap:set-config s01 ldapConfigurationActive 0` → `occ app:disable user_ldap`（local user 無傷）→ 必要なら remnants フラグは再 active 化で解消。
- 限界: LDAP プロビジョン済 agent uid は LDAP off で login 不可・app password 無効化。投稿済メッセージは uid で残る。**ローカルデータの不可逆損傷は無し**。

### per-role atomic cutover（二重投稿ゼロ・取りこぼしゼロ）
1. 前提: agent user + app password 準備、registry に role 行、cursor 記録。
2. 切替直前の last message id を記録。
3. `kind='user'` へ atomic 更新（commit 点）→ bridge 側 dispatch 停止。
4. plugin reconcile が kind 変化を検知し、記録 cursor から long-poll 開始（gap は lookIntoFuture の履歴で回収）。
5. 検証: 人間の test 発言に **1 回だけ**応答。
6. Talk の bot participant 除去は最後。
- 順序保証: 「bridge は kind を見て dispatch しない」「plugin は kind='user' のみ poll」＋ cursor で重複なし。

### P2 縮小・新規決定
- P2 は「LDAP 構成 + active=1」のみ（extraApps/app:enable 不要）。
- 移行中は **nixpkgs 凍結**（dirty な flake.nix/flake.lock を先に commit）。unstable 移行は別タスク。
- **推奨（要ユーザー合意）**: risk 分離のため Track 分割 — Track1=NC **local user** で bot→user を先行（P1/P2 を CP から外す）、Track2=後段で LDAP へ移行。critic の代替案を採用。

---

## Round 3 最終確定（親 Plan 返却用・2026-10-13）

### フェーズ（目的/手順/依存/完了条件/ロールバック）
- **P0 凍結・backup**: dirty flake.nix/lock を commit(nixpkgs 凍結)、sv01 full backup(NC data+DB+config)、opencode SQLite snapshot、restore drill、6 venue/11 role inventory。依存=無。完了=restore 成功＋inventory 11 件。RB=無。
- **P1 LDAP 基盤(greenfield)**: openldap(dc=id,dc=syoch,dc=org, OU Users/Groups/Services/Meta, lastUID/lastGID=ou=Meta) + initial.ldif + ldap.py CLI 移植、127.0.0.1:389。依存=P0。完了=round-trip＋カウンタ増分＋bind。RB=unit disable(NC 無傷)。
- **P2 user_ldap 構成(extraApps 不要・有効済)**: local admin 温存確認、**B1** `settings.ldapUserCleanupInterval=0`(宣言)＋`occ config:system:set ldapUserCleanupInterval --value=0`、LDAP スコープ agent-only、`occ ldap:set-config s01 …(ldapGroupMemberAssocAttr=memberUid)`、`ldap:test-config s01`、active=1、直前に snapshot。依存=P1。完了=test-config 成功＋`occ user:list` に test user＋human login 継続＋cleanup no-op。RB=active 0→app:disable。
- **P3 アカウント+認証**: uid=role / group cn=slug 冪等発行。**B6** 非 app-password セッション(生成 LDAP パス Basic)→ `GET /ocs/v2.php/core/getapppassword` で mint→以後 app password。`talk:room:add <token> --user <uid>`(participant は group 共有と独立)。age(SOPS 分離鍵)配布。依存=P2。完了=agent uid で OCS Basic 200＋room participant＋app password で chat 取得。RB=revoke/ldapdelete/participant remove(冪等)。
- **P4 supervisor(laptop, P1 と並列)**: talk_bind SQLite(cursor/キャッシュ非真実)。**B2** app password で `chat/{token}?lookIntoFuture=1&timeout=30` 成立を最初に確証。**B3** routing gating を非 LLM コードで明文化(self-echo 無視/human→leader+mention/role→mention/budget/leader=is_leader)。`X-Chat-Last-Given` 永続、304=正常(短 sleep)、401=停止+surface、lease(uid)、post は OCS 直。依存=P3(E2E)。完了=B2 E2E＋反転テスト＋fan-out≤1+#mention 単体。RB=plugin 無効化。
- **P5 cutover(per-role atomic, drain)**: **B4/B5** ①`POST /ctl/drain{token,role}` で webhook dispatch 停止＋in-flight 待ち ②切替直前の最終 msg id を `last_processed` として registry 永続 ③`UPDATE talk_agent SET kind='user'`(単一行 commit、単一 writer) ④plugin は kind='user' のみ poll、`lastKnownMessageId=last_processed` から gap 回収 ⑤処理済 msg id を永続し**冪等 dedup**(gap と overlap の二重防止) ⑥検証後 Talk の bot participant 除去は最後。依存=P4,P3。完了=二重投稿ゼロ/沈黙ゼロ/gap 回収(human 3 発言で全応答 1 回ずつ)。RB=kind='bot' に戻し bot 再 install(session_id 不変)。
- **P6 bot 全廃+bridge 縮小**: `talk:bot:uninstall` 全除去、bridge 停止(削除は 1–2 週)、SQLite を authoritative へ昇格、tunnel `-L 8787` 撤去。依存=P5。完了=`talk:bot:list` 空＋bridge 停止でも全 venue 動作＋reconcile が SQLite 単独で健全。RB=bridge 停止維持→再起動。

### CP / 並列
CP = P0→P1→P2→P3→P5→P6。P4 は P0 から dev 並列可（E2E のみ P3 依存）。P1∥P4。P5 は venue 並列・role 直列。Track 分離推奨時: Track1=P0→P3'(local user)→P4→P5→P6、Track2=P0→P1→P2→P3(LDAP)。

### 混在運用
- 不変条件: (token,role) は bot XOR user の一方のみ（drain＋kind で担保）。
- ghost alert: registry × talk:bot:list × SQLite を reconcile、bot installed かつ kind='user' を alert。session orphan は opencode /session 突合。
- 二重/取りこぼし監視: メッセージ id の exactly-once(dedup table)、human 1 通の dispatch 数 ≤1+#mention、gap replay 数。
- worker: poll 中 1 binding=PHP-FPM worker 1（≤30s 毎）。11 許容、cap 設定、増加時 notify_push。

### ロールバック総表（可逆/不可逆）
| 相 | 戻し方 | 不可逆点 |
|---|---|---|
| P0 | なし | なし |
| P1 | unit disable | なし |
| P2 | active 0→app:disable | cleanup フラグは再 active で解消／実質なし |
| P3 | revoke/ldapdelete | 発行済 app password は rotate 可、投稿メッセージ帰属は不可逆 |
| P4 | plugin 無効化 | なし(cursor 再取得可) |
| P5 | kind='bot' 戻し | user 名義の既投稿は bot に戻せない(session 継続) |
| P6 | bridge 再起動 | bot uninstall 後は旧 bot 名義の再現不可(再 install は新 id)。Postgres 退役後は SQLite が唯一の真実 |

### 未決/残存懸念
- 未決: (1) LDAP を CP に残すか Track 分離(local user 先行)か (2) binding を opencode SQLite 同居か別 файлか(別ファイル推奨) (3) pilot venue 選定。
- 残存: app password at-rest 平文 SQLite／CF Access 再導入時の long-poll 死／PHP-FPM worker 増加／採番カウンタ非原子／spreed timeout 上限 30s の再接続頻度。

---

## 2026-10-13 P0–P2 完了: sv01 OpenLDAP + NextCloud user_ldap

### 成果物
- `components/host/sv01/services/openldap.nix`（`dc=id,dc=syoch,dc=org`、**loopback 限定**、389 は firewall で開かない）
- `components/host/sv01/ldifs/initial.ldif.in`（ou=Users/Groups/Services/**Meta**、lastUID=10000 / lastGID=10002）
- `components/host/sv01/scripts/ldapctl.py`（`nnctroboticsclub/infrastructure` の `AccountSetup/ldap.py` を移植）
- SOPS: `ldap-admin-password` / `ldap-nextcloud-password`
- backup: sv01 `/var/backups/ldap-migration-20261013-111930/`（nextcloud 188 tables / syoch-talk / syoch-portal、復元 drill 済み）

### 検証結果
- `openldap` / `ldap-init` active、`ldap:test-config s01` = "valid and the connection could be established"
- ローカル user `root`/`syoch` は `backend: Database` のまま。`ldapUserCleanup=0`
- LDAP ユーザは NextCloud 上で `backend: LDAP`、group は `posixGroup/memberUid` で自動同期

### 実測で判明した落とし穴（重要）
1. **`cn=admin,dc=...` は作れない** — slapd は RDN 属性の存在を要求し `organization` は `cn` を許可しない（object class violation）。`uid=admin,ou=Users,...`（inetOrgPerson+posixAccount）にする。
2. **userPassword の ACL に `by anonymous auth` が無いと全 simple bind が `Invalid credentials`** — slapd が PW 検証前に拒否する。`by * none` だけでは不可。
3. **NC35 に `ldapBindDN`/`ldapBindPassword` は無い** — 正しくは **`ldapAgentName` / `ldapAgentPassword`**。誤設定だと `ldapBase` が空になり `ldap_search(): No such object` → `ldap:test-config` が SEARCHFAILURE になる。切り分けは「同じ資格情報で生 PHP が成功するか」。
4. **`{ssha512}` は OpenLDAP が検証しない** — ldap3 は生成できるが保存はされるだけで**永久に bind 失敗**。`ldap3.utils.hashed.hashed(HASHED_SALTED_SHA, pw)`（= `{SSHA}`）を使う。`ldap3.utils.digest` は存在しない。
5. **bash の `if ! cmd; then rc=$?` は反転後の status** — `rc=0; cmd || rc=$?` を使う。
6. **採番カウンタが実 ID 以下だと収束しない** — 同じ ID を提案し続ける。カウンタを前に進める。seed group より大きい値から始める。
7. `nextcloud-occ app:enable user_ldap` は NC35 に同梱済みで **no-op**。「app 不在」は誤読。

### 運用メモ
- nixpkgs は sv01 実機に合わせて **`nixos-26.05`** に固定（unstable だと 470 derivations ugh）。OS upgrade と分ける。
- `nixos-rebuild --target-host` は profile symlink 作成に root が要る → **`--use-remote-sudo` を付ける**
- 新ファイルは `git add` しないと flake から見えない（既知制約）
- `nextcloud.db` ではなく **`/srv/NAS/nextcloud`（38G、別 btrfs）** が実データ。LDAP 作業が壊すのは認証/設定なので backup は config + DB で十分。

## 発行スクリプトの落とし穴（2026-10-13 実測）

残りロールへ拡大する前に必ず読むこと。

- **`ldapctl.py ensure-agent` は既存 uid では no-op**。「ユーザがいなければ作る」だけで、
  既にいるときのパスワード設定はしない。新規生成したパスワードを反映させるには
  **create 後に必ず `set-password` を呼ぶ**。
- これを飛ばすと `user:auth-tokens:add --password-from-env` が古いパスワードを受け、
  **限定 token（49 文字）**になる。full token は **72 文字**。
  判定は OCS 認証（`/ocs/v2.php/cloud/user`）を実際の transport で行うこと。
  根拠は文字数ではなく認証結果とする。
- `talk_bind` 投入は **verify-before-insert**。認証が通るまで DB を触らない。
- 検証を sv01 自身から繰り返すと 429（bruteforce）。throttle は Redis に居るので
  `redis-cli -s /run/redis-nextcloud/redis.sock flushall` で解除できる（専用 redis のみ）。
