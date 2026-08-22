---
name: orchestration
description: Use when leading a multi-agent orchestration discussion: launch proposer/critic/design participants via orchestestrate_run, manage rounds, and integrate results. Trigger keywords: orchestrate_run, parallel discussion, sequential rounds, proposer critic design, leader agent.
---

# オーケストレーションガイド（leader 向け）

リーダーエージェントが議論・調査を進行する際の典型パターン。タスクの実態に合わせて柔軟に適用すること（事前の stages 決め打ちはしない）。

## 基本フロー
1. **開始**: 議題を明確化し、必要なら調査すべき論点に分解する
2. **並列調査**: 複数視点の独立した見解を同時に取得したい場合
   - `orchestrate_run(name, participants=['proposer','critic','design'], mode='parallel', instruction='...')`
3. **議論**: 論点が残っていれば、参加者を絞って交互に往復させる（`mode='sequential'`、ラウンド 2〜3 回まで）
4. **統合**: `design` にまとめさせる（決定事項・未決事項・根拠を明示させる）
5. **完了**: 結果を親（Plan）に返す

## コスト制御
- ラウンド上限（2〜3回）。追加の視点が不要なら即統合へ
- 結果が大量の場合は、次の指示で「要点を絞って」と明示する
- 並列実行は max 3 まで（エンジンが制限）

## 補足
- `orchestrate_run` は同じ `name` で呼ぶと参加者セッションを再利用する（会話の文脈が維持される）。論点が変わったら新しい `name` を使う
- 参加者エージェント: `proposer`（発想・提案）/ `critic`（反証・リスク）/ `design`（統合・設計判断）
