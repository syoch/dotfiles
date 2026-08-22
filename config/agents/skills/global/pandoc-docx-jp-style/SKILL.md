---
name: pandoc-docx-jp-style
description: Use when generating a styled .docx from text/markdown with pandoc on a Nix system, customizing a reference.docx styles.xml (eastAsia Japanese fonts like 游明朝, line spacing, heading sizes, centering) by editing the zip directly, then converting to PDF with LibreOffice. Trigger keywords: pandoc reference.docx, styles.xml edit, w:eastAsia 游明朝, nix shell pandoc, sofice convert docx to pdf, custom docx styles, report to word, pdftotext verify docx style.
args: <md> <out.docx>
---

# Pandoc .docx styling via custom reference.docx (Japanese eastAsia fonts)

## When to use
Use when you need to produce a formatted Word (.docx) document from plain text/markdown with specific typography — Japanese eastAsia fonts (e.g. 游明朝/u東明), line height/spacing, heading sizes, centered titles — and optionally render it to PDF. Useful for reports/meeting-minutes style documents.

## Procedure
1. **Get pandoc** (if not installed, e.g. on NixOS): `nix shell nixpkgs#pandoc -c pandoc --version`. Always prefix with `nix shell nixpkgs#pandoc -c` for each pandoc call.
2. **Dump default reference doc**: `nix shell nixpkgs#pandoc -c pandoc -o ref.docx --print-default-data-file reference.docx`.
3. **Unpack it**: `mkdir reftmp && cd reftmp && python3 -m zipfile -e ../ref.docx .`. Inspect `word/styles.xml` (style IDs like `Normal`, `BodyText`, `Heading1`, `Title`, `use**`FirstParagraph`**).
4. **Edit styles.xml with Python regex** (a .docx is a zip of XML; edit then rezip). Rebuild `w:pPr` and `w:rPr` from scratch per style to avoid invalid XML:
   - Remove existing `<w:pPr>.*?</w:pPr>` and `<w:rPr>.*?</w:rPr>`, then re-insert clean ones.
   - Spacing: `<w:spacing w:before="X" w:after="Y" w:line="240" w:lineRule="auto" />`.
   - Alignment: `<w:jc w:val="center" />`.
   - Font: `<w:rFonts w:eastAsia="游明朝" w:eastAsiaTheme="majorEastAsia" />`.
   - Size: `<w:sz w:val="N" /><w:szCs w:val="N" />` (half-points; 21=10.5pt, 40=20pt). Bold: `<w:b />`.
   - Style IDs used by pandoc: `Normal`, `BodyText`, `FirstParagraph`, `Heading1`-`Heading6`, `Title`.
5. **Repack**: rezip containing directory preserving `[Content_Types].xml` etc. into `ref-custom.docx`.
6. **Convert your source**: `... -o report.md` from your text using appropriate heading markers; then `pandoc report.md -o report.docx --reference-doc ref-custom.docx`.
7. **PDF (optional)**: `soffice --headless --convert-to pdf report.docx --outdir .`.

## Pitfalls
- Editing styles.xml naively can produce **invalid XML** (duplicate/nested tags); always strip and rebuild the whole `pPr`/`rPr` block, don't surgically swap tags.
- The default reference doc may NOT include every heading style; add `FirstParagraph`/`Heading3+` via the rebuild loop — assert each style exists: `assert m, style_id`.
- `soffice` may warn `storagebase.cxx: missing base input stream` — harmless, check output PDF pages instead (`pdfinfo …Pages`).
- Verify styles landed: unpack the output docx and grep `document.xml` for `<w:pStyle w:val="Heading1"`.
- Clean up temp dirs (`reftmp`, `reftmp2`, `verify`) after monitoring user always `verify` then later (`rm -rf verify ref.docx`).

## Verification
Extract final docx: `python3 -m zipfile -e report.docx verify &&` grep document.xml for each expected `w:pStyle` mapping; then `pdftotext -layout report.pdf | head` to confirm layout/order and that fonts did not break rendering.
