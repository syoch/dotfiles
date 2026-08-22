---
name: opencode-verification-harness
description: Use when verifying opencode behavior end-to-end on a real headless server: run `opencode serve`, drive it via the SDK client (createOpencodeClient) to create sessions, send prompts, and inspect responses/measure timing, then clean up temp sessions with session.delete. Covers parallel-execution testing, plugin custom tool behavior, hooks, resume, and permission checks. Trigger keywords: opencode verification, serve e2e test, SDK client session.prompt, parallel execution test, plugin tool behavior check, session.delete cleanup, Insufficient balance provider, behavioral verification harness.
---

# opencode 挙動検証ハーネス（serve + SDK client E2E）

## いつ使うか
- opencode の挙動を実サーバー上で検証したいとき（並列実行性、プラグインのカスタムツール、フック、resume、permission など）
- SDK client / HTTP API の仕様確認（レスポンス構造・パラメータ）が必要なとき
- プラグイン開発（agents-bridge.ts 等）の動作確認基盤として

## 手順

1. **serve を tasks_start でバックグラウンド起動**（1コマンドにプロセス管理を詰め込まない。シェルバックグラウンド起動はセッション終了で死ぬため禁止）
   ```
   opencode serve --port 4199
   ```
   起動確認: `curl -s http://127.0.0.1:4199/`
2. **検証スクリプトを作成**（下記テンプレートを土台に検証コードを書く）。クリーンアップは必須。
3. **実行**: `bun <script>.ts [port]`
4. **必要なら** `tasks_log` で serve のログ確認
5. **tasks_kill で serve 終了**

## テンプレート（ベース）

```ts
import { createOpencodeClient } from "@opencode-ai/sdk"
const port = process.argv[2] ?? "4199"
const client = createOpencodeClient({ baseUrl: `http://127.0.0.1:${port}`, throwOnError: true })
const dir = process.cwd()
const model = { providerID: "deepseek", modelID: "deepseek-chat" } // 直結プロバイダを使用

const created: string[] = [] // 全作成セッションを記録して finally で削除

async function newSession(title: string) {
  const res: any = await client.session.create({ query: { directory: dir }, body: { title } })
  created.push(res.id)
  return res.id
}

async function promptText(sid: string, text: string) {
  const res: any = await client.session.prompt({ path: { id: sid }, body: { model, parts: [{ type: "text", text }] } })
  return (res.data?.parts ?? []).filter((p: any) => p.type === "text").map((p: any) => p.text).join("")
}

async function main() {
  try {
    // ★ 検証コード
  } finally {
    for (const sid of created) {
      await client.session.delete({ path: { id: sid } }).catch(() => {})
    }
    console.log(`cleaned up ${created.length} session(s)`)
  }
}
main()
```

## 検証パターン例: 並列実行性
- 直列: 2セッションに順次 prompt → 合計時間
- 並列: 別の2セッションに `Promise.all` → wall 時間
- 判定: 並列 wall が `max(個別時間)` に近ければ完全並列（実測: 直列 31.7s → 並列 wall 18.2s, ratio=1.00005）

## 落とし穴（重要）
- **`opencode` プロバイダのモデルは課金残高が必要**（`Insufficient balance` で失敗）。検証は直結プロバイダ（deepseek 等）を使う
- **`session.create` のパラメータ**: directory は `query`、body は `{ title }` のみ。`agent` / `model` は **prompt 時の `body`** に指定
- **prompt レスポンス構造**: `res.data.info`（assistant メタ）/ `res.data.parts`（本文）から抽出
- **一時セッションは必ず finally で `session.delete`**（DB 肥大化防止）。resume 検証など保持が必要な場合のみ明示的にスキップ
- 同一セッションへの同時 prompt は排他（busy）→ 並列は必ず異なるセッション間で
- モデルは環境により `opencode models <provider>` で利用可能なものを確認
