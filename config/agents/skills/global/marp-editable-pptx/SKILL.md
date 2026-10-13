---
name: marp-editable-pptx
description: Use when producing a PowerPoint that must keep editable text (not a flat image), or when porting an HTML/CSS deck to PPTX. Trigger keywords: marp --pptx-editable, 編集可能 pptx, marp pptx notes, marp 独自CSS, marp fragment pptx, PowerPoint テキスト編集.
args: <markdown の正> <出力.pptx>
---

## いつ使う

- PPTX を渡したいが、テキストが編集できる必要がある（1 スライド 1 画像では困る）
- HTML/CSS で組んだデッキを PPTX に持ち込む必要がある

前提ツール: `nix shell nixpkgs#marp-cli`（marp-cli 4.x）、`python-pptx`。

## 手順

1. **変換**（編集可能テキストが出る）:

   ```bash
   marp deck.md --pptx --pptx-editable --allow-local-files -o deck.pptx
   ```

2. **後処理する**（3 つとも必須。python-pptx ではなく XML を直接直す）:

   | 処理 | なぜ要るか |
   |---|---|
   | ノート注入 | Marp の PPTX はノートを受け取らない |
   | フォント置換 | 既定の Noto Serif CJK JP が残る |
   | 部首の正体字化 | 本文が Kangxi 部首へ化ける |
   | 幅の補正 | 折り返した行だけボックスが短くなる |
   | 右端のクランプ | ボックスがスライド外へ出て文字が切れる |

3. **検証**:

   ```bash
   python3 -c "
   from pptx import Presentation
   p = Presentation('deck.pptx')
   imgs = sum(1 for s in p.slides for sh in s.shapes if sh.shape_type == 13)
   txt  = sum(1 for s in p.slides for sh in s.shapes if sh.has_text_frame and sh.text_frame.text.strip())
   print(len(p.slides), 'slides', imgs, 'images', txt, 'text boxes')
   "
   ```

   編集可能なら `txt` が十分大きい（画像版なら `txt=0`）。

## marp が本文を化ける（実測）

`marp --pptx --pptx-editable` は本文の漢字を **Kangxi 部首（U+2F00 帯）** に
置き換える。`画面` → `画⾯`、`自転車` → `⾃転車` のように、**意味と字形は
変わらないので目では絶対に気づけない**。Noto Sans CJK JP なら同じ字形で描かれる
ため PDF 出力でも差が出ないが、PowerPoint を別のフォントで開くと別の字形になる。

正体字化は NFKC で 9 割は戻る。ただし **CJK 部首補足（U+2E80 帯）は NFKC の
分解先が定義されていない**ので表を作る（例: `⻄` → `西`）。

```python
import unicodedata
RADICAL_FALLBACK = {"\u2ec4": "西"}  # CJK 部首補足だけ明示対応

def canonical(text: str) -> str:
    out = []
    for ch in text:
        ch = RADICAL_FALLBACK.get(ch, ch)
        if 0x2E80 <= ord(ch) <= 0x2FDF or 0xF900 <= ord(ch) <= 0xFAFF:
            ch = unicodedata.normalize("NFKC", ch)
        out.append(ch)
    return "".join(out)
```

検出は文字列全体的一致ではなく**コードポイント範囲**で行う。
`grep '画面'` は `画⾯` に一致しない。

```python
rad = {c for n in z.namelist() if "slides/" in n or "notesSlides/" in n
       for t in re.findall(r"<a:t>([^<]*)</a:t>", z.read(n).decode())
       for c in t if 0x2E80 <= ord(c) <= 0x2FDF or 0xF900 <= ord(c) <= 0xFAFF}
```

## テキストボックスがスライドからはみ出す

`--pptx-editable` は **1 visual ライン 1 ボックス**を作り、各ボックスに
`wrap="none"` を付ける。折り返しが発生した行だけ PDF から回収した幅が
実幅より狭くなり、日本語が 1 文字ずつ縦に並ぶ。

逆向きの不具合もある。`len(text) * 1em` で幅を見積もると **ASCII 混在行は
過大評価**になり、ボックス右端がスライド外へ出る。`wrap="none"` の
テキストはボックスで切られるので、**文字が消える**。

対処は 2 段。

1. 必要な幅が足りないボックスだけ広げる（縦に並ぶのを防ぐ）。
2. `x + cx` がスライド幅を超えるボックスは `cx = slide_width - x` に詰める。

```python
pres = z.read("ppt/presentation.xml").decode()
W = int(re.search(r'<p:sldSz[^>]*\bcx="(\d+)"', pres).group(1))
```

縦方向（`y + cy`）は装飾矩形が `== slide_height` で止まる例が多く、
検査すると必ず引っかかる。**横方向だけを見る**。

## 検証は soffice → PDF → Chromium

PPTX の見た目を確認するには変換が要る。

```bash
soffice --headless --convert-to pdf --outdir /tmp/chk deck.pptx
```

- `soffice --convert-to png` は**先頭 1 枚しか出ない**。
  `impress_png_Export` の `PageRange` は効かない。
- PDF を Chromium（Playwright の `connect_over_cdp`）で開くとページ番号ごとに
  確認できる。`#page=N` は同一 PDF 内の再 navigate では効かないので、
  **サイドバーのサムネイルをクリック**する。

## 落とし穴（すべて実測で確認済み）

- **`--pptx-editable` だけではノートが入らない。** `--notes` は text 出力専用で PPTX とは排他。
  必ず python-pptx で注入する。
- **`<!-- コメント -->` のノート記法は PPTX に反映されない。** `--notes` で txt に出るだけ。
  markdown に書いて保持し、PPTX 生成後に注入する。
- **fragment（`-` の段階表示）は PPTX で展開されない。** 段階は HTML / PDF 出力でのみ効く。
  アニメーションの意図はノートに文章で書く。
- **front-matter の `theme:` は外部 CSS を読まない。** Marp 4.x は `<!-- theme: name -->`
  の形式でのみファイル名を拾う。front-matter に書くと**独自 CSS が丸ごと無視され**
  本文が全部素の Markdown になる（`<div>` も落ちる）。確実に効かせるには CSS の中身を
  `<style>` タグで直接 deck に埋める。
- **`html: true` が必要。** これを忘れると生 HTML が全部消える。
- **section の既定を打ち消す。** Marp の `section` は `padding: 78.5px` /
  `place-content: safe center center` / `font-size: 29px`。CSS を移植しただけでは
  大きな余白と中央寄せが残る。`padding` と `place-content: start` を明示する。
- **`layout: title` は Marp では `lead` になる。** CSS 側のセレクタも
  `section.layout-title` → `section.layout-lead` に直す。
- **`<div>` の中に Markdown を書くと解釈されない。** CommonMark の HTML ブロックは
  空行で終わる。独自レイアウトを組むなら **中身を全部生 HTML で書く**。
- **`<img>` は残る。** `--pptx-editable` でも `![](a.png)` は `ppt/media/` に入る。
  テキストだけがネイティブ。
- **LibreOffice の HTML→PPTX は使えない。** `soffice --convert-to pptx deck.html` は
  Writer/Web として開いて `Unspecified Application Error` で失敗する。
- **PPTX 仕様の折り返し差。** PDF と 1 ピクセルも一致させたいときは編集可能版は使えない。
  その場合は `--pptx`（画像版）を使う。

## ノート

PPTX にノートを入れるため、markdown とは別に
`[{index, title, note}]` の JSON を持っておくとよい。`make` に組み込むなら
生成スクリプトで markdown から抽出して JSON に落とす。

アニメーションの意図は fragment ではなくノートに書く：

```
【アニメーション】上のスライダー 3 本を動かした流れを 3 段階で話す。
  1) 既定の重み
  2) 視界だけを見る
  3) 重みをすべて 0
```

## 既存 CSS の移植

HTML/CSS のデッキを Marp に持ち込むとき、テーマを作り直さず
**元の CSS 定数を import して置換する**。二重管理になるとズレる。

```python
import importlib.util

spec = importlib.util.spec_from_file_location("build_html", "build_html.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

css = m.CSS
css = css.replace("section.slide", "section")   # Marp は 1 スライド = 1 section
css = re.sub(r"@page\s*\{[^}]*\}", "", css)      # 印刷専用は不要
css = re.sub(r"(page-break-[a-z-]+|break-[a-z-]+)\s*:[^;]+;", "", css)
```

元の CSS 定義に Python 側の処理が混ざっているなら、import せず CSS だけ手で写すほうが安全。

## 発表資料に実画面を入れる

統一カードやピクトグラムだけのスライドは「AI 感」が出る。実物を入れると消える。
SSOT として、公開アプリの実スクリーンショットを `make` のターゲット化しておく。

- 生データはリポジトリ直下の `.playwright-mcp/`（ブラウザが書く場所）
- 発表ディレクトリに `make_shots.py` を置き、トリミングと赤枠を自動化
- `deck.md` は加工後の PNG だけを参照する。`$(SHOTS)` を HTML/PPTX の依存に入れる
- 生画像が無くても `make` が通るように **`shots` は手動ターゲット**にする

## 図は HTML/CSS で書く

**diagram / chart は HTML + CSS で書き、画像にしない。** 画像にすると PPTX で文字を編集できない。

- 対象: 構成図、フロー、バー、数値の表
- 例外（画像でよい）: 写真、スクリーンショット、地図のポリライン。幾何かラスタで CSS では表現できない
- SVG も編集性には効かない（PPTX 化でラスタライズされる）
- procon の発表資料では `drafts/37-free-widenavi/README.md` の「図の作り方」が正

## 事例

procon の第37回発表資料（`.private/ws/presentation/drafts/37-free-widenavi/`）で
`deck.md` + `script.md` + `build_html.py` の CSS から
`make_marp.py` で Marp デッキを自動生成し、`marp --pptx-editable` →
`inject_notes.py` の 2 段で 15 スライドの編集可能 PPTX を作っている。
`make_marp.py` の `script_key()` は数字・記号・括弧を落とした緩いキーで
script.md の原稿と突き合わせる（見出し表現がズレて取りこぼすのを防ぐ）。
