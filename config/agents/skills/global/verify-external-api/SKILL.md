---
name: verify-external-api
description: Use when integrating with any external product's API / CLI / webhook, or before writing a skill from documentation, to verify the contract against the real server first. Covers version pinning, capturing real inputs instead of synthesizing payloads, the three test traps (self-made payload passes, passing by doing nothing, falsy stub values), inversion testing, and the structural limit of probing a session that is measuring itself. Trigger keywords: verify external api, contract verification, spreed version, synthesize payload trap, test passes by doing nothing, inversion test, dry-run first, real event log, 未確認.
---

# 外部 API の契約を実機で先に検証してから skill にする

外部製品（NextCloud Talk, Cloudflare, 各 SaaS）の API を前提に実装すると、
**バージョン違い・テストが自分の作った偽物を通す・テストが「何もしない」ことで PASS する**
という 3 つの罠にほぼ必ず嵌まる。契約は実機で確認してからコードと skill に落とす。

## いつ使うか

- 外部サービスの API / CLI / webhook を初めて使うとき（特に**バージョンを跨ぐ**とき）
- 「E2E で PASS した」と報告する前
- 既存の skill / ドキュメントに書かれた事実を鵜呑みにせず確認したいとき

## 手順

### 1. バージョンを実機で確定する

```bash
occ app:list --enabled | grep -i spreed      # → spreed: 25.0.0
```

読解はバージョンを固定してから。**stable 系ドキュメントは別物**:
sv01 は NC35 / Talk 25 だが、stable31 は Talk 21 で feature 排他制約すら違う。

### 2. 実 inputs を集める（自作しない）

| 対象 | 採取すべきもの |
|---|---|
| webhook | **実 event ログ**。payload を自分で書かない |
| CLI | exit code + stdout + stderr をファイルに保存（例外で捨てない） |
| HTTP | ヘッダ + 生 body（**再シリアライズ禁止**、バイト列が変わる） |
| API | 実レスポンス。型定義やドキュメントの抜粋ではない |

### 3. 1 つずつ dry-run する

コマンド 1 本 / リクエスト 1 通を実行し、出力をファイルに落とす。
複数まとめて流すと、どれが原因か分からなくなる。

### 4. 観測できた事実だけをコードと skill に書く

- **未確認の項目は「未確認」と明示**して残す。断定しない
- 観測した内容とドキュメントが食い違う点をメモする
- 各事実に **出所**（ログ行・exit code・API パス）を紐づける

### 5. テストは 3 点セット

1. **stub の各分岐に実行 counter** を置き、`counter > 0` をアサートする
2. **反転テスト**: 修正を戻した copy に同じテストを走らせ、**FAIL すること**を確認する
3. **falsy trap**: テスト stub の 0/空/未設定を「未生成」と判定しない（`completed: i` の `i=0` が最頻）

## 検証方法

各主張に観測 source があるか確認する:

```bash
rg -n 'exit code|log line|path' <skill body>   # 出所が書けているか
```

- 反転テストが FAIL することを確認したか
- 「未確認」リストが残っているか（残っていないなら、：**全部 instrument する Preferred**）
- テストの PASS に対して **「意図した経路を通った」証明**óstoch を確立しているか

## 落とし穴

1. **自作 payload でテスト → PASS**：実際に壊れた箇所（`Activity` 判定）を自分で再現し
   全 message を捨てていたのに PASS していた。webhook 契約 7 項目中 6 項目が正しいまま肝心の type だけ 180 度逆
2. **テストが「何もしない」ことで PASS**：stub の TDZ 参照エラーで空 message 分岐が 1 度も実行されなかった。
   4 度嵌まった。**PASS は意図した経路を通った証明ではない**
3. **バージョン未確認で stable 文書をよむ**：`talk:room:create` に `--output` が無いのは
   `parent::configure()` を呼びsquashないため。バグではなく実装
4. **自称の diff と内部 signal は disagree**：`Promise.race` で throw した probe は
   code が undefined。probe を `try/catch` で黙らせると真因が隠れる
5. **自分の turn を測るプローブ**：被測定対象の session が測っている agent 自身だと
   **検証できない**（ack も reply も観測できない）。人による目視確認が唯一
6. **「来なかった」と「返事がない」は区別できない**：ack を post する。ack が無い事象と
   到着 acknowledgement の無い事象は区別がつかない
7. **例外で evidence を捨てる**：`try/catch` で exit code も stderr も捨てると、
   実は exit 1 で**排他制約違反**だったのが「不明」で終わる
