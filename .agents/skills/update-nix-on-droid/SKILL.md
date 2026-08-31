---
name: update-nix-on-droid
description: Use when updating Nix-on-Droid on the phone. Two modes: (1) fast pre-built path (desktop builds nar, phone imports + activates without evaluation), (2) legacy path (extract dotfiles.tgz and run nix-on-droid switch on device - slow, 10-15 min). Trigger keywords: nix-on-droid update, phone flake switch, dotfiles.tgz extract, droid-build, droid-serve, droid-diff.
args: なし
---

# update-nix-on-droid

## いつ使うか

Nix-on-Droid (p30t) の設定を更新する。**通常は fast path を使う**（desktop ビルド + nar transfer）。初回セットアップや fast path が動かない場合のみ legacy path にフォールバック。

## 手順

### Fast path (推奨, 1-2分)

**Desktop 側:**
1. `make droid-build` で aarch64-linux 用 activation package をビルド
2. `make droid-serve` で closure を nar に export して adb push（/sdcard/Download/ 経由, root 不要）

**Phone 側:**
3. `~/update-nix-on-droid-prebuilt` で /sdcard から ~/ へコピー → nar import → activate

Diff-only path（phone に sshd 動作時）:
- Phone: `~/droid-state-server &`
- Desktop: `PHONE=<ip> make droid-diff`

### Legacy path (フォールバック, 10-15分)

**Desktop 側:**
1. `make droid-sync-dotfiles-adb` で dotfiles.tgz を phone に push（/data/local/tmp 経由, root 必須）
2. `make droid-sync-update-adb` で update.sh を phone に push

**Phone 側:**
3. `~/update.sh` で dotfiles.tgz を展開 → `nix-on-droid switch --flake ~/dotfiles -v`

## 検証方法

- Fast path: `cat ~/droid-activation-path` で正しい activation path が出ること、`~/droid-activate` がエラーなく完了すること
- Legacy path: `nix-on-droid switch` がエラーなく完了し、`~/dotfiles` の内容が更新されること

## 落とし穴

- **初回セットアップ時**: phone の nix-on-droid ブートストラップ完了後に `make droid-push-scripts` で phone 側スクリプトを配置する必要がある
- **評価互換性**: `programs.ssh.settings."*"` は nix-on-droid の HM integration で評価不可。`modules-hm/cui/ssh.nix` は `matchBlocks."*"` を使うこと
- **substituter 設定**: desktop でビルドする際は `--impure` と `nix-on-droid.cachix.org` の substituter 指定が必須
- **root 必須パス**: `/data/data/com.termux.nix/files/home/` への直 push は root 必須。/sdcard/ 経由（root 不要）を使うこと
- **hardcoded store path**: legacy `update-nix-on-droid` には `/nix/store/923k4wjp*/bin/gzip` のような hardcoded path があり、nixpkgs 更新で壊れる可能性あり。fast path への移行推奨
- **closure サイズ**: 現在 ~3.6 GiB / 494 paths。差分のみ transfer することで大幅削減可能
