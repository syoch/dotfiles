---
name: update-nix-on-droid
description: Use when updating Nix-on-Droid on the phone. Two stages: (1) initial bootstrap (sshd-only ~450 MiB minimal config via adb), (2) full p30t deployment via SSH once sshd is up. Desktop builds the activation package; phone just imports and activates. Trigger keywords: nix-on-droid update, phone flake switch, droid-build, droid-serve, sshd bootstrap.
args: なし
---

# update-nix-on-droid

## いつ使うか

Nix-on-Droid (p30t) の設定を更新する。**Desktop で aarch64 向け activation package をビルド → phone で import + activate**。Phone 側での nixpkgs 評価は行わない（10-15分 → 数秒に短縮）。

## 2 つの構成

| 構成 | 内容 | closure サイズ | 用途 |
|---|---|---|---|
| `initial` | sshd のみ (port 8022) | ~450 MiB | 初回セットアップ / sshd 修復 |
| `p30t` | 完全な p30t 設定 | ~3.6 GiB | 通常運用 |

## 手順

### 初回セットアップ（sshd 未動作）

**Desktop:**
1. `make droid-build-initial` で sshd のみの activation package をビルド
2. `make droid-push-scripts` で phone 側スクリプトを配置
3. `make droid-serve-initial` で nar を /sdcard に push

**Phone:**
4. `~/update-nix-on-droid-prebuilt` で nar import + activate
5. sshd が port 8022 で起動（`/data/data/.../files/home` 配下なので root 経由で chown）

### 通常更新（sshd 動作中）

**Desktop:**
1. `make droid-build` で p30t の activation package をビルド
2. `make droid-serve` で nar を /sdcard に push（または `--http` で HTTP serve）

**Phone:**
3. `~/update-nix-on-droid-prebuilt` で nar import + activate

または desktop 側で `nix copy --to ssh://phone:8022` を使うことも可能（sshd 動作後）。

## 検証方法

- `cat ~/droid-config-name` で正しい config 名が出る (initial / p30t)
- `cat ~/droid-activation-path` で activation package の path が出る
- `~/droid-activate` がエラーなく完了
- sshd 動作確認: `ssh -p 8022 syoch@phone-ip` でログイン可能

## 落とし穴

- **評価互換性**: `programs.ssh.settings."*"` は nix-on-droid の HM integration で評価不可。`modules-hm/cui/ssh.nix` は `matchBlocks."*"` を使うこと
- **substituter 設定**: desktop でビルドする際は `--impure` と `nix-on-droid.cachix.org` の substituter 指定が必須（scripts/droid-build にハードコード済み）
- **root 必須パス**: `/data/data/com.termux.nix/files/home/` への直 push は root 必須。/sdcard/ 経由（root 不要）を使うこと
- **nar export 時の closure パス**: `nix-store --export $(nix-store -qR $ACTIVATION)` の形式で closure 全体をエクスポート。差分転送したい場合は phone 側で現状 closure を expose する仕組みが必要
- **initial 構成は runsvdir 自動起動なし**: activation script 内で `tmux new-session` で起動する。shell モジュールを import しないので shell hook は使えない
- **sshd 修復時**: initial 構成を build + push して `~/droid-activate` で再適用可能
