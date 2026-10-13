#!/usr/bin/env python3
"""タイル列から画面変化を検出してセグメント化する。"""
import sys

import numpy as np

data = np.load("tiles.npz")
dh = data["dhash"].astype(np.int16)
small = data["small"].astype(np.float32)
luma = data["luma"]
times = data["times"]
n = len(dh)

ham = np.array([(dh[i] != dh[i - 1]).sum() for i in range(1, n)])
mad = np.array([np.abs(small[i] - small[i - 1]).mean() for i in range(1, n)])

print(f"frames: {n}  t: {times[0]:.1f}..{times[-1]:.1f}")
print("hamming  percentiles:", {p: int(np.percentile(ham, p)) for p in (5, 25, 50, 75, 90, 95, 99)})
print("absdiff  percentiles:", {p: round(float(np.percentile(mad, p)), 2) for p in (5, 25, 50, 75, 90, 95, 99)})

hist = np.bincount(np.clip(ham, 0, 40), minlength=41)
print("hamming histogram (0..40):")
for i in range(41):
    if hist[i]:
        print(f"  {i:3d} {hist[i]:5d} {'#' * (hist[i] * 60 // max(hist.max(), 1))}")

hm = int(sys.argv[1]) if len(sys.argv) > 1 else 8
md = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0
change = (ham >= hm) | (mad >= md)
print(f"\nthresholds hamming>={hm} absdiff>={md} -> changes: {change.sum()} of {n - 1}")