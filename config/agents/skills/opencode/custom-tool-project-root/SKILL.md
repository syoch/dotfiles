---
name: custom-tool-project-root
description: Use when writing or reviewing opencode custom tools or plugins that resolve project-scoped paths (.agents/, .agents/memory/, catalogs): must use ctx.worktree/ctx.directory (tools) or client.session.get directory (plugin hooks) instead of process.cwd(), which breaks under the webui server. Trigger keywords: opencode custom tool cwd, ctx.directory ctx.worktree, project root resolution, memory scope collision, agents-bridge session directory, process.cwd bug
args: なし
---

# opencode custom tool / plugin のプロジェクトルート解決

## いつ使うか

opencode のカスタムツール (`tool()`) やプラグインで「セッションのプロジェクトディレクトリ」を基準にパス (`.agents/`, `.agents/memory/` 等) を解決するコードを書く・レビューする時。**`process.cwd()` を使うと WebUI/systemd サービス経由のセッションで project スコープが $HOME に化ける**。

## 手順

1. **カスタムツール**: `execute(args, ctx)` の第2引数 `ctx` を受け、`ctx.worktree || ctx.directory` をルートにする。SDK の `tool.d.ts` にも "Prefer this over process.cwd()" と明記されている。実装例: dotfiles `orchestration.ts:42`
   ```ts
   async execute(args, ctx) {
     const base = resolve(join(ctx.worktree || ctx.directory, ".agents", "memory"))
   }
   ```
2. **プラグイン**: `Plugin = async (input) => {...}` の `input.worktree || input.directory` をフォールバックとし、フック内では `input.client.session.get({ path: { id: hookInput.sessionID } })` → `res.data.directory` でセッション毎のディレクトリを解決する (system.transform 系フックの入力には directory が無い)
3. 型検証は `bun build --no-bundle <file> --outfile /tmp/out.js`

## 検証方法

- ツール実行の応答 JSON の `path` フィールドが `<worktree>/.agents/...` を指すこと
- 分離スモークテスト: plugin 関数にモック `input = { client: fakeClient(→session.get が directory を返す), directory, worktree }` を渡して呼び出し、注入ブロック内のパスを assert

## 落とし穴

- **症状が出にくい**: TUI をリポジトリ直下から起動した場合は cwd===worktree で正しく動く。WebUI (`opencode web` systemd unit) では cwd=$HOME になり、project 書き込みが `~/.agents/...` (global ベース) に静かに衝突する。応答 JSON の `scope` フィールドは正しいので発見が遅れる
- 実際に発生したバグ (2026-08): memory.ts / agents.ts / agents-bridge.ts の 3 ファイル。agents-bridge.ts では `.agent/memory` (旧パス誤記) と `~/.config/opencode/memory` (移行前 global パス) の残存も同時に発覚
