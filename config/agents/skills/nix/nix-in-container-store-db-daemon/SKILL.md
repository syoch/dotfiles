---
name: nix-in-container-store-db-daemon
description: Use when a container needs to run nix commands against the host's already-realised store, or when nix inside a container reports the store as empty, downloads everything, or errors with `cannot determine user's home directory` / `experimental Nix feature 'nix-command' is disabled`. Trigger keywords: nix in container, nix develop in docker, nix store empty, /nix/var/nix/db, NIX_REMOTE=daemon, daemon-socket, bind-ro /nix/store, nixos-containers, nix cannot determine user's home directory, nix-command disabled, passwd entry uid.
args: <コンテナを起動するコマンドの例>
---

Use when a container needs to run nix commands and reach the host's already-realised store,
or when nix inside a container reports the store as empty or tries to download everything.

## 症状と原因

`nix` をコンテナに入れて `/nix/store` を bind しただけでは**動かない**。

- `error: experimental Nix feature 'nix-command' is disabled`
コンテナに `/etc/nix/nix.conf` が無い。
  `NIX_CONFIG` で `experimental-features` を渡す。
- 全 store path を「無効」と判定してネットワークから取り直しに行く
  **「何が在るか」は DB にあり、store 自体には無い。**
- `error: cannot determine user's home directory`
  `--user $(id -u)` では passwd エントリが作られない。
  `XDG_*` を明示する。

`git worktree` 型の「絶対パスを見られないと全部消えたと誤判定する」と同じ構造。

## 公式が使っている 3 つ

nixpkgs `nixos/modules/virtualisation/nixos-containers.nix` の
`systemd-nspawn` 起動オプションが正:

```
--bind-ro=/nix/store
--bind-ro=/nix/var/nix/db
--bind-ro=/nix/var/nix/daemon-socket
--bind=/nix/var/nix/profiles/per-container/$INSTANCE:/nix/var/nix/profiles
--bind=/nix/var/nix/gcroots/per-container/$INSTANCE:/nix/var/nix/gcroots
```

| bind | 役割 |
|---|---|
| `/nix/store` ro | バイナリが実体で解決される |
| `/nix/var/nix/db` ro | **「何が在るか」の台帳。これが無いと store を空とみなす** |
| `/nix/var/nix/daemon-socket` rw | 書き込みをホストの daemon に委譲する |
| `profiles` / `gcroots` rw | コンテナが書く先。per-container / per-run のディレクトリを用意する |

## daemon は knowledge を解かない

`NIX_REMOTE=daemon` は**書き込み権限**を委譲する（コンテナが store を書けないようにする）。
DB は**別物**で、コンテナに daemon を立てても DB は空のまま。

```
-e NIX_REMOTE=daemon
```

公式は `--bind-ro=/nix/var/nix/daemon-socket` として read-only で渡す。
ソケットは書き込み可だが、daemon 側が権限を適用する。

## 手順

```bash
# 1. 移植しても安全な設定キーを抽出する（絶対パスを含むキーは除外）
NIX_CONF="$(grep -vE '^\s*(#|$)' /etc/nix/nix.conf \
  | grep -E '^\s*(experimental-features|substituters|trusted-public-keys|trusted-substituters|require-sigs|extra-platforms|auto-optimise-store)\s*=' \
  | sed 's/^[[:space:]]*//')"

# 2. per-run の profiles / gcroots を作る
mkdir -p "$STATE/profiles" "$STATE/gcroots"

# 3. 起動する
docker run --rm --user "$(id -u):$(id -g)" \
  -v /nix/store:/nix/store:ro \
  -v /nix/var/nix/db:/nix/var/nix/db:ro \
  -v /nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket \
  -v "$STATE/profiles":/nix/var/nix/profiles \
  -v "$STATE/gcroots":/nix/var/nix/gcroots \
  -e NIX_REMOTE=daemon \
  -e NIX_CONFIG="$NIX_CONF" \
  -e HOME=/runner \
  -e XDG_CACHE_HOME=/runner/cache \
  -e XDG_DATA_HOME=/runner/data \
  -e XDG_CONFIG_HOME=/runner/cfg \
  --tmpfs /runner:mode=1777 \
  "$IMAGE" -c 'nix develop --command bash -c "node -v; pnpm -v"'
```

**nix バイナリはイメージに入れない。**
`/nix/store` に `nix-<version>` があるので PATH に足すだけで動く。
apt の `nix-bin` は別バージョンなので版数がずれる。

## 検証

| 確認 | 合格条件 |
|---|---|
| `nix --version` | 起動する |
| `nix store info` | `Store URL: daemon` / `Trusted: 1` |
| `nix path-info <既知の store path>` | 成功する（= valid 判定されている） |
| `nix develop --command <cmd>` | 想定どおりのバージョンが出る |
| 実行前後で `ls /nix/store \| wc -l` | **差分ゼロ** |

store の件数比較が決め手。nix は store path の mtime を epoch に固定するので
`find -newermt` では検出できない。

## 落とし穴

- **`XDG_*` を省略すると `cannot determine user's home directory` で止まる。**
  `$HOME` を存在しないパスにして nix に作らせる回避も可能だが、
 挙動に依存するので場所を明示する方を選ぶ。
- **agent が任意パッケージを引けるようになる。**
実現はホスト daemon がホスト store で行う。
  権限昇格ではないがディスクを消費する。
  記録に残す价值があるなら実行前後で store 件数を比べる。
- **per-user の gcroot を汚さない。**
  コンテナが触るのは `profiles` / `gcroots` の bind 先だけ。
