# opencode provider 可用状況（2026-10-05 実測）

## 現状

| provider | 状態 | 备注 |
|---|---|---|
| `opencode-go`（本番設定） | **monthly quota 100%**、リセット 2026-10-08T11:12:32Z | rolling 0% / weekly 6% は正常。**無応答ハング**（エラーも返さず turn が完了しない） |
| `openrouter` | **Insufficient credits**（アカウント未購入） | |
| `opencode` | モデルにより挙動不同。`big-pickle` / `claude-haiku-4-5` は空応答（turn 未完了）、**`space-bunny-free` は正常動作** | |
| `google` | free-tier quota 枯渇（`You exceeded your current quota`）。約 70 秒のリトライ/バックオフ後に失敗 | |
| `github-copilot` | auth.json に key あるが provider 定義なし（`Provider not found`） | |

## 重要な失敗モード

**provider はハングしうる**。`opencode-go` は quota 枯渇時に HTTP エラーを返さず、session.prompt が永久に返らない。DB 上は assistant message が `cost=0` / `tokens=全0` / `time.completed` 欠落の状態になる。

→ .timeout を持たない呼び出し（`orchestrate_run` を含む）は永久にブロックされる。診断時は「turn が完了したか」を `message.data.time.completed` の有無で判定する。

## 計測用の.provider 選択

短期の計測・検証には `opencode/space-bunny-free` を使う（cost=0、finish まで正常完了する）。

ただし以下に注意:

- agent frontmatter の `variant` は model を上書きすると失効する（opencode-go の reasoning variant は space-bunny-free に無い）
- variant を使うaxelometry（leader=high など）は space-bunny-free では再現できない
- 本番の絶対値が必要な計測は 10-08 の quota リセット後に行う

## quota 確認方法

```
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <~/.local/share/opencode/auth.json の opencode-go.key>
```

## リスク: orchestration fleet の単一 provider 依存（2026-10-05 追記）

### 構造

`leader` / `design` / `proposer` / `critic` の 4 agent が **すべて `opencode-go/deepseek-v4-flash` を明示指定**している
（`modules-hm/apps/opencode/agents/*.md` の frontmatter `model:`）。

default model（`space-bunny-free`）を使う agent:
`build` / `general` / `plan` / `explore` / `compaction` / `summary` / `title`

### 影響

`opencode-go` が quota 枯渇すると:

- **orchestration fleet 全体が停止**する。leader が動いても proposer/critic/design を招集できない（全員同じ provider）
- しかも provider は**エラーを返さずハング**するため、`orchestrate_run` は永久に await したまま（timeout 実装が無い）
- 代替モデルへのフォールバックは**发生在しない**（agent frontmatter が model を固定しているため）

### 実害の記録

2026-10-05 の 1 セッションで provider 障害起因の作業停止が **2 回**発生:
1. leader を呼んで命名規則を brainstorm させようとしたが、opencode-go 枯渇で不可
2. orchestration のベースライン測定が provider 待ちで遅延

`general` へのフォールバックは permission rule で denied WasRenamedため代替 belligerent が確保できなかった。

### 対策候補（未実装）

| 案 | 内容 |  tradeoff |
|---|---|---|
| **model を agent frontmatter から外す** | default model に委譲し、provider 停止時も動く | モデル指定の再現性が失われる |
| **fallback 機構** | primary provider が failed を検出した agent だけ secondary に切替 | agent ごとに primary/secondary を書く必要 |
| **provider を分散** | 役割ごとに別 provider を割当（設計=opencode-go、proposer=他） | 役割と provider が結びつく |
| **timeout + 明示的失敗** | ハングではなくエラーで失敗させる | 可用性は解決しない |

根本的な Durée: 「全 agent が同じ provider を指す」という設定が、単一障害点になっている。
