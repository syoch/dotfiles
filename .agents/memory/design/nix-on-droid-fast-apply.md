# Nix-on-Droid 2 段構成デプロイ

## 概要

Desktop で aarch64 向け activation package をビルド → phone で import + activate。Phone 側での nixpkgs 評価は行わない。初回セットアップ (sshd 未動作) と通常運用 (sshd 動作中) で別構成を使用。

## 2 つの構成

### `components/droid/initial/` (sshd のみ)
- closure: 127 paths / ~450 MiB
- 用途: 初回セットアップ / sshd 修復
- features:
  - sshd (port 8022)
  - runit サービスフレームワーク（runsvdir は activation script で起動）
  - coreutils, bashInteractive のみ
  - Home Manager なし
  - shell モジュールなし

### `components/droid/p30t/` (完全構成)
- closure: 494 paths / ~3.6 GiB
- 用途: 通常運用
- features: full Home Manager (zsh, nvim, tmux, git, gpg-agent), shell, services, syncthing, portal

## flake.nix 出力

```nix
nixOnDroidConfigurations.initial  # sshd only
nixOnDroidConfigurations.default  # full p30t (旧 default)
```

## ワークフロー

### 初回セットアップ
```
Desktop: make droid-build-initial    # ~5分
Desktop: make droid-push-scripts     # phone 側スクリプト
Desktop: make droid-serve-initial    # nar を /sdcard に push
Phone:   ~/update-nix-on-droid-prebuilt
         → sshd 起動
```

### 通常更新 (sshd 動作中)
```
Desktop: make droid-build            # ~5分 (初回) / 1分 (更新)
Desktop: make droid-serve            # nar を /sdcard に push
Phone:   ~/update-nix-on-droid-prebuilt
```

### sshd 修復
```
Desktop: make droid-build-initial && make droid-serve-initial
Phone:   ~/update-nix-on-droid-prebuilt
```

## スクリプト

| ファイル | 役割 |
|---|---|
| `scripts/droid-build` | Desktop: aarch64 ビルド（config 選択可） |
| `scripts/droid-serve` | Desktop: nar export + /sdcard push / HTTP serve |
| `scripts/droid-activate` | Phone: nar import + activate |
| `scripts/update-nix-on-droid-prebuilt` | Phone: /sdcard → ~/ コピー + activate |

## Makefile ターゲット

- `make droid-build-initial` — sshd のみビルド
- `make droid-build` — p30t 完全ビルド
- `make droid-build-initial-serve` / `droid-build-serve` — ビルド + HTTP
- `make droid-serve-initial` / `droid-serve` — nar を /sdcard に push
- `make droid-push-scripts` — phone 側スクリプトを /sdcard 経由で配置

## ビルドコマンド（直接実行）

```bash
nix build --system aarch64-linux --impure \
  --option substituters "https://nix-on-droid.cachix.org https://cache.nixos.org" \
  --option trusted-public-keys "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
  .#nixOnDroidConfigurations.{initial,default}.activationPackage
```

## 注意事項

- `--impure` 必須: nix-on-droid が impure 機能を使うため
- `nix-on-droid.cachix.org` 必須: proot バイナリ (aarch64-android 専用) の取得元
- 旧 `droid-sync-dotfiles-adb` (root 必須) と旧 `nix-on-droid switch` (phone 評価) は廃止
- `programs.ssh.settings."*"` は nix-on-droid の HM integration で評価不可 → `matchBlocks."*"` を使う
