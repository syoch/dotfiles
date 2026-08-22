---
name: update-nix-on-droid
description: Use when updating Nix-on-Droid on the phone: extract dotfiles.tgz into ~/dotfiles and run nix-on-droid switch --flake ~/dotfiles. Trigger keywords: nix-on-droid update, phone flake switch, dotfiles.tgz extract.
args: なし
---

# update-nix-on-droid

## いつ使うか

`dotfiles.tgz` を展開して `~/dotfiles` を更新し、Nix-on-Droid の flake 切替を実行する。

## 手順

1. 電話上のホームディレクトリに `dotfiles.tgz` を配置し、スクリプトを実行する。
2. `nix-on-droid switch --flake ~/dotfiles -v` が実行され、設定が適用される。

## 検証方法

- `nix-on-droid switch` がエラーなく完了し、`~/dotfiles` の内容が更新されることを確認する。

## 落とし穴

- ネイティブ環境では実行しない（Nix-on-Droid 専用）。根ざした適用のため事前に `dotfiles.tgz` が存在している必要がある。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。