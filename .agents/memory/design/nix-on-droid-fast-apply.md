# Nix-on-Droid高速適用ワークフロー

## 概要

Phone (aarch64) での `nix-on-droid switch` による nixpkgs 評価が遅い（10-15分初回、3+分更新）問題を、Desktop (x86_64) で事前ビルド + nar transfer で解決する。

## 構成

```
Desktop (x86_64)                         Phone (aarch64)
─────────────────                        ───────────────
1. nix build --system aarch64-linux      3. wget or /sdcard からコピー
   .#nixOnDroidConfigurations             4. nix-store --import < closure.nar
   .default.activationPackage             5. /nix/store/.../activate
2. nix-store --export → closure.nar
```

## 必要なもの

### Desktop
- `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` （既存）
- `extra-platforms = aarch64-linux` in nix.conf （既存）
- `nix-on-droid.cachix.org` substituter + public key （スクリプトにハードコード）
- `--impure` flag （nix-on-droid のモジュールが impure 機能を使うため）

### Phone
- Termux + nix-on-droid （既存）
- sshd on port 8022 （既存）
- /sdcard/Download への書き込み権限 （標準でアクセス可能）

## スクリプト

| ファイル | 役割 | 実行場所 |
|---|---|---|
| `scripts/droid-build` | デスクトップでビルド + オプションでHTTP serve | Desktop |
| `scripts/droid-serve` | closure をnarにexport + adb push to /sdcard or HTTP serve | Desktop |
| `scripts/droid-diff` | phone の現状closureと比較し差分のみtransfer | Desktop |
| `scripts/droid-activate` | phone で nar import + activate 実行 | Phone |
| `scripts/droid-state-server` | phone の現状closureを HTTP で公開（diff用） | Phone |
| `scripts/update-nix-on-droid-prebuilt` | /sdcard からファイルを ~/ にコピーして activate | Phone |

## Makefile ターゲット

- `make droid-build` — ビルドのみ
- `make droid-build-serve` — ビルド + HTTP serve
- `make droid-serve` — ビルド + nar export + /sdcard push
- `make droid-diff` — 差分のみ transfer
- `make droid-push-scripts` — phone 側スクリプトを /sdcard 経由で ~/ にコピー

## ワークフロー

### 初回セットアップ（sshd 未動作）
1. Phone: nix-on-droid ブートストラップ（既存）
2. Desktop: `make droid-push-scripts` （phone にスクリプト配置）
3. Desktop: `make droid-serve` （nar を /sdcard に push）
4. Phone: `~/update-nix-on-droid-prebuilt` （nar import + activate）

### 通常更新
1. Desktop: `make droid-serve`
2. Phone: `~/update-nix-on-droid-prebuilt`

または差分のみ:
1. Phone: `~/droid-state-server &` （port 8766）
2. Desktop: `PHONE=<phone-ip> make droid-diff`

## 注意事項

### nixpkgs 評価互換性
`modules-hm/cui/ssh.nix` で `programs.ssh.settings."*"` を使うと nix-on-droid の HM integration で評価エラーになる（`home-manager.config.programs.ssh.settings' does not exist`）。`matchBlocks."*"` を使うこと。

### 必要なフラグ
```bash
nix build --system aarch64-linux --impure \
  --option substituters "https://nix-on-droid.cachix.org https://cache.nixos.org" \
  --option trusted-public-keys "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
  .#nixOnDroidConfigurations.default.activationPackage
```

### closure サイズ
現在の p30t 構成で 494 paths / 3.6 GiB。nar export すると更に大きくなる可能性あり。差分のみ transfer することで大幅削減可能。

### 初回 activation 後の generation 管理
- `nix-on-droid generations` で世代一覧
- `nix-on-droid rollback` で前の世代に戻る
- 不要な generation は `nix-collect-garbage -d` で削除

## 旧ワークフロー（参考）

旧: `nix-on-droid switch --flake ~/dotfiles -v`
- phone 上で nixpkgs 評価 → 10-15分
- ローカルビルド（cache.nixos.org ヒット時を除く）
- 遅い

新: desktop ビルド + nar import
- desktop で評価+ビルド → 5分（初回）/ 1分（更新）
- phone は nar import + activate → 数秒
- 大幅高速化
