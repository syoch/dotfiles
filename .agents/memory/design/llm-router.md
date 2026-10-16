## LLM ルータ (opencode-inspector 取り込み) 設計案 2026-10-15

設計 docs は NextCloud に publish 済み: https://nextcloud.syoch.org/f/129616

### 4 十字の不変制約 (empirical、opencode 1.18.31)
1. opencode は POST /v1/chat/completions に出す（model は config 固定の "any"）。
2. プロジェクトは x-session-id ヘッダから opencode.db (read-only) を引いて解決。
3. 上流レスポンスは SSE で passthrough が必要。
4. Authorization は Bearer <local-token>（ルータが受け取る）。

### 解決規則
- project.parent_id 単一ツリー (MVP), non-null model_id を持つ最初の祖先が勝つ。
- project_route 行が無ければ継承。
- _default sentinel (root) まで walk し、フォールバック model を取得。
- BaseProject を B に変更 → override を持たない ProjectA は B に再解決。

### DB (router.db、opencode.db とは別)
upstream / model / project / project_route / project_effective / request_log。
概念の details は NextCloud の shared/llm-router-design.md を参照。

### opencode-inspector 取り込み
read-only opencode.db 閲覧機能 (/api/inspect/*) + SQL console。既存の
NOTE.md / test.sql (再帰 CTE subtree) を移植。

### WebUI と Inspector を同一 bun サーバへ統合。

### 未決め項目 (user decision pending)
- name (ocdesk など)
- upstream family (openai-compatible only vs +anthropic)
- secret 強度 (plaintext か master-key)
- audit log scope (prompt 本文を保存するか)
- WebUI (SPA vs plain html)
- variant の表現
### 元メモ
~/work/opencode-inspector (NOTE.md, test.sql, flake.nix) へ吸収。dotfiles とは
別 repo (~work/<name>)、安定後に nix-ize。

### design 决定 fixed (2026-10-15)

未決 §12 を resolved:

1. **Name: ocdesk** (ocworkbench flavor). DB パス `~/.local/share/ocdesk/ocdesk.db`、config `~/.config/ocdesk/`。
2. **Upstream family**: **openai-compatible のみ** (Phase 1)。anthropic は Phase 2。
3. **secret storage**: 平文 SQLite (opencode 自身と同じ姿勢、master-key 暗号化なし)。
4. **audit log**: prompt 本文は保存しない — メタデータ（ts/session/project/model/status/bytes/tokens/latency/error）のみ。
5. **WebUI**: **Skeleton UI (Tailwind + svelte 系)** を使う。plain HTML ではない。
6. **variant**: MVP は別 model レコード approach (model_name + variant column、NULL = upstream default)。

これで Phase 1 着手可能。`~/work/ocdesk` を独立 repo として作成し、stable 後 nix-ize。
