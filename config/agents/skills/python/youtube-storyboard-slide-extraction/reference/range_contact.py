#!/usr/bin/env python3
"""任意の範囲を全タイル（無加工）で並べて時系列を確認する。"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path("contact")
OUT.mkdir(exist_ok=True)

t0 = float(sys.argv[1])
t1 = float(sys.argv[2])
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 8
cw = 1920 // cols
ch = round(cw * 9 / 16)
bar = 18

import csv

rows = list(csv.DictReader(open("tiles.csv", encoding="utf-8")))
sel = [r for r in rows if t0 <= float(r["t"]) <= t1]
n = len(sel)
nrows = (n + cols - 1) // cols
sheet = Image.new("RGB", (cols * (cw + 2) + 2, nrows * (ch + bar + 2) + 2), (20, 20, 24))
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default(size=13)

for i, r in enumerate(sel):
    rr, cc = divmod(i, cols)
    x = 2 + cc * (cw + 2)
    y = 2 + rr * (ch + bar + 2)
    t = float(r["t"])
    with Image.open(f"tiles/{int(r['frame']):05d}.jpg") as tile:
        sheet.paste(tile.convert("RGB").resize((cw, ch), Image.LANCZOS), (x, y + bar))
    label = f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{int(t % 60):02d} f{r['frame']}"
    draw.rectangle([x, y, x + cw, y + bar], fill=(70, 70, 80))
    draw.text((x + 4, y + 2), label, fill=(240, 240, 240), font=font)

path = OUT / f"range_{int(t0)}_{int(t1)}.jpg"
sheet.save(path, quality=88)
print(f"{path}  tiles={n}")