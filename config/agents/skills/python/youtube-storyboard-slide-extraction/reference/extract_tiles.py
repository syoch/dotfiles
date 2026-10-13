#!/usr/bin/env python3
"""sb0 storyboard sheet (960x540, 3x3) を 320x180 タイルに分割して時刻を付与する。

ジオメトリは player response より
  rows=3 columns=3 tile=320x180 fps=0.10006393861892583 total_frames=2191
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SHEETS = Path(sys.argv[1] if len(sys.argv) > 1 else "sheets")
TILES = Path("tiles")
FPS = 0.10006393861892583
ROWS, COLS = 3, 3
TOTAL_FRAMES = 2191

TILES.mkdir(exist_ok=True)


def dhash(img: Image.Image, size: int = 8) -> np.ndarray:
    g = img.convert("L").resize((size + 1, size), Image.LANCZOS)
    px = np.asarray(g, dtype=np.int16).reshape(size, size + 1)
    return (px[:, :-1] > px[:, 1:]).reshape(-1).astype(np.uint8)


def main() -> None:
    sheets = sorted(p for p in SHEETS.glob("*.jpg") if p.stem.isdigit())
    print(f"sheets: {len(sheets)}")

    hashes: list[np.ndarray] = []
    smalls: list[np.ndarray] = []
    lumas: list[float] = []
    rows_out: list[dict] = []

    for frame in range(TOTAL_FRAMES):
        sheet_idx, pos = divmod(frame, ROWS * COLS)
        r, c = divmod(pos, COLS)
        path = SHEETS / f"{sheet_idx:05d}.jpg"
        with Image.open(path) as sheet:
            tw = sheet.width // COLS
            th = sheet.height // ROWS
            box = (c * tw, r * th, (c + 1) * tw, (r + 1) * th)
            tile = sheet.crop(box)
            hashes.append(dhash(tile))
            arr = np.asarray(tile.convert("L").resize((32, 18), Image.LANCZOS), dtype=np.uint8)
            smalls.append(arr.reshape(-1))
            lumas.append(float(arr.mean()))
            tile.save(TILES / f"{frame:05d}.jpg", quality=88)
        rows_out.append(
            {
                "frame": frame,
                "t": round(frame / FPS, 3),
                "sheet": sheet_idx,
                "pos": pos,
                "row": r,
                "col": c,
                "luma": round(lumas[-1], 2),
            }
        )
        if frame % 300 == 0:
            print(f"  frame {frame}/{TOTAL_FRAMES}")

    with open("tiles.csv", "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows_out[0]))
        writer.writeheader()
        writer.writerows(rows_out)

    np.savez_compressed(
        "tiles.npz",
        dhash=np.stack(hashes),
        small=np.stack(smalls),
        luma=np.asarray(lumas, dtype=np.float32),
        times=np.asarray([r["t"] for r in rows_out], dtype=np.float32),
    )
    print(f"tiles -> {len(rows_out)}  luma mean={np.mean(lumas):.1f}")


if __name__ == "__main__":
    main()