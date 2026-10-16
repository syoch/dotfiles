---
name: batt
description: Use when checking laptop battery status: display BAT0 state (Discharging/Charging) and remaining percentage via /sys/class/power_supply/BAT0. Trigger keywords: battery, batt, power status, BAT0, remaining percent.
---

# batt

## いつ使うか

BAT0 のバッテリー状態と残量 % を `/sys/class/power_supply/BAT0` から読み取って表示する。

## 手順

1. リポジトリルート (`~/dotfiles`) から `scripts/batt` を実行する（PATH が通っていれば `batt` のみ）。
2. 引数は不要。

## 検証方法

- `scripts/batt` が BAT0 の状態（Discharging/Charging 等）と残量 % を出力することを確認する。

## 落とし穴

- 実行には実行権限が必要（`chmod +x scripts/batt`）。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。