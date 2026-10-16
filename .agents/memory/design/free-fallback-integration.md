# opencode free-tier fallback 統合依頼 (ocdesk → dotfiles, 2026-10-16)

依頼パッケージ: `~/ghq/github.com/syoch/ocdesk/integrations/opencode-free-fallback/`
(README.md / DESIGN.md / plugin.ts / plugin.test.ts / policy.example.json)

## 目的
無料/stealth な opencode.ai モデル (`opencode/<*-free>`) を優先して使い、
free tier 枯渇時は ocdesk が提供する有料モデルへ同一ターンを継続する。

## ハード制約 (実測済み・設計の根拠)
`*-free` は **opencode アプリ本体しか通らない** (curl / bun / @opencode/sdk /
ocdesk proxy いずれも `403 FreeTierError`)。よって切替は ocdesk 側では実装できず、
**opencode の plugin (in-process) が唯一の実装場所**。ocdesk は policy/registry と
有料 leg の provider を担う。

## plugin が ocdesk に要求する contract (未実装)
- `GET  /api/free-fallback/policy?directory=<dir>[&project_id=...]`
  -> `{enabled, freeProvider:"opencode", free:[...], paid:{providerID,modelID}}`
- `POST /api/free-fallback/events` (枯渇 audit; 204)
- 優先順位: inline JSON (`options.policy`/`$OCDESK_FREE_FALLBACK`) → GET policy → built-in default

## 検出と failover (1.x)
- 検出: `session.error` (ProviderAuthError / ApiError.statusCode 403/429 + "free") と
  `session.status` retry の message テキスト。※ v2 では `reason==="free_tier_limit"` が出る予定。
- 動作: 最後の user message を取得 → `session.abort` → `session.prompt(model=paid)` で再生。
- guard: `(sessionID,userMessageID)` 単位で単発。

## 既知の制限 (prototype)
- **paid を sticky にできない** (1.x に model override hook なし)。次の user turn で
  再び free を選ぶと再度 failover する。ログで警告するのみ。
- replay で user メッセージが重複する (revert するか許容)。
- 検出は reactive (quota は非公開、1 回失敗して初めて分かる)。

## dotfiles 側ハンドオフ checklist (DESIGN §10)
1. `plugin.ts` を `~/.config/opencode/plugins/free-fallback.ts` へ配置 (or config.plugin)
2. ocdesk provider 追加 (`baseURL` に `/v1` 必須, apiKey=token) — skill `opencode/openai-compatible-provider`
3. ocdesk 側の 2 endpoint (policy GET / events POST) + DB table
4. 既定 policy (free list + paid model) と per-project override の決定
5. FreeTierError を強制する E2E テスト

## 状態
読み込みのみ完了 (2026-10-16)。dotfiles 側の実装/判断は未着手。

## フォールバック順序の確定 (2026-10-16 ユーザー決定)

正しい順序: **free モデルをすべて使う → ocdesk のルーティング (paid) に載せる**。
その段階で ocdesk が利用不可なら**許容**（しょうがない）。それ以上の追加
フォールバックは設計しない（過剰化を避ける）。

含意:
- prototype の「paid が sticky でない」制限は実害なしと判断。次ターンで free に
  戻る挙動は「free 優先」の意図と一致するため許容する。
- 「free をすべて使う」= free list を順に消費する（`free: [...]` の順序が意味を持つ）。
  per-model quota 枯渇なら次の free、全 free 枯渇で paid(ocdesk) へ。
- ocdesk 側 endpoint (policy GET / events POST) と有料 leg provider は引き続き必要。
- E2E 検証の合格条件もこれに合わせる: 全 free 枯渇 → paid replay が成功すること。
  paid 側障害時のリトライループは作らない（ログのみ）。
