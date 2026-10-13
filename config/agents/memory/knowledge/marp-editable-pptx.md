# marp-cli で編集可能な PPTX を作る（2026-10-05 実測）

## 結論
- `marp --pptx --pptx-editable` は**ネイティブ PowerPoint テキスト**（`<a:t>` run）を出す。編集できる。
- `--pptx-editable` なしは 1 スライド 1 画像（`ppt/media/` に PNG、テキスト 0）。
- `--pptx-editable` ありは `ppt/media/` 0 枚、テキスト run だけ。図は `<img>` として残る。
- 16:9 は `size: 16:9`。PPT は 13.333 x 7.5 インチ。

## 落とし穴（実際に踏んだ）

1. **`--pptx-editable` だけだとノートが入らない。** Marp の PPTX 出力はノートを
   受け取らない（`--notes` は text 出力のみで PPTX と排他）。`marp-notes.json` を別に作り、
   `python-pptx` の `slide.notes_slide.notes_text_frame.text` で注入する。
   `slide.notes_slide` は空前でも PPTX 上に作られるので触るだけでよい。

2. **`<!-- ノート -->` は PPTX に入らない。** Marp 記法としては正しい（`--notes` で txt になる）が
   PPTX には反映されない。ノートは markdown 側で保持して PPTX 生成後に注入する。

3. **fragment（段階表示）は PPTX では展開されない。** 15 スライドの markdown に
   3 箇所の fragment を書いても PPTX は 2 枚のまま。段階表示は HTML / PDF 出力でのみ効く。
   → アニメーションの情報はノートに文章で書く（`FRAGMENT_HINT` のような連想配列）。

4. **front-matter の `theme:` だけでは外部 CSS を読まない。** Marp 4.x は
   `<!-- theme: name -->` の形式でのみ CSS ファイル名を拾う。front-matter に
   `theme: marp-theme` と書くと**独自 CSS が丸ごと無視される**（本文が全部素の Markdown になる）。
   確実に効かせるには CSS の中身を `<style>` タグで直接 deck に埋める。

5. **section の既定スタイルを打ち消す必要がある。** Marp の `section` は
   `padding: 78.5px` / `place-content: safe center center` / `font-size: 29px`。
   `build_html.py` 由来の CSS を `section.slide` → `section` に置換しただけでは
   上の既定が残り、大きな余白と中央寄せになる。`padding` と `place-content: start` を明示する。

6. **`layout: title` は Marp では `lead` になる。** `section.slide.layout-title` を
   `section.layout-lead` にリネームしないと表紙の特別スタイルが効かない。

7. **`html: true` でないと deck.md の生 HTML（カード・表・図）は全部落ちる。**

8. **LibreOffice の HTML→PPTX 変換は使えない。** `soffice --convert-to pptx deck.html` は
   Writer/Web として開いて `Unspecified Application Error` で失敗する。

## 手法
`make_marp.py` で deck.md（正）+ script.md（原稿）+ build_html.py の CSS（デザイン）から
生成する。手で Marp 版を作るとデザインとズレて二重管理になる。

- CSS は `build_html.py` の `CSS` 定数を import して使い、
  `section.slide` → `section`、`@page` と `page-break-*` を落とす。
- 原稿は script.md の `##` 見出しと deck.md の `#` 見出しを、数字・記号・括弧を落とした
  緩いキーで突き合わせる（`7. 道路網の構築 — 3 段の変換` と `7. 道路網の構築` のようなズレがある）。
- 表紙の deck.md 側見出しは作品名で script.md 側は「タイトル」なので、1 枚目は特別扱い。
