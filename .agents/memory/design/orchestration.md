# マルチエージェント Orchestration 設計（opencode）— 最終版

## 目的
- エージェント間の対話（ブレスト・議論・並列調査）をコード層でオーケストレーションし、低コスト・高品質な出力を得る。
- 転送（メッセージルーティング）は LLM ではなく仕組み（コード）が行う。
- 性能の高くないモデルでも、検証ゲート・モデルティアリング・早期終了により品質を増幅する。

## アーキテクチャ

### リーダーエージェント (leader, mode: subagent, 強いモデル)
- 流れの判断を担当（誰に何を聞くか、並列/直列、いつ統合するか）
- **edit / bash は使わず orchestration に徹する**（強いモデルのツール多用によるコスト増を避ける）
- ツール: `orchestrate_run` のみ（+ 読み取り系）
- 起動: Plan フェーズで orchestration 要否を判断 → task tool で leader を起動（議題を渡す）→ 結果を Plan に返す

### エンジン（プラグイン, コード）
- リーダーの指示 `orchestrate_run(name, participants, mode, instruction)` を実行
- mode: `parallel`（同時 prompt, Promise.all）/ `sequential`（順次）
- 転送は**完了時送信**（全文を次へ）。リアルタイム送信は採用しない
- 結果全文をリーダーへ返す

### 状態管理（resume 対応）
- `.agents/orchestration/<name>.json` — participant → sessionID マップ + メタ（topic, createdAt）
- `orchestrate_run` は name + participant 名でセッションを一意に特定
  - sessionID あり → そのセッションへ追記送信（resume、コンテキスト維持）
  - なし → セッション作成 → state に記録
- 同じ name の orchestration 内でのみ participant セッションを再利用（別議論の文脈混入を防ぐ）
- `.agents/orchestration/<name>.log` — 実行ログ（ストリーミング観察用）
- プロセス再起動後も .json から resume 可能

### 参加者エージェント (participants, 静的定義)
- `proposer` / `critic` 新規作成（mode: subagent, 弱いモデル）
- `design` を統合役に流用（強いモデル）
- frontmatter の `model:` でモデル解決（フロー定義で上書き可）

### アシスト = memory ツール
- フローガイド（典型的な進め方）は memory_save で保存（topic: `orchestration/guide`, project scope）
- leader は memory_get で参照。プロジェクトごとにカスタマイズ可能
- 事前の stages 決め打ちはしない（リーダーが柔軟に判断）

## 検証済みの技術前提（opencode 1.18.13）
- `PluginInput.client` に公式 SDK client が注入される
- `POST /session/{id}/message`（body に agent 指定可）で既存セッションへ追記送信可能 → セッションは履歴を保持（resume の基盤）
- `session.start` フックは存在しない → Plan エージェントが判断して task tool で起動
- **並列実行性（実測済み）**: 同一プロセス内で複数セッションへの同時 prompt は完全並列実行される
  - 直列 31.7s → 並列 wall 18.2s（max に一致, ratio=1.00005）
  - 根拠: Node 非同期 HTTP サーバー + セッション処理がファイバー独立ループ + LLM 呼び出しが非同期ストリーム
  - 制約: 同セッションへの同時送信は排他（busy）→ 並列は異なるセッション間でのみ
  - レート制限: 2並列は問題なし（4呼び出し成功）。モデル依存なので並列数上限（max 3〜5）を維持
- task tool に task_id 再開があるが、LLM 中継になるため議論転送には採用しない（エンジンが直接 session を再利用）

## 実装優先度
1. 直列（sequential / debate）を先に実装
2. 並列（parallel）を次に実装（並列調査が主用途）

## 確定した非機能要件
- ラウンド上限（2〜3回）でコスト制御（SKIMIX の知見）
- モデルティアリング: 生成=弱いモデル、統合/検証/リーダー=強いモデル
- 並列数上限（例: max 3〜5）でレート制限対策

## 事前調査結果（2026-08-22、実装前の実測）

### 1. モデル利用可否（実測）
- **利用可**: `deepseek/deepseek-v4-flash`（弱）、`deepseek/deepseek-v4-pro`（強）— deepseek 直結キー
- **利用不可**: `opencode-go/*`（25秒タイムアウトでハング）、`opencode/*`（Insufficient balance）
- → モデルティアリングは deepseek プロバイダ内で解決する

### 2. plan エージェントの task 許可
- `task` ツールは標準ツールとして全セッションに登録（tool.list で確認）
- plan エージェントから leader 起動（task で subagent 起動）は実現可能。実行時 permission は ask がデフォルト

### 3. カスタムツール permission（重要）
- **プラグイン定義のカスタムツールはデフォルトで確認なしで実行可能**（settings.permission に未登録でも allow 相当）
- エージェント定義の permission deny は機能するが、モデルの応答が完了しない（finish=undefined でハング）リスク
- **堅牢な制御**: ツール execute 内で `ctx.agent` を確認し、leader 以外は明示エラーを返す方式を採用する（permission deny は併用しない）

### 4. プラグイン内 client 動作
- `Hooks.tool` で定義したツールの execute 内から `PluginInput.client` で session create/prompt/delete が**完全に動作**（実測: orchestrate_test が別セッション作成→prompt→応答取得→削除、エラーなし）
- カスタムツールは tool.list に登録される（全エージェントに見える）

### 5. モデル割り当て（確定）
- leader: `deepseek/deepseek-v4-pro`（強い）
- proposer / critic: `deepseek/deepseek-v4-flash`（弱い）
- design（統合役）: `deepseek/deepseek-v4-pro`（強い）

### 実装時の設計反映
- orchestrate_run は `plugins/orchestration.ts` に置く（client が必要なため）
- ツール内で ctx.agent ガード（leader のみ許可）を実装
- カスタムツールのデフォルト allow に注意（全エージェントから呼べる）

### 【修正】調査1の再検証（opencode-go はハングではない）
- `GET https://opencode.ai/zen/go/v1/usage`（opencode-go API キー）で quota 確認:
  - rolling: ok (0%)
  - **weekly: rate-limited (100%)** — 週間枠枯渇が原因。リセット 2026-08-24T00:00:00Z
  - monthly: ok (60%)
- 結論: **opencode-go は「ハング」ではなく週間 quota 100% による rate-limit**。リセット後は利用可能になる見込み
- モデル割り当てへの反映: 現時点の実装は deepseek 直結（v4-flash 弱 / v4-pro 強）で行うが、**opencode-go は quota リセット後の「強いモデル」選択肢として残す**（gpt-5.6-luna 等）
- 参考: `/zen/go/v1/models` で opencode-go 利用モデル一覧が取得可能（minimax-m3, minimax-m2.7, kimi-k3 等）
