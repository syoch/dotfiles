#!/usr/bin/env python3
"""画面変化からセグメント化し、21 チームに割り当てる。

チーム開始時刻は逐語の司会アンカーで確定済み (2025_jiyu_p1)。
"""
import json
import re

import numpy as np

FPS = 0.10006393861892583
ABS_THRESH = 8.0
HAM_THRESH = 18
HOLD_MIN = 1  # 保持フレーム下限
SCREEN_LUMA = 160.0  # 投影画面は luma>160、会場カメラ映像は <160

TEAMS = [
    (1, "れしぷろえんじん！", "弓削商船", "00:06:51"),
    (2, "Mr.PET", "熊本(八代)", "00:19:37"),
    (3, "Guitarist", "福井", "00:32:45"),
    (4, "Agri-Hacks", "香川(高松)", "00:47:11"),
    (5, "はなうた日和", "豊田", "01:07:38"),
    (6, "OrcheStra", "豊田", "01:20:13"),
    (7, "FullFreeFresh", "都城", "01:33:22"),
    (8, "SORAMIMI", "広島商船", "01:46:48"),
    (9, "かいたす", "神山", "02:56:00"),
    (10, "きりかた先生", "沖縄", "03:08:29"),
    (11, "よせぎゅっと", "舞鶴", "03:24:15"),
    (12, "からくる", "香川(詫間)", "03:35:46"),
    (13, "YuMe.", "茨城", "03:55:34"),
    (14, "Harmony Analyzer", "宇部", "04:08:00"),
    (15, "愛島show", "阿南", "04:20:52"),
    (16, "Next Bro", "明石", "04:33:26"),
    (17, "CPR BEAT", "熊本", "04:57:33"),
    (18, "HAKUNE", "大島商船", "05:10:28"),
    (19, "BIRDLOCK", "鳥羽商船", "05:23:38"),
    (20, "HAKOSOK", "松江", "05:37:50"),
    (21, "あみナビ", "沖縄", "05:49:42"),
]


def hms(sec: float) -> str:
    return f"{int(sec // 3600):02d}:{int(sec % 3600 // 60):02d}:{int(sec % 60):02d}"


def parse_hms(text: str) -> float:
    h, m, s = (int(x) for x in text.split(":"))
    return h * 3600 + m * 60 + s


def main() -> None:
    data = np.load("tiles.npz")
    dh = data["dhash"].astype(np.int16)
    small = data["small"].astype(np.float32)
    luma = data["luma"]
    times = data["times"].astype(np.float64)
    n = len(dh)

    ham = np.zeros(n, dtype=np.int16)
    mad = np.zeros(n, dtype=np.float32)
    for i in range(1, n):
        ham[i] = int((dh[i] != dh[i - 1]).sum())
        mad[i] = float(np.abs(small[i] - small[i - 1]).mean())
    change = np.zeros(n, dtype=bool)
    change[1:] = (mad[1:] >= ABS_THRESH) | (ham[1:] >= HAM_THRESH)

    # セグメント化
    segs = []
    start = 0
    for i in range(1, n):
        if change[i]:
            segs.append({"f0": start, "f1": i - 1})
            start = i
    segs.append({"f0": start, "f1": n - 1})
    for seg in segs:
        seg["t0"] = float(times[seg["f0"]])
        seg["t1"] = float(times[seg["f1"]])
        seg["dur"] = seg["t1"] - seg["t0"] + 9.994
        seg["luma"] = round(float(luma[seg["f0"] : seg["f1"] + 1].mean()), 1)
        seg["screen"] = bool(seg["luma"] >= SCREEN_LUMA)
    print(f"segments: {len(segs)}  changes: {int(change.sum())}")

    starts = [parse_hms(t[3]) for t in TEAMS]
    out = []
    for idx, (no, name, school, start_txt) in enumerate(TEAMS):
        t_start = starts[idx]
        t_next = starts[idx + 1] if idx + 1 < len(starts) else times[-1] + 10
        pres = [s for s in segs if s["f0"] * 9.99364 >= t_start and s["t0"] < t_start + 480]
        slot = [s for s in segs if s["t0"] >= t_start and s["t0"] < t_next]
        screen_pres = [s for s in pres if s["screen"]]
        rec = {
            "no": no,
            "name": name,
            "school": school,
            "start": start_txt,
            "t_start": t_start,
            "t_next": t_next,
            "slot_sec": round(t_next - t_start),
            "seg_pres": len(pres),
            "slide_pres": len(screen_pres),
            "slot_seg": len(slot),
            "frames_pres": sum(1 for f in range(n) if t_start <= times[f] < t_start + 480),
            "segments": [
                {
                    "t0": round(s["t0"], 1),
                    "dur": round(s["dur"], 1),
                    "rep": s["f0"],
                    "luma": s["luma"],
                    "screen": s["screen"],
                }
                for s in pres
            ],
        }
        out.append(rec)
        print(
            f"#{no:2d} {name:18s} start={start_txt} slot={rec['slot_sec']:5d}s "
            f"pres_seg={len(pres):3d} slides={len(screen_pres):3d} slot_seg={len(slot):3d}"
        )

    with open("segments.json", "w", encoding="utf-8") as fh:
        json.dump({"segments": segs, "teams": out}, fh, ensure_ascii=False, indent=1)
    print("\n-> segments.json")


if __name__ == "__main__":
    main()