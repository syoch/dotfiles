# Orchestration モデル割り当て（実証済み 2026-08-25）

## 確定割り当て（Agent frontmatter）

| agent | model | variant |
|---|---|---|
| proposer | `opencode-go/deepseek-v4-flash` | `low` |
| critic | `opencode-go/deepseek-v4-flash` | （省略 = default） |
| design | `opencode-go/deepseek-v4-flash` | `high` |
| leader | `opencode-go/deepseek-v4-flash` | `high` |

- deepseek 直結プロバイダは廃止。プロバイダは **OpenCode Go**（枠枯渇時は OpenRouter へ逃げる）
- variant は opencode 公式の Agent frontmatter `variant:` フィールド（opencode が models.dev の reasoning_options から自動生成する reasoning variant を参照）
  - `opencode-go` は `@ai-sdk/openai-compatible` → deepseek-v4 系は `{ low/high/max: { reasoningEffort: <effort> } }` が生成される（transform.ts）
  - 「Default」は variant 省略（prompt.ts で一致する variant が無ければ既定）
- 昇格判断: proposer 浅い→high / leader 不十分→max → 最終 `opencode-go/deepseek-v4-pro`

## 実験結果（トピック: opencode トークン利用改善案、parallel[proposer,critic] 1ラウンド → leader 統合）

| agent | variant | cost | in | out | reasoning | 所要 |
|---|---|---|---|---|---|---|
| leader | high | $0.0064 | 19,178 | 1,744 | **852** | 37s |
| proposer | low | $0.0025 | 7,796 | 1,116 | **0** | 8s |
| critic | default | $0.0024 | 7,840 | 971 | **0** | 8s |
| 合計 | | **$0.011** | 34,814 | 3,831 | 852 | ~37s |

- **think ティアリングが正しく機能**: leader のみ reasoning 852（high）、proposer/critic は reasoning 0（low/default）
- 総コスト $0.011・全工程 37s → 予算 (<150K in) を大きく下回り合格
- 品質: leader(high) 統合が論点を束ね、pro/max への昇格は不要と判定

## 留意点

- opencode サーバーは agent 設定を**起動時にキャッシュ**する → agent ファイル変更後は `systemctl --user restart opencode` が必要（WebUI セッションは DB 永続のため再起動で維持される）
- モデル/variant の実適用は DB `session.model` 列（JSON: id/providerID/variant）で検証可能
- キャッシュリード偏重ワークロードでコスト極小（Go 割引 + キャッシュ単価）
