---
name: slide-data-viz
description: Use when creating or reviewing charts, maps, diagrams, or comparison figures for a presentation, or when applying Tufte principles (data-ink ratio, chartjunk, lie factor) to slide graphics. Trigger keywords: 図, チャート, グラフ, 可視化, マップ, 比較図, SVG, matplotlib, Recharts, Tufte, data-ink ratio, chartjunk, pie chart, 3D effect, 凡例, legend, small multiples, 投影, プロジェクタ, 地図, 経路図.
args: &lt;chart|figure|map|diagram&gt; [message]
---

# 発表用の図とチャートを設計する

## 何をやるか

スライドに載せる**図・チャート・マップ・比較図**を設計する。
`slide-deck-minimize` が「要素を何個置くか」を扱うのに対し、本書は
**その図がどう描かれるべきか**を扱う。

| 領域 | skill |
|---|---|
| 認知負荷の閾値と減量 | `slide-deck-minimize` |
| 学術・技術発表の構成と質疑 | `academic-talk` |
| 日本語の文字数予算と話速 | `presentation-japanese` |
| **図・チャートの設計**（本書） | `slide-data-viz` |

## 使う場面

- 発表用のチャートを生成する（SVG / matplotlib / Recharts など）
- 既存の図が読みにくい
- 2 つの対象を並べて比較したい
- 地図上に経路や既に決まった線を重ねたい

## 判断の根拠（一次ソース）

### Edward Tufte, "The Visual Display of Quantitative Information"（1983 / 2001）
<https://www.edwardtufte.com/notebook/chartjunk>

| 原則 | 内容 |
|---|---|
| **Data-ink ratio** | データインク / 総インク。最大化する |
| **Chartjunk** | 情報を伝えない内装。消す |
| **Lie factor** | 図上の変化量 / 実際の変化量。1.0 なら誠実 |
| Small multiples | 同じ形式の小図を並べる |

Data-ink ratio を上げる手順（Tufte 自身の 5 ステップ）:

1. **データを最初に見せる**（Above all else, show the data）
2. **Data-ink ratio を最大化する**
3. **データでないインクを消す**（装飾・罫線・枠）
4. **余分なデータインクを消す**（2D で足りるところを 3D にしない）
5. **推敲する**

**消しゴムテスト**: データ情報を失わずに消せるものは消す。

### John Stasko CMU, "Tufte's Design Principles"（CS 4460 講義ノート）
<https://faculty.cc.gatech.edu/~stasko/4460/Notes/tufte.pdf>

- 視覚属性の値はデータ属性の値に**直接比例**させる。
- 格子線・目盛・凡例は**最小限にするか統合する**。
- **データ密度を最大化する**。地図と時系列は単位面積あたり数千の数値を載せられる。

### Gillan & Richman, "Minimalism in Information Visualization"（ACM）
<https://dl.acm.org/doi/epdf/10.1145/1362550.1362587>

data-ink ratio を上げると**応答時間が短くなり、正解率が上がる**（実証あり）。

### 色覚（Naegle PLoS Rule 7 経由）

- **5〜10% の人には色覚の特徴がある**（赤緑が最多、次に青黄）。
- 色は**唯一の識別手段にしない**。形・パターン・直接ラベルと併用する。

## スライドでの図の原則

### 1 図 1 命題

Naegle PLoS Rule 6 は**テキストだけのスライドを禁じ**、可視化で命題を裏づけることを求める。
1 枚の図に複数の命題を詰めると、聴衆はどれも読み取れない。

### 立体効果を使わない

- 奥行き・影・遠近法は情報を加えない。
- 2D のデータに 3D を重ねない。

### 軸はデータ範囲だけ

- 軸線は**データが存在する範囲だけ**。ゼロから引き始めない。
- **上辺と右辺の軸線と枠は chartjunk**。下辺と左辺で足りる。

### 円グラフを避ける

値の順序が視覚的に読み取れないため**低密度**。
**値の降順に並べた横棒**を使う。

### 直接ラベルを使う

- グラフのすぐそばに名称を置く。
- **凡例を作ると、目が往復する。** 凡例は作らない。

### 色は最小限

- グレーを基本に、**アクセントは 1 色**。
- **4 色以上使わない**。
- 順序データに虹色の配色は使わない。

### 文字は 24pt 以上

投影は**後ろの席から**見える必要がある。
**図中の文字も含めて 24pt 未満にしない**。

## 2 つの対象を比較する図

### 小さな複数（small multiples）

同じ区間に対して複数のモード・複数の条件を描くとき:

- **同じ縮尺・同じ範囲**で並べる。縮尺が違うと比較が成立しない。
- パネル間に十分な余白を空ける。
- 各パネルの題名は中央寄せ。

### 差分の強調

2 本の経路・2 つの条件を比較するとき:

1. **基準を灰色・破線で描く**（やや太め）
2. **対象を色で描く**（実線）
3. **乖離した区間だけ点を打つ**（赤・半透明）

これで「どう変わったか」が一目で分かる。

## 手順

### 1. 命題を 1 文で書く

その図で聴衆に理解させたいことを**1 文**にする。
書けないなら、図が複数の命題を混ざえている。

### 2. データ源と座標系を確認する

- 図は**実データ**から描く。模式図は模式であると明記する。
- 地図なら**投影を合わせる**。経度 1 度 = 緯度 1 度 × cos(緯度) を明示的に入れる。
  放置すると縦長に歪む。
- 縮尺を明示する。

### 3. chartjunk を消す

- 罫線を消すか、極薄の灰色にする。
- 影・グラデーション・立体効果・装飾を消す。
- **消しゴムテスト**を当てる。

### 4. 色を決める

- ベースはグレー。
- アクセントは 1 色。
- 識別が色だけに依存しない形にする。

### 5. ラベルを直接付ける

- 凡例を作らず、グラフのそばに文字を置く。
- 数字は右端に寄せる（`font-variant-numeric: tabular-nums`）。

### 6. 投影で確認する

- 実際のプロジェクタで、**後ろの席から**見えるか確認する。
- **グレースケールでも判別できるか**（色覚ハック）。

## 落とし穴

- **入れ子の `<svg>` は Chromium で親の viewBox を継承しない。** `<g transform>` に包む。
- **地図の投影を放置すると歪む。** cos(緯度) 補正を入れる。
- **パネルごとに縮尺が変わると比較できない。** 共通の境界領域を使う。
- **凡例を画像の内側に描くと縮む。** HTML 側（CSS）へ出す。
- **立体表現は避ける。** 影は chartjunk。
- **軸をゼロから引き始めない。** 差が可視化されなくなる。
- **円グラフは並び順が視覚的に読み取れない。** 横棒に置き換える。
- **色だけで識別しない。** 赤緑の混同は 5〜10% の人に影響する。
- **Overpass API は User-Agent 無しで 406 を返す。** 連打はキャッシュする。
- **数値を口頭で読むときは言い換える。** 「98.8%」は「約 99%」。
- **投影のグラフは線幅が 1px 以下だと消える。** 2px 以上にする。

## 関連ファイル（WideNavi 実例）

- 経路比較の SVG 生成: `.private/ws/presentation/drafts/37-free-widenavi/route-svg.ts`
- SVG から PNG への変換: `svg2png.mjs`（chromium-cdp の `Page.captureScreenshot`）
- 道路データの取得: Overpass API（User-Agent 必須。無いと 406）
- 採用した配色: 緑 `#5f8d7d`、墨 `#514f5c`、危険側 赤 `#b86e6d`（WideNavi の紹介動画から実測）
