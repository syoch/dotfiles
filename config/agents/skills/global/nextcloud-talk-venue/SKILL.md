---
name: nextcloud-talk-venue
description: Use when creating or tearing down a NextCloud Talk venue (a conversation with role agents), adding a role/bot to an existing conversation, or binding an existing opencode session to a role, via the sv01 talk-bridge control API. Documents the exact request payloads of GET/POST/DELETE /ctl/venues, /ctl/agents, /ctl/venue, /ctl/bot, /ctl/session, /ctl/sessions, /ctl/roles, /ctl/model, /ctl/delegate and /ctl/occ. "gdm" = group DM = one venue (a group conversation); this control API manages venues (there is no gdm binary). Trigger keywords: gdm, group DM, venue token, ctl/session, role を追加, bot を追加, session を bind, 会話に session を追加, /ctl/bot, /ctl/venue, /ctl/agents, talk-bridge control API, role slug, project_slug prefix.
---

# Talk venue control API（bridge の `/ctl/*`）

sv01 の `talk-bridge` が持つ制御平面。**「gdm」= group DM = 1 つの venue（グループ会話）**で、
この control API は venue を作る/操作する（`gdm` という実体バイナリは無いので `which gdm` は not found）。

bridge は **loopback 限定**（`127.0.0.1` bind）。
sv01 上で叩くか、reverse/SSH tunnel を使う。

### Base URL（どれを叩くか）

| 実行場所 | base URL | 備考 |
|---|---|---|
| **desktop / laptop（opencode が動く側）** | **`http://127.0.0.1:8788`** | `opencode-sv01-tunnel` が `-L 127.0.0.1:8788:127.0.0.1:8787` で転送 |
| sv01 自身 | `http://127.0.0.1:8787` | loopback 直接 |

**desktop から叩くなら `8788`。`8787` を叩いても通らない。**（実測: `8787/9101/10002/10003/20241` を全部試して不通、
`8788` は一撃 200）。
base URL は環境変数 `TALK_BRIDGE_CTL` に入っている。

### token の入手方法

- **自分が話している会話の token** = briefing に書かれた venue token。
  role agent には briefing で直接渡す（例: 「You are the `dotfiles-lead` role agent for the NextCloud Talk conversation `<token>`」）。
- **推測ではなく必ず確認**: `GET ${TALK_BRIDGE_CTL}/ctl/venues` で一覧する。
- 見つからないときは推測せず、一覧から該当 slug を探す。

## いつ使うか

- 会話（venue token）を作る / 消す
- 会話に**役割（role）を追加**したい（= Talk bot を 1 つ増やす）
- 既存の opencode **session を会話に bind** したい
- 「この role は既存之后再利用か新規か」を判断したい
- occ を直接叩けない環境で occ 相当の診断がしたい

## 手順

### 1. 役割と bot を足す前に必ず確認

```
GET /ctl/agents?token=<token>
→ { token, agents: [{ role, server_url, session_id, created_at }] }
```

**`secret` は絶対に返らない。** 「新しい role か既存 role の再利用か」の判断材料はこの endpoint で足りる。

### 2. 会話を作る（新規 role + session）

```
POST /ctl/venue
{ "project_path": "/home/syoch/ghq/github.com/syoch/<repo>",   // 必須・非空
  "slug": "procon",                                            // 必須・非空
  "model": "opencode/space-bunny-free",                        // 必須 "<provider>/<id>"
  "server_url": "http://127.0.0.1:12000",                      // 任意
  "description": "…",                                           // 任意（leader の scope にもなる）
  "migrate": { "sessions": ["ses_…"], "rename_prefix": "procon/prev" } }  // 任意
→ 201 { token, … }
```

- `project_path` / `slug` / `model` が**必須**（欠落・書式違反は 400）
- `model` は leader session に適用され、**後から足す role は leader のモデルを継承**する。既定値は無い
- `migrate.sessions` は **明示する session id の配列**。
  **件数から推測しない**（`Never inferred from a count`）。`rename_prefix` 既定は `<slug>/prev`
- 同じ `slug` の role が既にあれば **409**

### 3. 会話に役割（bot）を追加する

```
POST /ctl/bot
{ "token": "…", "role": "procon-skill-writer", "session_id": "ses_…",
  "project_path": "/abs/path", "project_slug": "procon",
  "description": "…", "server_url": "…" }
→ 201 { token, role, secret, server_url, session_id }
```

- **`token` / `role` / `project_path` / `session_id` の 4 つが必須**（2026-10-06 実測）
- `session_id` を省くと 400 `session_id is required and must look like an opencode session id`。
  これは**新規採番ではなく既存 session の指定**なので、役割追加と bind が 1 回で済む。
  先に `/ctl/session` を呼ぶ必要はない
- `role` は slug 規則（**小文字 ASCII + ハイフン**、`SLUG_MAX=40`）を通る必要がある
- `project_slug` を渡すと **prefix 検査が走る**:
  leader でない限り `role` は `<project_slug>-` で始まる必要がある（違反は 400）。
  **省略すると検査が飛ばされ、別プロジェクトの role が作られる**
- 既にいる role は **409**
- `secret` は**サーバーが自動生成**する（`bc_` + UUIDv7 を 96 文字に切り詰め）。要求しない
- `model` は **leader のモデルを継承**（`"model": "<provider>/<id>"` で個別上書き可）。新 session の model 列も切り替わる
- 途中で失敗したら bot を remove → uninstall してから例外を再送出する（**孤児を残さない**）

### 4. 既存 session を bind する

```
POST /ctl/session   { "token": "…", "role": "…", "session_id": "ses_…" }   → { ok: true }
```

agent 行が無い場合は **404**。
bot を作らず、**既存のセッションだけ差し替える**ときに使う。
既存 role の session を後から差し替えるのが主用途。
新しい role を足すときは `/ctl/bot` に `session_id` を渡すので、こちらは不要。

### 5. 消す

```
DELETE /ctl/bot?token=&role=     → { ok, removed }          // 1 役割だけ
DELETE /ctl/venue?token=         → { ok, token, roles_removed, warnings }
```

`/ctl/venue` の順序は固定: 全 role の uninstall（best effort）→ DB 行削除 → **最後に**会話削除。
会話削除が失敗しても **role 行は既に消えているので再実行して安全**（二重 uninstall にならない）。
`ok: false` のときは `warnings[]` を読む。

### 6. 参考

```
GET  /ctl/sessions?project_path=&limit=&offset=&prefix=&stats=1   // 移行候補
GET  /ctl/venues                                                  // venue 一覧
GET  /ctl/roles?session_id=<id>   （または ?token=<venue token>）  // 会話の role 一覧＋スコープ＋モデル
POST /ctl/model { "token": "…", "model": "<provider>/<id>" }       // venue の全 session を一括でモデル切替（ランタイム）
POST /ctl/delegate { "session_id": "ses_…", "target_role": "…", "message": "…" }
                                                                  // 委任: message を Talk に投稿 + 対象 role に配送
GET  /ctl/session/<id>/messages?limit=&directory=&server_url=     // 本文（明示要求時のみ）
GET  /ctl/occ?args=talk:bot:list --output json                    // occ 診断
GET  /healthz
```

`/ctl/roles` は `/ctl/bot` の `description`（role スコープ）と `model` を返す。
`/ctl/model` は venue の**全 session の model 列を一括更新**する（leader のモデル = venue のモデル）。
bridge は prompt 送信時に model を渡さないので、`session.model` が唯一の真実。個別 session の切替は
opencode の `POST /api/session/<id>/model` で直接行える。
`/ctl/delegate` は agent 向けツール `talk-delegate` の実体で、**投稿**と**配送**を 1 回で行う
（旧「返信テキストの @role 走査 relay」は撤廃）。1 人間メッセージ起点の予算を超えると **429**
（`{ ok:false, reason:"budget" }`）。

webhook の受信パスは `/hook/<token>/<role>`。人間メッセージは **leader（最古の role）だけ**に
配送され、人間が `@role` を明示したときだけその role にも配送される（broadcast 廃止）。

## 検証方法

- 必須パラメータ欠落が **400**、未知 role が **404**、role 重複が **409**、
  slug 重複が **409** になることを 1 つずつ確かめる
- `project_path` を落とすと 400。**`.` に落とすと bridge の cwd に作られる**ので必ず絶対パス
- `project_slug` を渡して prefix 外の role を入れると 400、
  **omit すると通ってしまう**ことを確認する
- 一覧系レスポンスに `secret` が**含まれない**こと（`/ctl/agents`, `/ctl/venues`, `/ctl/sessions`）
- `DELETE /ctl/venue` の後、`talk:bot:list -v` に bot が残っていないこと

## 落とし穴

| # | 症状 | 真因 |
|---|---|---|
| 1 | bot が別プロジェクトの名前で増える | `project_slug` を省略 → **prefix 検査が走らない** |
| 2 | session が bridge の cwd にできる | `project_path` を `.` にした。**絶対パス必須** |
| 3 | role 名が拒否される | slug 規則は**小文字 ASCII + ハイフン**、40 文字まで |
| 4 | 移行する session が勝手に選ばれる | `migrate.sessions` は**明示 id の配列**。件数指定は不可 |
| 5 | 壊れた bot が残る | `DELETE /ctl/bot` は uninstall 失敗を**握り潰す**（warning も返らない）→ 行だけ消える |
| 6 | bot が生きているのに webhook が 404 | registry 行を先に消した。`/ctl/venue` の**順序**を守る |
| 7 | 応答が遅い | `GET /ctl/sessions` の `stats=1` は全 message を走査する（重い） |
| 8 | 権限周りで壊れる | occ は `User = nextcloud`。`/ctl/occ` と同じラッパー・同じ権限で動く |
| 9 | `/ctl/bot` が 400 で弾かれる | `session_id` を省いた。**既存 session の id が必須**（勝手に採番されない） |
| 10 | 委任が 429 で弾かれる | 1 人間メッセージ起点の delegate 予算（既定 12）超過。人間の新規メッセージでリセット |
| 11 | `/ctl/venue` が 400 | `model`（`"<provider>/<id>"`）が必須。無いと venue を作れない |

occ の正確な引数形と権限は `nextcloud-talk-occ`、webhook 契約は `nextcloud-talk-webhook` を参照。
