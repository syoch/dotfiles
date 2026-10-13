#!/usr/bin/env python3
"""チームごとに代表タイルのコンタクトシートを作る。目視で内容を読むため。"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path("contact")
OUT.mkdir(exist_ok=True)

CELL_W, CELL_H = 400, 225
BAR = 24
COLS = 4
PAD = 4


def hms(sec: float) -> str:
    return f"{int(sec // 3600):02d}:{int(sec % 3600 // 60):02d}:{int(sec % 60):02d}"


def build(team: dict, screen_only: bool = False) -> Path:
    cells = [s for s in team["segments"] if s["screen"]] if screen_only else team["segments"]
    if not cells:
        raise SystemExit(f"#{team['no']} no segments")

    rows = (len(cells) + COLS - 1) // COLS
    W = COLS * (CELL_W + PAD) + PAD
    H = rows * (CELL_H + BAR + PAD) + PAD
    sheet = Image.new("RGB", (W, H), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=15)

    for i, seg in enumerate(cells):
        r, c = divmod(i, COLS)
        x = PAD + c * (CELL_W + PAD)
        y = PAD + r * (CELL_H + BAR + PAD)
        with Image.open(f"tiles/{seg['rep']:05d}.jpg") as tile:
            sheet.paste(tile.convert("RGB").resize((CELL_W, CELL_H), Image.LANCZOS), (x, y + BAR))
        label = f"{i + 1:02d}  {hms(seg['t0'])}  {seg['dur']:5.0f}s  L{seg['luma']:.0f}"
        draw.rectangle([x, y, x + CELL_W, y + BAR], fill=(60, 60, 68))
        draw.text((x + 5, y + 4), label, fill=(240, 240, 240), font=font)

    path = OUT / f"no{team['no']:02d}.jpg"
    sheet.save(path, quality=92)
    return path


def main() -> None:
    data = json.loads(Path("segments.json").read_text(encoding="utf-8"))
    wanted = sys.argv[1:] or [str(t["no"]) for t in data["teams"]]
    for token in wanted:
        team = next(t for t in data["teams"] if str(t["no"]) == token.lstrip("#"))
        path = build(team)
        print(f"{path}  cells={len(team['segments'])}  (#{team['no']} {team['name']})")


if __name__ == "__main__":
    main()