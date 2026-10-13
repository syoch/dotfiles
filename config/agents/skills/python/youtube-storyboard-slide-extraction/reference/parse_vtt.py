#!/usr/bin/env python3
"""逐語 VTT を解析して発表区間のアンカーを抽出する。

判別ルールは notes/presentation-archive-segment-offset.md に従う。
- 発表開始: 司会が「◯番の発表」を読み上げる
- 発表終了: 「（◯◯校）の発表を終わりたい」
- 質疑開始は qa_start の自動判定に依存しない
"""
import json
import re
import sys
from pathlib import Path

VTT = Path(sys.argv[1])
CUE = re.compile(
    r"(\d{2}):(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[.,](\d{3})"
)


def to_sec(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def parse_vtt(path: Path):
    cues = []
    block = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            if block:
                cues.append(make_cue(block))
                block = []
            continue
        block.append(line)
    if block:
        cues.append(make_cue(block))
    return cues


def make_cue(block):
    for i, line in enumerate(block):
        m = CUE.search(line)
        if m:
            start = to_sec(*m.group(1, 2, 3, 4))
            end = to_sec(*m.group(5, 6, 7, 8))
            text = " ".join(x for x in block[i + 1:] if not x.isdigit())
            return {"start": start, "end": end, "text": text}
    return None


PATTERNS = [
    ("start_no", re.compile(r"(\d{1,2})\s*番(目)?(の|の)?\s*発表")),
    ("end_school", re.compile(r"発表を終わりたい")),
    ("qa_start", re.compile(r"(質疑|質問|質問い|time)\s*(を|は)?\s*(始|はじ)")),
    ("mc_talk", re.compile(r"(司会|お Vish| herewith|一般是)?")),
]


def main():
    cues = [c for c in parse_vtt(VTT) if c]
    print(f"cues: {len(cues)}  span: {cues[0]['start']:.1f} .. {cues[-1]['end']:.1f}")

    hits = []
    for c in cues:
        for name, pat in PATTERNS:
            if name == "mc_talk":
                continue
            if pat.search(c["text"]):
                hits.append({"t": c["start"], "kind": name, "text": c["text"]})
                break

    hits.sort(key=lambda h: h["t"])
    for h in hits:
        print(f"{int(h['t']//60):02d}:{int(h['t']%60):02d}  {h['kind']:12s}  {h['text'][:90]}")

    Path("anchors.json").write_text(
        json.dumps(hits, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    print(f"\nanchors -> anchors.json ({len(hits)})")


if __name__ == "__main__":
    main()