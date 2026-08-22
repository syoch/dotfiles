---
name: compaction-memory-candidates
description: Use when injecting custom instructions into opencode's /compact summarization or persisting session knowledge across context compaction: the compaction agent cannot reliably execute tool calls (emits them as plain text), so use experimental.session.compacting hook output.context to append summary sections instead. Trigger keywords: compaction hook, session.compacting, pre-compaction flush, memory candidates, compacting tool call not executed, output.context vs output.prompt.
---

# opencode コンパクションへの指示注入と知識フラッシュ

## いつ使うか
- `/compact` の要約生成に独自セクション（例: Memory Candidates）を追加したいとき
- 圧縮で失われる決定・発見を長期記憶に残す仕組みを作るとき
- コンパクション中にツールを呼ばせようとして失敗したとき

## 落とし穴（最重要）
- **コンパクションエージェントはツールを実行できない**。権限 (`memory_*": "allow"`) やツール登録が有効でも、会話がプレーンテキスト化されるためモデルはツールコールを**テキストとして出力**し、実行されない（opencode 1.18.13 / big-pickle で実証）。
- したがって「圧縮前に memory_save せよ」という指示は機能しない。
- フックの `output.prompt` を置換すると内蔵の要約プロンプト（Objective/Work State 等の構造）が失われる。**`output.context` への追記が安全**。

## 手順
1. プラグインで `experimental.session.compacting` フックを定義する:
   ```ts
   "experimental.session.compacting": async (_input, output) => {
     output.context.push("In addition to the required sections, append a final section titled '## Memory Candidates'. ...")
   }
   ```
2. 要約に候補セクションを出力させ、**圧縮後のメインエージェント**（通常ターンなのでツールが使える）に永続化させる規約を AGENTS.md に書く。
3. 検証: `/compact` 後の要約パネルにセクションが表示されること、圧縮後のターンでその内容が参照できることを確認。

## 実証済みの動作 (1.18.13)
- フックの context は確実にモデルへ届く（指示通りのセクションが出力される）
- 未保存の知識は Memory Candidates 経由で圧縮を生存でき、復帰後のエージェントが `memory_find` で重複確認してから保存する一連のループが成立する
