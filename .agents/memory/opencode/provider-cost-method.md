# opencode provider コスト・quota 分析の手法

`AI プロバイダコスパ比較` セッション（386 msgs, 2026-08-22/23）をアーカイブして得た
**再利用可能な手順**。-parameterized 数値は当時（2026-08）実測。

出典: `.agents/sessions-archive/20260822-1354_iCT5M1z5I_ai-provider-cost-comparison.json.gz`
現況（2026-10-05 時点）は `opencode/provider-availability` を見ること。

---

## 1. quota の権威値はサーバー側 API

ローカル DB で推定せず、必ず公式 usage エンドポイントを使う。

```bash
curl -H "Authorization: Bearer $(jq -r '.["opencode-go"].key' ~/.local/share/opencode/auth.json)" \
     -H "User-Agent: Mozilla/5.0" \
     https://opencode.ai/zen/go/v1/usage
```

返るのは 3 つのスライディングウィンドウ:

```json
{ "rolling": {"status":"ok",          "percent":0,   "resetsAt":"..."},
  "weekly":  {"status":"rate-limited","percent":100, "resetsAt":"..."},
  "monthly": {"status":"ok",          "percent":60,  "resetsAt":"..."} }
```

**教訓**: 「rolling は 0% なのに切れている」ような矛盾牘か所が出る。DB 側の
トークン集計はキャッシュ読み取りを正確に捕捉しないため、判定には API を使う。

## 2. 実際の使用量はローカル DB で測る

```bash
opencode db "SELECT id, title, datetime(time_created/1000,'unixepoch','localtime'),
                     datetime(time_updated/1000,'unixepoch','localtime')
              FROM session WHERE directory='<cwd>'"
opencode db "SELECT session_id, COUNT(*) AS msgs, SUM(LENGTH(data)) AS bytes
              FROM message WHERE session_id IN (...) GROUP BY session_id"
```

実測値（2026-06〜08、opencode-go / deepseek-v4-flash、Go リスト価格換算）:

| 月 | オフピーク | ピーク | 内訳 |
|---|---|---|---|
| 2026-06 | $28.5 | $57.0 | in 34.5M / cache-read 2.47B |
| 2026-07 | $44.6 | $89.2 | in 79.8M / cache-read 3.20B |
| 2026-08 | $8.4 | $16.9 | in 14.1M / cache-read 633M |

### ⚠ 最重要知見: 使用量の ~97% はキャッシュ読み取り

input トークン数が 100 倍あっても cost は 10 倍程度にしかならない。よって

- **コスト比較では input 単価ではなく cache-read 単価で決まる**
- キャッシュヒット率が高いワークロードほど定額制が有利
- 「トークン数が多い = 費用が高い」という直感は外す

## 3. quota 枯渇の真因は「価格」ではなく「キャパシティ」

月額上限（$60）には実際に達していない。枯渇するのは**短時間窓**：

```
MAX 5h: $34.6(オフピーク) / $69.2(ピーク)   ← 上限 $12 の 3〜6 倍
MAX 7d: $42.4 / $84.8                        ← 上限 $30 を超過
```

つまり**集中作業日（1 日に数十セッション）に 5h / 7d キャップを一度に打ち抜く**
と即停止する。月額ベースの予算判断では停止日を予測できない。

→ quota の判定をする時は **weekly / rolling を主指標にする**。monthly は無意味。

## 4. Go vs OpenRouter の実測比較（同量で実測）

| 月 | OpenRouter（+5.5% 手数料） | Go（$10/月固定） |
|---|---|---|
| 2026-06 | $42.79 | $10 |
| 2026-07 | $58.34 | $10 |
| 2026-08 | $11.42 | $10 |
| **計** | **$112.55** | **$30.00** |

- OpenRouter: 5.5% 手数料（Stripe、最低 $0.80）+ プロバイダ価格パススルー、上乗せなし
- Go: 初月 $5 / 以降 $10。5h$12 / 週$30 / 月$60 の枠

**Go が約 3.8 倍コスパ良好**。.cache-read 単価も Go（$0.007/M）が
OpenRouter（$0.015/M）の半額。

### ただし OpenRouter を選ぶべきケース

| 状況 | 勝者 |
|---|---|
| オープンモデルを月 $60 相当まで | **Go** |
| Claude / Gemini 等のフロンティア | OpenRouter（Go に非掲載） |
| 月 $60 超のヘビーユース | OpenRouter（Go に上限あり） |
| 無料で試したい | OpenRouter（25+ 無料モデル、50 req/日） |

## 5. 実務的な対処方針

问题是**価格ではなく停止の fusilli**。したがって:

1. Go をメインに据える
2. キャップ到達時は **Zen 残高トップアップ**（`Use balance`）で続行
3. それでも高負荷なら、突発的な集中作業を OpenRouter の安価な
   `deepseek-v4-flash` へオーバーフロー

完全移行は同量で月 $42〜58 かかり 4 倍近い出費になるので割に合わない。

## 関連

- [[opencode/provider-availability]] — 現行の provider 可用状況（single-provider 依存リスクも）
- [[design/orchestration-model]] — 実モデル選定の検証（DB `session.model` 列）
