# コンテナ内で `git worktree prune` を実行すると、/tmp 配下の全 worktree 管理情報が消滅する

## 事象（2026-10-04、procon リポジトリで実測）

pr-review-bot のコンテナ内 opencode エージェントが
`git worktree remove --force /tmp/pr-review-106 && git worktree prune` を実行したところ、
ホスト側の 6 個の worktree の管理情報 `.git/worktrees/*/` が全滅した（作業ツリーは無傷）。

## 仕組み

1. git の worktree 管理情報 `.git/worktrees/<name>/gitdir` は**絶対パス**を保持する。
2. コンテナに `-v REPO_ROOT:/repo`（`:ro` なし = read-write）でマウントし、
   **`/tmp` をマウントしていない**と、コンテナからは
   「ホストの `/tmp/opencode/procon/wt-*`」が存在しないのと同じに見える。
3. `git worktree prune` は「gitdir が指す先が stat できない」worktree を prunable と判定し、
   **リポジトリ全体の管理情報を削除する**（対象を絞るオプションは存在しない）。
4. 全件削除されて空になった `.git/worktrees` は**ディレクトリごと削除される**。

## 決定的な兆候

- コンテナ内 `git worktree list` に `prunable` が並ぶ。
- `git worktree prune -v` が `Removing worktrees/X: gitdir file points to non-existent location` を出力。
- ホスト側では `git worktree list` が main だけになり、作業ツリーは残るのに
  `git status` が `fatal: not a git repository: (null)` になる。

## 重要な補足

- **作業ツリーをコンテナに別パスでマウントしても解決しない。**
  git は絶対パスを保持するため、マウント先が見えても `gitdir` の指す先が
  stat できない限り prunable になる。
- **`git worktree prune` は bot の prompt に指示されていなくても agent が自発的に付け足す。**
  LLM エージェントは「後始末」として prune を足す傾向がある。
- ホスト側のセッションが同じ `git worktree prune` を実行しても無害（同じ mount namespace だから）。
  差分は「コンテナ内かホスト内か」だけ。

## 対策

- bot のリポジトリマウントは `-v REPO_ROOT:/repo:ro`。
  ただし `git worktree add` 自体が `.git` を書くので、worktree を作らせたいなら
  `git clone --shared --no-checkout` を tmpfs 上に作って渡す（管理情報が隔離される）。
- prompt に `git worktree prune` / `git clean` / `git gc` を明示禁止する。
- **そもそも worktree を `/tmp` 配下に置かない。** 永続・非 tmpfs の場所（`~/worktrees/`）を使う。

## 復旧方法（実測済み）

`.git/worktrees` が空になると、worktree の一覧を保持する唯一の場所（このディレクトリ）が
消えるため、git は孤児 worktree を発見する経路自体を持たない。

- `git worktree repair`（パスなし）: **無反応**
- `git worktree repair <path>`: **エラー** `.git file does not reference a repository`
- **管理情報（HEAD / commondir / gitdir）を手で再構成: 唯一有効な方法**

復旧スクリプト:

```bash
MAIN=/path/to/repo
D="$MAIN/.git/worktrees/<name>"
mkdir -p "$D"
printf 'ref: refs/heads/<branch>\n' > "$D/HEAD"     # detached なら SHA を直接書く
printf '../..\n'                          > "$D/commondir"
printf '/abs/path/to/worktree/.git\n'      > "$D/gitdir"
GIT_INDEX_FILE="$D/index" git -C /abs/path/to/worktree read-tree HEAD
```
