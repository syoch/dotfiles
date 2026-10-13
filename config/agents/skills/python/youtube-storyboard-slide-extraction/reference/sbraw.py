#!/usr/bin/env python3
"""player response の storyboard spec をそのままダンプする。"""
import json
import subprocess
import sys

VIDEO = sys.argv[1] if len(sys.argv) > 1 else "https://www.youtube.com/watch?v=WwhRZeRsDgA"

out = subprocess.run(
    ["yt-dlp", "-J", "--no-warnings", "--skip-download", VIDEO],
    capture_output=True, text=True, check=True,
).stdout
meta = json.loads(out)

sb = meta.get("storyboards")
print("meta['storyboards'] =", json.dumps(sb, ensure_ascii=False)[:2000])

for key in sorted(meta):
    if "story" in key.lower() or "sb" == key.lower():
        print(f"KEY {key} = {json.dumps(meta[key], ensure_ascii=False)[:2000]}")

# 各 sb format の生 dict を全部出して spec 相当を探す
for fmt in meta.get("formats", []):
    if (fmt.get("format_id") or "").startswith("sb"):
        print("=" * 60)
        print(json.dumps(fmt, ensure_ascii=False, indent=1)[:2000])