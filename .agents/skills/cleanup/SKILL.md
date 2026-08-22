---
name: cleanup
description: Use when cleaning up the Nix store: remove dangling /nix/var/nix/gcroots/auto links, run nix store gc and nix-collect-garbage -d and nix store optimise. Trigger keywords: nix gc, nix-collect-garbage, cleanup nix store, gcroots auto, store optimise.
args: なし
---

# cleanup

## いつ使うか

壊れた `/nix/var/nix/gcroots/auto` リンクを削除し、`nix store gc` / `nix-collect-garbage -d` / `nix store optimise` を実行する。

## 手順

1. リポジトリルート (`~/dotfiles`) から `scripts/cleanup` を実行する（PATH が通っていれば `cleanup` のみ）。
2. 引数は不要。

## 検証方法

- 出力に保存された gc root の一覧と gc/optimise の結果が表示され、壊れたリンクが削除されることを確認する。

## 落とし穴

- `sudo rm` を含むため、実行前に壊れたリンクの実体が存在しないことを確認すること。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。