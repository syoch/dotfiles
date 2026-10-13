---
name: academic-talk
description: Use when building a time-boxed academic/technical talk (学会発表・コンテスト・社内技術発表) with Q&A, or when preparing backup slides and predicted questions. Trigger keywords: 学会発表, 技術発表, コンテスト発表, academic talk, conference presentation, Q&A, 質疑応答, 想定問答, backup slides, 8分発表, 発表構成, 研究発表, time-boxed talk, 抄録, 起点, forecast.
---

# 学術・技術系の発表を組み立てる

## 何をやるか

学会・コンテスト・社内技術発表など、**質疑応答が付く技術発表**の構成と
質疑応答の準備をする。認知負荷の閾値（`slide-deck-minimize`）とは別の軸で扱う。

| 領域 | skill |
|---|---|
| 認知負荷の閾値と減量 | `slide-deck-minimize` |
| **学術・技術発表の構成と質疑**（本書） | `academic-talk` |
| 日本語の文字数予算と話速 | `presentation-japanese` |
| 図・チャートの設計 | `slide-data-viz` |

## 使う場面

- 8 分 + 質疑 4 分のような time-boxed な発表
- 論文や技術資料を口頭発表に置き換える
- 質疑応答で問われそうな想定問答が要る
- 発表の前提条件（時間・会場・機材・採点方式）を満たしたい

## 判断の根拠（一次ソース）

### Jennifer Widom, "Tips for a Good Conference Talk"（Stanford, SIGMOD '05 プログラム委員長）
<https://cs.stanford.edu/people/widom/conference-talks.html>

- **発表は論文の代わりではない。** 論文を読んでAlbizu したいcardia への広告である。
- 時間内に収まるよう慎重に計画する。時間を守る座長は容赦なく切られる。
- 論文の全結果を載せるのは不可能。各結果から代表的な図を 1〜2 個選ぶ。
- 動機を説明し、アプローチと主要な結果を述べる。
- **スライドに全て書いてから読み上げない。** スライドは手がかりと図だけにする。
- 例は単純に要点を強調して、聴衆が内容を理解する時間を与える。
- 複数回リハーサルし、時間を計測する。
- 質疑では**聞き取れた人のために質問を繰り返させる**。理解の確認と、考える時間を确保するため。

### David Karger CMU, "Oral Presentation Advice"
<https://www.andrew.cmu.edu/user/lakoglu/courses/14CSE512/resources/OralPresentationAdvice.pdf>

- **1 スライドあたり 2 分**（-talk としては標準的なペース）。20 分なら約 12 枚。
- 典型的な構成:
  - Title / author / affiliation（1 枚）
  - Forecast（1 枚）— 記憶に残したい 1 つの命題
  - Outline（1 枚）— 発表の構造
  - Background: Motivation / Problem（1〜2 枚）、Related Work（0〜1 枚）
  - Methods（1 枚）— 短い発表では浅く
  - **Results（4〜6 枚）— ここが本丸**。解釈をつける。数値の羅列はしない。
  - Summary（1 枚）、Future Work（0〜1 枚）
  - Backup slides（0〜3 枚、発表時間外）

### Jennifer Widom / Eric Mernst UW, "How to give a technical presentation"
<https://homes.cs.washington.edu/~mernst/advice/giving-talk.html>

- 論文の表をそのまま PDF で貼り付けない。**読みやすいように組み直す**。
- スライドは約 1 分 1 枚にする。
- 説明的なタイトルを使う。同じタイトルを複数枚に使わない。
- タイトル直後の 1 枚は動機の提示（問題の例）。
- **目次スライドで始めない。** 退屈で、構造がまだ伝わらない。
- 最後の枚は「貢献」または「結論」。**Future Work や「Thank you」で終わらない。**
- 質疑中は結論の枚を下げたままにする。

### VLDB Session Guidelines（公式）
<https://vldb.org/2015/session-guidelines.html>

- **PDF スライドを推奨する**（PowerPoint や Keynote のバージョン差を回避）。
- 15 分前に会場へ到着し、貸出ノートパソコンで動作確認する。
- 前の発表者の質疑中に演台へ上がって準備する。
- Backup スライドは A1, A2 のように番号を振り、素早いジャンプに備える。

### SPIE, "A Practical Guide to Conferences"
<https://spie.org/news/a-practical-guide-to-conferences-part-i-preparing-for-a-presentation>

- 15 分発表なら 12〜13 枚（タイトルを除く）。
- 練習は 2〜3 分の質問時間を超えて、質問が出なくなるまで続ける。
- 図や表を引用したら出典を直下に記す。

## 発表時間と枚数の目安

| 発表時間 | 主旨の枚数（タイトルと目次を除く） |
|---|---|
| 5 分 | 3〜4 枚 |
| 8 分 | 6〜7 枚 |
| 10 分 | 8〜10 枚 |
| 15 分 | 10〜12 枚 |
| 20 分 | 12 枚 |

## 8 分発表の標準構成

| # | 役割 | 枚数 | 時間 |
|---|---|---|---|
| 1 | タイトル（チーム名・氏名） | 1 | 0:15 |
| 2 | 起点（記憶に残したい 1 命題） | 1 | 0:25 |
| 3 | 動機・問題提起 | 1 | 0:35 |
| 4 | アプローチ概要 | 1〜2 | 1:00 |
| 5 | 実装・手法 | 1〜2 | 1:15 |
| 6 | **結果** | 2〜3 | 1:45 |
| 7 | 限界（隠さず） | 1 | 0:25 |
| 8 | 結論（貢献） | 1 | 0:15 |
| — | バッファ | — | 0:20 |
| — | 質疑応答 | — | 4:00 |

Backup（質疑用・発表時間外）は 10〜30 枚。番号を A1, A2 と振る。

## 手順

### 1. 制約を確認する

- 発表時間、質疑時間、予鈴が鳴る時刻
- 会場の機材（HDMI か、Type-A か）
- **ナレーションの可否**（多くの競技大会では禁止。口頭のみ）
- 発表者数（複数人なら質疑には発表者だけが答える）
- **採点方式**（プレゼン以外の審査があるか: 実演・マニュアル審査・作品展示など）
- 赛区に提出したソースの扱い（当日審査員が直接閲覧するか）

### 2. 起点（1 命題）を決める

記憶に残したい 1 つの命題を先に定義する。
これがあると、8 分で全てを話せない制約下でも外すものを判断できる。

### 3. 結果を 2〜3 枚に絞る

- 代表図を 1〜2 個選ぶ。
- **数値の羅列ではなく解釈をつける**。
- 限界は隠さず明示する（審査員の主要関心が実証のとき特に効く）。

### 4. 質疑応答を準備する

想定問答を `qa.md` にまとめる。想定質問のソース:

- 審査員の既知の関心（過年度の質疑応答から抽出できるもの）
- 自分の発表で主張したことの弱点
- 応募書類や抄録との不整合
- 実装上过酷な点（ハードコード、マジックナンバー、テスト不足）

各項目に「発表で宣言済みか」「答えると不整合になるか」を書く。

### 5. Backup スライドを用意する

質疑に出そうな詳細（表の全文、ベンチマーク、方法の詳細）を A1, A2 と番号付きで。
質疑中は結論の枚を下げたままにして、Backup へ切り替える。

## 落とし穴

- **「全部話す」としない。** 発表は論文への招待広告である（Widom）。
- **目次で始めない。** 構造を述べるには早い（Mernst）。
- **「Thank you」で終わらない。** 結論の枚を下げたまま質疑へ（Mernst）。
- **限界を隠さない。** 隠すと質疑で発覚して信頼を失う。
- **Backup を 10 枚以上作る。** 予想外の方向から質問が来る（VLDB）。
- **質疑で「他の人に任せる」で済ませない。** 発表者が答える。
- **本番の 15 分前にテストする。** 不具合は時間内に致命的。
- **ナレーションを準備しない。** 多くの競技大会で禁止されている。
- **採点対象の審査が別にある。** 実演やマニュアル審査があれば、発表内容と整合させる。
- **文字数で時間を測らない。** 話速は日本語なら `presentation-japanese` を見る。

## 関連ファイル（WideNavi 実例）

- 発表原稿: `.private/ws/presentation/drafts/37-free-widenavi/script.md`
- 想定問答: `qa.md`
- 過年度の審査員関心分析: `.private/ws/presentation/reports/2026-09-30-審査員の関心-自由部門質疑応答分析.md`
- 発表構成の設計資料: `.private/ws/presentation/reports/2026-10-04-過去の発表履歴まとめ-発表構成設計資料.md`
