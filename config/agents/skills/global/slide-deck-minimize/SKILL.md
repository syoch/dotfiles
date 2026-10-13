---
name: slide-deck-minimize
description: Use when measuring or reducing slide cognitive load (text volume, element count) against evidence-based thresholds. Trigger keywords: スライド, 発表, プレゼン, presentation, slide, 文字数, 要素数, 認知負荷, cognitive load, 5x5 rule, one idea per slide, Kosslyn, Mayer, 減量, スライドを薄く.
args: &lt;deck.md&gt; [build_html.py]
---

# 発表スライドの認知負荷を減らす（汎用）

## 何をやるか

発表スライドの **文字数**と**要素数**を測り、認知負荷の観点から閾値オーバーを削る。
ジャンル固有の規則（学術発表の構成・日本語の話速・図の描き方）は別 skill に分ける。

| 領域 | skill |
|---|---|
| 認知負荷の閾値と減量（本書） | `slide-deck-minimize` |
| 学術・技術系発表の構成と質疑 | `academic-talk` |
| 日本語の文字数予算と話速 | `presentation-japanese` |
| 図・チャートの設計 | `slide-data-viz` |

## 使う場面

- 「スライドが文字数が多い／要素が多い」と言われた
- 認知負荷の閾値に対して objectively 測りたい
- どのくらい削ればよいか基準がほしい

## 判断の根拠（複数ソース）

### Naegle KM, "Ten simple rules for effective presentation slides", PLoS Comput Biol 2021
<https://pmc.ncbi.nlm.nih.gov/articles/PMC8638955/>

| Rule | 内容 |
|---|---|
| 1 | 1 スライド 1 命題 |
| 2 | **1 スライド 1 分** |
| 3 | 見出しで命題を書く（「結果」ではなく結論） |
| 4 | 説明できない要素は乗せない |
| 6 | テキストだけのスライドを禁じ、可視化で命題を裏づける |
| 7 | **要素は 6 個まで。7 個で認知負荷が 500% 増**（Phillips, TEDx） |
| 8 | 聞いていなくても内容が分かるようにする |

Rule 7 の根拠は、同じ認知チャネル（視覚・言語）を視覚と聴覚で分担させる原則。
図は聴覚と別チャネルで処理されるため、読み上げと併存しても負荷が増えない。

### Phillips DJ, "How to avoid death by PowerPoint", TEDx 2014
上一次元の出典。認知要素の上限を 6 とした出所。

### Kosslyn SM et al., "PowerPoint presentation flaws and failures: A psychological analysis", Front Psychol 2012
<https://doi.org/10.3389/fpsyg.2012.00001>
- アニメーションは注意を逸散させる。装飾的なアニメーションは使わない。
- 人は図から理解できるが、「，双方のチャネルを同時に使うと」的一方をobin する。

### Mayer RE, "Nine Ways to Reduce Cognitive Load in Multimedia Learning", Educ Psychol 2003
- 冗長原則（redundancy principle）：図に已是ある説明を重ねない。

## 日本語発表での実用閾値

日本語は英語の 2.5 倍文字数（東工大 言語心理学 2024）。
英語圏の「5 行 × 5 語」をそのまま日本語へ当てると溢出する。

| 指標 | 閾値 |
|---|---|
| 1 スライドの要素数 | 6 個 |
| 1 スライドの文字数 | 80 字 |
| 1 行の文字数 | 20 字 |

## 手順

### 1. HTML に対して機械的に数える

| 対象 | 要素数への加算 |
|---|---|
| 見出し | 1 |
| 表 | 3（タイトル・本体・凡例） |
| 箇条書き 1 項目 | 1 |
| カード（強調枠） | 1 |
| 図 | 2（図そのものと凡例） |
| ステップ（横一連の図） | 1 |
| バッジ（丸アイコン付き） | 1 |
| KPI（大きな数字） | 2（数字とラベル） |
| 段落 | 1 |

ページ番号・フッターは数えない。

### 2. 閾値超過を特定する

```
要素数 > 6  または  文字数 > 80  →  要修正
```

`scripts/check_load.py` を使う。deck が 0 なら 1、超過があれば枚数と内訳を出して 1 を返す。

### 3. 削る（この順に効く）

1. **注記（`class="note"`）を消す**。最優先。説明は口頭で行う（Mayer 冗長原則）。
2. **表の行を減らす**。全部公开发言しない。質疑に出た分だけ appendix へ。
3. **カードとバッジのラベルを 5 語以内にする**。
4. **出典や分母の注記を appendix の 1 枚にまとめる**。
5. **要素数が 6 を超えるままなら、要素を削る**（スライドを分けるのではなく）。

### 4. 検証

- HTML を取り直して数え直す。
- PDF をレンダリングし、注記が 1 ページに収まっているか目視する。
- 発表台本（`script.md`）が新しいスライドに対応しているか確認する。
- **文字化けチェック**: 韓国語・簡体字・U+FFFD が混ざっていないか。
- **主張の照合**: 数値が一次測定データと一致しているか。

## 落とし穴

- **「1 分ルール」と「6 要素ルール」は別**。要素数が少なくても 1 分で話せなければ Rule 2 違反。
- **注記を消すと根拠が消える**。数値の分母（例「10 経路の平均 98.8%」）は残す。
- **図の凡例は画像の内側に描くと縮む**。HTML 側に凡例を出す。
- **画像スライド**は要素数に `<img>` を 2 として数える。過少評価すると図を詰めすぎる。
- **投影は 1280×720**。CSS は px 指定で、絶対指定高さの画像だけ `has-figure` クラスで固定する。
- **入れ子 `<svg>` は Chromium で親 viewBox を継承しない**。`<g transform>` に包む。
- **余白が片側に偏る**。要素が少ないスライドは縦中央に寄せる（`sparse` クラス）。

## 関連ファイル（WideNavi 実例）

- deck: `.private/ws/presentation/drafts/37-free-widenavi/deck.md`
- 変換: `build_html.py`（Marp 記法の部分集合を自前で処理する）
- 図の生成: `route-svg.ts` / `svg2png.mjs`
- 実測: `measure-live.ts` / `route-diff.ts`
- 診断: `scripts/check_load.py`
