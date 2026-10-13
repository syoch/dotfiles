# Orchestration ベースライン実測（2026-10-05）

## 計測方法

- 計装: `modules-hm/apps/opencode/orchestration.ts` に `.agents/orchestration/<name>.metrics.jsonl` への JSONL 追記を追加（`wallMs` / `criticalPathMs` / `startSkewMs` / per-agent 内訳）。既存挙動は不変。
- ハーネス: `/tmp/opencode/orch-measure.ts`（bun で execute を直呼び、ctx は `agent="leader"` を mock、model 差替えは client ラッパで `session.prompt` の body に注入）
- サーバー再起動不要（bun が plugin を読むため計装が即反映）。`opencode serve --port 4199` を使用（ユーザーの 12000 セッションには触れない）
- 指標定義:
  - `compression = wall / Σ(per-agent)` — n agents の理想値は 1/n
  - `startSkewMs` — parallel なら 0、sequential なら前 agent の所要時間

## 結果（model=opencode/space-bunny-free, REPS=5, 固定プロンプト）

| 指標 | sequential | parallel |
|---|---|---|
| compression | **1.00, 1.00, 1.00, 1.00, 1.00** | 0.833, 0.541, 0.512, 0.583, 0.616 |
| startSkewMs | 前 agent の所要時間 | **0**（全 run） |

### 並列効率は数学的に最適

`wall == max(per-agent)` が**全 5 ランで厳密一致**（予測値 max/(p+c) と実測が小数点以下一致）。

ideal 0.50 からの逸脱は 100% が **participant の所要時間非対称**（proposer/critic 比 1.05〜4.99）で説明できる。並列効率の損失はゼロ。

- parallel speedup = Σ/max = **1.20〜1.95x（平均 1.67x）**、理論上限 2.0x
- 残り余地は「遅い participant を速くする」ことのみ

### leader は fan-out より速い（重要: 旧仮説の反証）

- leader 単発 turn median **4,351ms** vs fanout parallel median 18,151ms → **0.24x**
- 旧データ（2026-08-25, deepseek-v4-flash variant=high）で見られた「leader が 37s で支配的」は **model+variant 固有**でありアーキテクチャの性質ではない
- ただし本計測の leader は participant 出力を受け取らない裸 prompt であり、実統合コストは過小評価している

### resume は速くなる（文脈増加はキャッシュに負ける）

同一 name で 4 連呼（2〜4 回目で `resumed=1` 確認）:

```
11276ms(N) → 11273ms(R) → 7020ms(R) → 3697ms(R)   = 0.33x
```

文脈は増えるが prompt cache がそれを上回る。leader turn で `in=1, cacheRead=14965` を確認（システム prompt が完全キャッシュ）。**「ラウンドacca Artifact を重ねると遅延が増える」という素直な仮定は反証された。**

## 判明した堅牢性の欠陥

1. **`orchestrate_run` に timeout が無い** — provider がハングすると `Promise.all` ごと永久停止（opencode-go で実証）。`Promise.race` は await を止めない
2. **provider 例外は `[error]` 文字列として出力に埋まる** — 機械可読でない。leader が構造的に解析できない

## ハーネス側で発見したバグ（記録）

- `client` を `{...base.session}` で spread すると `delete` が欠落する → 明示 bind
- JSDoc block comment 内の `bun-*/bin/bun` が `*/` でコメントを早期終了させる
- 計測後に state ファイルを掃除すると resume テストが成立しない（毎回新規セッションになる）
- median を整数丸めすると比率 0.75 が "1" と表示される
