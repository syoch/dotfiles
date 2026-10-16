---
name: nix-shell-pdf-ocr
description: Use when extracting text or OCR from a PDF on a Nix system where poppler-utils/tesseract are not pre-installed; trigger keywords: nix-shell, pdftotext, pdftoppm, tesseract, jpn+eng, OCR PDF, NixOS no binaries.
---

# Extracting text or OCR from PDFs on Nix systems

## When to use
- User asks to read/extract/OCR a PDF (especially Japanese PDFs) on a NixOS / nix-shell environment.
- Standard tools (`pdftotext`, `pdfinfo`, `mutool`, `tesseract`) are not in `$PATH`.
- A PDF produced by Skia/PDF (Chrome print, Google Docs export) yields empty `pdftotext` output and needs OCR.

## Procedure

1. **Check available tools first**:
   ```
   which pdftotext pdfinfo mutool tesseract
   ```
   If missing, the host is likely NixOS or a pure nix-shell.

2. **Use `nix-shell` with explicit nixpkgs channel** to avoid `default.nix` lookup failures:
   ```
   nix-shell -I nixpkgs=channel:nixos-25.05 -p poppler-utils --run "..."
   ```
   Do NOT use `nix-build -A poppler_utils` inside a project subdirectory — it looks for `./default.nix` and errors out.

3. **Try text extraction first** (fast, small download):
   ```
   pdftotext -layout file.pdf out.txt   # preserves columns
   pdftotext -raw file.pdf out.txt      # literal order, no layout
   pdfinfo file.pdf                     # metadata + page count
   ```
   If `out.txt` is empty/garbled, the PDF is image-only — proceed to OCR.

4. **OCR pipeline** (heavier: ~470 MiB download, ~1 GiB unpacked for tesseract jpn+eng):
   ```
   nix-shell -I nixpkgs=channel:nixos-25.05 -p poppler-utils tesseract --run '
     pdftoppm -r 200 file.pdf /tmp/p -png
     tesseract /tmp/p-1.png /tmp/ocr -l jpn+eng --psm 6
   '
   ```
   - `--psm 6` (uniform block of text) usually beats default for mixed Japanese/English slides.
   - 200 dpi is a good balance; 400 dpi doubles time without major gain.
   - For Japanese-only docs, `-l jpn --psm 4` works better.

5. **For visual review**, convert to a single PNG and read it with the `read` tool:
   ```
   pdftoppm -r 150 file.pdf /tmp/p -png
   # then read /tmp/p-1.png directly — image attachments are supported.
   ```

## Detect image-only PDFs (Skia/PDF)

`pdfinfo` can tell you if the PDF is image-only:
```
$ pdfinfo file.pdf
Producer:        Skia/PDF m124     ← image-based PDF, OCR needed
Pages:           1
Page size:       2560 x 1915 pts
```

If `Producer` is `Skia/PDF` (Chrome print, Google Docs export), `pdftotext` will be empty — go straight to `pdftoppm` + Read tool or tesseract.

## Triage by PDF type

| Type | Detection | Action |
|------|-----------|--------|
| Text-embedded | `pdftotext` returns text | `pdftotext` is enough |
| Image-only (Skia/PDF) | `pdftotext` empty, `Producer: Skia/PDF` | `pdftoppm` + Read tool (or tesseract) |

## Verification
- `wc -l` the output file; `pdftotext` typically yields hundreds of lines, OCR fewer.
- `pdfinfo` to confirm page count matches expectations.
- Always grep out noise: `2>&1 | grep -v "nix-store\|copying path\|nixos.org\|tmux"`.

## Pitfalls
- First nix-shell run downloads hundreds of MiB and may take minutes — set `timeout: 300000`.
- `nix-build` from a project dir fails with `default.nix does not exist` — stick to `nix-shell -p`.
- Image-only PDFs (Skia/PDF m124 etc.) return empty text — don't loop on `pdftotext` flags, switch to OCR.
- Tesseract may produce 0-byte output silently if the language data isn't fully fetched; check `ls -la` on the output file.
- Don't rely on `nix-env -qa` for discovery — it's slow and often returns nothing useful inside a shell session.
- **`nix-shell` inside tmux**: `nix-shell --run` may not execute inside a tmux session. Workaround: run `nix-shell -p poppler-utils --run "pdftoppm -r 200 input.pdf /tmp/p -png"` and then verify with `ls -la /tmp/p*` before reading with the Read tool.
