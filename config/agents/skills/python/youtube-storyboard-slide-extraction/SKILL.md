---
name: youtube-storyboard-slide-extraction
description: Use when a YouTube video's normal video/audio formats are unavailable (403 or stream-only) but you still need to know what appeared on screen, e.g. recovering the slide count, slide titles, or per-slide content of conference and contest presentations from storyboards. Trigger keywords: storyboard, sb0, storyboard3_L2, i.ytimg.com/sb, yt-dlp storyboard, rows columns fps, スライド枚数, 発表スライド, 格子分割, dhash, コンタクトシート.
---

## いつ使うか

- YouTube の通常動画 (video/audio format) が 403 や stream-only で取得できないが、
  映像に何が映っていたか知りたい時。
- 発表や会議の配信から「スライド何枚だったか」「各スライドに何が書かれていたか」を復元する時。
- 全文を保存せずに画面だけ構造化したい時。

通常動画が取得できる場合は ffmpeg で単発フレームを抜く方が確実です。
この skill は通常動画が使えない場合の代替手順です。

## 前提条件

- storyboard は 1 枚 = 1 画面ではありません。1 枚の中に格子状に複数画面が並びます。

## 手順

### 1. ジオメトリを確定する

`format_id` は `sb0` 形式で "storyboard" 文字列を含みません。
`"storyboard" in format_id` で判定すると取りこぼします。
`fid.startswith("sb")` で判定します。

```bash
nix-shell -I nixpkgs=channel:nixos-25.05 -p yt-dlp --run "python3 reference/sbraw.py"
```

`rows` / `columns` / `fps` / `fragments` を全部 dump します。
`interval = 1 / fps`、`total_frames = duration * fps` です。
channel を固定しないと `rows` が読めない channel があります。

### 2. 最良の level を選ぶ

分解能とサンプル密度は独立に決まります。
全 level の rows×cols・タイル幅・間隔・sheet 数を並べて比較します。

実測例（21,896 秒の配信）:

| level | rows×cols | タイル | sheet | 間隔 | sheets |
|---|---|---|---|---|---|
| sb0 | 3×3 | 320×180 | 960×540 | 9.994 秒 | 244 |
| sb1 | 5×5 | 160×90 | 800×450 | 9.994 秒 | 88 |

この例では sb0 が分解能と密度の両方で最良でした。

### 3. sheet をダウンロードする

URL は次の形です。

```
https://i.ytimg.com/sb/<videoId>/storyboard3_L<N>/M<sheetIndex>.jpg?sqp=...&sigh=...
```

**URL の `L<N>` は yt-dlp の `format_id`（`sb0`…`sb3`）と逆向きに対応します。**
`sb0` が `storyboard3_L3`、`sb1` が `storyboard3_L2` です。
`fragments[0].url` ではなく `format['url']` を読んで level を確認します。

`sigh` 付きの URL をそのまま使います。
署名なしは 403 になります。

### 4. タイルに分割して時刻を付ける

- フレーム f の sheet は `f // (rows * cols)`。
- フレーム f のタイルは `f % (rows * cols)`（row-major）。
- フレーム f の時刻は `f * interval`。

分割と同時に dhash と縮小画像の輝度配列を `npz` に保存します。

```bash
nix-shell -p python3Packages.pillow -p python3Packages.numpy \
  --run "python3 reference/extract_tiles.py sheets"
```

### 5. 画面変化を検出する

- dhash (8×8) のハミング距離。
- 32×18 縮小画像の平均絶対差。

平均絶対差は明確に二峰になります。
同一画面は 0.5 未満、画面変更は 15 を超えます。
実測分布を確認してから閾値を決めます。

### 6. コンタクトシートで目視確認する

各セグメントの代表タイルをグリッドに並べ、時刻ラベルを付けます。
**輝度によるスライドと会場カメラ映像の分離は機械的に行いません。**
投影画面の輝度はチームごとに大きく偏ります。
全画面が閾値未満のチームがあると結果が 0 枚になります。

```bash
nix-shell -p python3Packages.numpy --run "python3 reference/segment.py"
nix-shell -p python3Packages.pillow --run "python3 reference/make_contact.py"
```

### 7. 発表区間ごとに分ける

字幕の司会発言（`N 番目の発表` / `発表を終わりたい`）で区間を決めます。
発表番号は ASR の揺れが大きいため名簿と照合します。

## 検証方法

- コンタクトシートが時系列順に並んでいれば row-major と時刻の対応は正しいです。
- 隣接する 2 タイルの境界時刻と字幕の司会発言時刻が合えば区間切り出しは正しいです。
- ハミング距離と平均絶対差が同じ変化を指すか確認します。

## 落とし穴

| 落とし穴 | 対処 |
|---|---|
| `format_id` に "storyboard" が無い | `startswith("sb")` で判定する |
| 1 枚 = 1 画面と誤認する | 複数 level の rows×cols を必ず dump する |
| 「20 秒以上保持」で枚数を数える | interval 以上保持された各セグメントを 1 画面とする |
| 輝度閾値で会場カメラ映像を除く | 目視で除外する |
| 隅の小さな装飾文字の意味を誤読する | 解像度では本文が読めない。字幕で補う |
| 報告書に枚数を確定値と書く | 「下限値」と「10 秒未満は検出不可」を明記する |

## 実例

第36回高専プロコン自由部門の発表 21 本からスライド構成を復元しました。
スライド枚数は 7 枚から 34 枚で中央値は 18 枚でした。
成果物は `.private/ws/presentation/reports/2026-10-05-procon36-自由部門-発表スライド構成の復元.md` にあります。
