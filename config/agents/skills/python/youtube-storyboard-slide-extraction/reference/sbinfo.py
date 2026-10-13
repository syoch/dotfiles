#!/usr/bin/env python3
"""YouTube storyboard のジオメトリ (rows/cols/interval) を JSON から取り出す。"""
import json
import subprocess
import sys

VIDEO = sys.argv[1] if len(sys.argv) > 1 else "https://www.youtube.com/watch?v=WwhRZeRsDgA"

out = subprocess.run(
    ["yt-dlp", "-J", "--no-warnings", "--skip-download", VIDEO],
    capture_output=True, text=True, check=True,
).stdout
meta = json.loads(out)

print(f"title   : {meta.get('title')}")
print(f"duration: {meta.get('duration')}")
print(f"fps     : {meta.get('fps')}")

for fmt in meta.get("formats", []):
    fid = fmt.get("format_id") or ""
    if "storyboard" not in fid and not fid.startswith("sb"):
        continue
    sb = fmt.get("storyboards") or [{}]
    for entry in sb:
        print("---")
        print(f"  format_id : {fmt['format_id']}")
        print(f"  rows      : {entry.get('rows')}")
        print(f"  columns   : {entry.get('columns')}")
        print(f"  interval  : {entry.get('interval')}")
        print(f"  total     : {entry.get('total_frames')}")
        print(f"  width     : {fmt.get('width')} height: {fmt.get('height')}")
        print(f"  fragments : {len(entry.get('fragments', []))}")
        frags = entry.get("fragments", [])
        if frags:
            print(f"  frag[0]   : {json.dumps(frags[0], ensure_ascii=False)[:300]}")
            print(f"  frag[-1]  : {json.dumps(frags[-1], ensure_ascii=False)[:300]}")