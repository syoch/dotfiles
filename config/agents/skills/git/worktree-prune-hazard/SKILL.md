---
name: worktree-prune-hazard
description: Use when running git inside a container/VM/sandbox that mounts a host repository, or when `git worktree prune` unexpectedly removes every registration in .git/worktrees. Trigger keywords: git worktree prune, prunable, gitdir file points to non-existent location, .git/worktrees disappeared, worktree prune deletes all, read-only .git mount is not enough, mount host repo at all, prune in container, git worktree list prunable, git bundle, git clone --shared --no-checkout.
args: &lt;リポジトリのパス&gt;
---

## git worktree prune はリポジトリ単位の破壊的演算

`git worktree prune` は「`gitdir` が指す先が存在しない」worktree の登録を
**リポジトリ全体について** 削除する。対象を絞るオプションは無い。

### 事故のメカニズム

git は `.git/worktrees/<name>/gitdir` に**絶対パス**を保存する。

```bash
cat .git/worktrees/wt-110/gitdir
/tmp/opencode/procon/wt-110/.git
```

`git worktree prune` はこのファイルの指す先を `stat` できないと
「消えた」と判定して登録を消す。コンテナや VM、sandbox から
**パスが違う・そもそもマウントされていない** で git を実行すると、
他人の worktree がすべて「消えた」と判定される。
symlink で辿れる場合も、git は実パスで判定するため解決しないことがある。

```
$ git worktree prune -v
Removing worktrees/wt-b: gitdir file points to non-existent location
Removing worktrees/wt-110: gitdir file points to non-existent location
```

登録していた worktree の数だけ `.git/worktrees` が空になり、git は**ディレクトリごと**削除する。
`git worktree list` を実行しただけで事故が起こることもある。

### 第一__: 本家のリポジトリをマウントしない

**これが唯一の根本的な対策。** 破壊の手段自体を無くす。

```bash
# ホストで bundle を作る（コンテナには渡さない）
git update-ref refs/tmp/bundle/pr-106 <head-sha>
git bundle create /tmp/pr.bundle --branches --tags refs/tmp/bundle/pr-106
git update-ref -d refs/tmp/bundle/pr-106

# コンテナは bundle から独立 clone を作る
docker run ... -v /tmp/pr.bundle:/runner/pr.bundle:ro ...
  git clone --quiet --no-checkout /runner/pr.bundle /work/repo
```

**`git bundle` は ref 名を必要とする。** `FETCH_HEAD` は ref ではないので
一時 ref を立てる。
付け忘れると bundle に ref が入らない。

**`git clone --shared` を使わない。** alternates が `/repo/.git/objects` を
指すので `/repo` マウントの削除と同時に clone したリポジトリも壊れる。
素の `clone` なら alternates が無く、mount が無くても独立して成立する。

**read-only mount では不十分。** 読み取りはできてしまう。
「`.private/` や作業データは共有しない」という方針があるなら、
`:ro` で渡すのは「読ませている」だけで方針に反する。

### 手順: サンドボックスで再現してから対処する

1. **本物では実行しない。** 別ディレクトリに sandbox を作る。

   ```bash
   SANDBOX=/tmp/opencode/prune-repro
   git init -q "$SANDBOX/repo"
   mkdir -p "$SANDBOX/wtparent"
   git -C "$SANDBOX/repo" commit -q --allow-empty -m init
   git -C "$SANDBOX/repo" worktree add -q "$SANDBOX/wtparent/wt-a"
   ```

2. **コンテナの中で prune する。**

   ```bash
   docker run --rm --user "$(id -u):$(id -g)" \
     -v "$SANDBOX/repo":/repo "$IMAGE" \
     sh -c 'git -C /repo worktree prune -v; git -C /repo worktree list'
   ```

3. **ホスト側の変化を確かめる。**

   ```bash
   git -C "$SANDBOX/repo" worktree list
   ls "$SANDBOX/repo/.git/worktrees" 2>&1
   ```

### 検証: 3 つの系統すべてが「無傷」を示すこと

| 確認 | 期待 |
|---|---|
| `git worktree list` | 前後で同一 |
| `.git/worktrees` の中身（sha256） | 前後で同一 |
| コンテナ内 `git worktree prune -v` | `Removing ...` が出ない、または削除に失敗する |

管理情報の bytes を比べるのが確実。

```bash
find "$REPO/.git/worktrees" -type f | sort | xargs sha256sum > before.sha
# ... 破壊的な操作をさせる ...
find "$REPO/.git/worktrees" -type f | sort | xargs sha256sum > after.sha
diff before.sha after.sha
```

**store や cache の件数も数えておく。** mount した副作用を検出できる。

### 対策（効果が強い順）

| 順位 | 対策 | 効果 |
|---|---|---|
| 1 | **本家のリポジトリをマウントしない。** bundle から独立 clone を作る | **決定的。** 破壊の手段が無い |
| 2 | agent に後始末の指示を書かない | 決定的。`--rm` がコンテナを捨てるので不要 |
| 3 | 禁止リストに `prune` を明示する | 多層防御。**単独では防げない** |
| 4 | `.git` を read-only でマウントする | 削除は失敗するが**読み取りはできる**。方針が「読ませない」なら不適合 |
| 5 | worktree の置き場所をコンテナから見えるパスにする | 誤判定を消すだけ。本家的削除は防げない |
| 6 | worktree を永続パスへ移す | **効果が無い。** コンテナから見えないパスは同じ |

### 指示の範囲を絞っても防げない（実測）

事故の時、`prompt.md` は `git worktree remove --force <path>` しか
指示していなかった（=`prune` は指示していない）。
agent が「念のため」と `prune` を 1 語自発的に足した。

**LLM agent は指示の範囲遵守を保証しない。**
ファイルシステム境界でしか守れない。

### 落とし穴

- **`git worktree repair` は策にならない。** `.git/worktrees` が空になると
  孤児 worktree を探す経路自体が無い（`error: unable to locate repository`）。
  復旧は `HEAD` / `commondir` / `gitdir` の手書き再構成でしか確認されていない。
- **`git branch -a` の `+` が手がかりになる。** 別の worktree で checkout 済みなら `+` が付く。
  コンテナ内ログのこの行は「その時点では登録が健在だった」証拠になる。
- **read-only _parent の中に read-write 子を bind mount できる。**
  Docker は深いパスを先に被せるので、`-v repo:/repo:ro` の後に
  `-v repo/app/node_modules:/repo/app/node_modules` を重ねれば
  依存キャッシュだけ書き込み可能になる。ツールがキャッシュを作れなくなり
  機能が死ぬときに効く。
- **nix store をコンテナから使いたいとき**は `store` だけでなく
  **DB と daemon-socket** も bind する。公式 nixpkgs
  `nixos/modules/virtualisation/nixos-containers.nix` が
  `--bind-ro=/nix/store` `--bind-ro=/nix/var/nix/db`
  `--bind-ro=/nix/var/nix/daemon-socket` を指定している。
  DB が無いと nix は store を空とみなす。daemon は permission を解くのであって
  「何が在るか」を解くのではない。
