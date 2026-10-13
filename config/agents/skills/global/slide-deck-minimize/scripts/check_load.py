#!/usr/bin/env python3
"""発表スライドの文字数と要素数を数える。

Naegle "Ten simple rules for effective presentation slides" (PLoS Comput Biol 2021)
の Rule 2（1 スライド 1 分）と Rule 7（要素は 6 個まで）に照らして判定する。

日本語は英語の 2.5 倍文字数（東工大 言語心理学 2024）なので、
英語圏の「5 行 5 語」をそのまま使わず文字数で判定する。

使い方:
    python3 check_load.py deck.html
    python3 check_load.py deck.html --max-chars 80 --max-elements 6
    python3 check_load.py deck.html --json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# 認知的に独立した単位として数える対象と、その重み
ELEMENT_RULES: list[tuple[str, str, int]] = [
    ("見出し", r"<h[1-6][^>]*>", 1),
    ("表", r"<table", 3),
    ("箇条書き", r"<li", 1),
    ("カード", r'class="card"', 1),
    ("図", r"<img", 2),
    ("ステップ", r'class="step"', 1),
    ("バッジ", r'class="ic"', 1),
    ("KPI", r'class="kpi"', 2),
    ("段落", r"<p[ >]", 1),
]

# 数えない（装飾とメタ情報）
IGNORE = re.compile(r'class="(pageno|foot|note)"')


def split_slides(html: str) -> list[str]:
    return re.findall(r'<section class="slide[^"]*">(.*?)</section>', html, re.S)


def count_text(slide: str) -> int:
    body = IGNORE.sub("", slide)
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = re.sub(r"<[^>]+>", " ", body)
    return len(re.sub(r"\s", "", body))


def count_elements(slide: str) -> tuple[int, dict[str, int]]:
    body = IGNORE.sub("", slide)
    detail: dict[str, int] = {}
    total = 0
    for name, pattern, weight in ELEMENT_RULES:
        n = len(re.findall(pattern, body))
        if n == 0:
            continue
        detail[name] = n
        total += n * weight
    return total, detail


def heading(slide: str) -> str:
    m = re.search(r"<h[12][^>]*>(.*?)</h[12]>", slide, re.S)
    if m is None:
        return "(図のみ)"
    return re.sub(r"<[^>]+>", "", m.group(1)).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("html", type=Path)
    ap.add_argument("--max-chars", type=int, default=80)
    ap.add_argument("--max-elements", type=int, default=6)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if not args.html.exists():
        print(f"not found: {args.html}", file=sys.stderr)
        return 2

    slides = split_slides(args.html.read_text(encoding="utf-8"))
    if not slides:
        print("section.slide が見つからない", file=sys.stderr)
        return 2

    rows = []
    for i, s in enumerate(slides, start=1):
        chars = count_text(s)
        elems, detail = count_elements(s)
        rows.append(
            {
                "index": i,
                "heading": heading(s),
                "chars": chars,
                "elements": elems,
                "detail": detail,
                "over_chars": chars > args.max_chars,
                "over_elements": elems > args.max_elements,
            }
        )

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0

    print(f"{'#':>3} {'要素':>4} {'文字':>5}  {'判定':6}  見出し")
    print("-" * 72)
    for r in rows:
        flags = []
        if r["over_chars"]:
            flags.append("文字")
        if r["over_elements"]:
            flags.append("要素")
        verdict = " ".join(flags) if flags else "OK"
        print(f"{r['index']:3} {r['elements']:4} {r['chars']:5}  {verdict:6}  {r['heading'][:34]}")

    avg_chars = sum(r["chars"] for r in rows) / len(rows)
    avg_elems = sum(r["elements"] for r in rows) / len(rows)
    bad = [r for r in rows if r["over_chars"] or r["over_elements"]]
    print("-" * 72)
    print(f"{len(rows)} 枚 / 平均 {avg_elems:.1f} 要素・{avg_chars:.0f} 字")
    print(f"閾値超過 {len(bad)} 枚（文字 > {args.max_chars} / 要素 > {args.max_elements}）")
    for r in bad:
        d = ", ".join(f"{k}{v}" for k, v in sorted(r["detail"].items(), key=lambda x: -x[1]))
        print(f"  {r['index']:2} {r['chars']:4}字 {r['elements']:2}要素 [{d}] {r['heading'][:24]}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())