---
name: stacked-pr-rebase
description: Use when fixing stacked or dependent GitHub PRs whose base was changed to main after a squash merge, causing inflated diffs and CONFLICTING state, or when deciding whether one PR can replace another. Covers merge-base diagnosis, tree-hash proof of zero data loss, git rebase --onto upstream selection, force-with-lease, and remote backups. Trigger keywords: stacked PR, base change, CONFLICTING DIRTY, merge-base, rebase --onto, force-push, force-with-lease, squash merge, PR absorption, inflated diff, スタックしたPR, base変更, 競合, 履歴の巻き戻し, PR統合.",
args: &lt;feature ブランチ名&gt; [&lt;新しい base&gt;]
---

## いつ使うか

GitHub の PR が「スタック」している（下の PR のブランチを base にしている）と:main への squash merge 後に base を `main` に変えたときに、次のような症状が出たとき。

- PR の差分が何倍にも膨張する（既に main に入った内容が重複して見える）
- PR が `CONFLICTING` / `DIRTY` になる
- merge-base が想定より古いコミットを指している
- 「片方の PR でもう片方を代替できる」と判定したい

## 症状の原因

main へ **squash merge** すると、main には「PR の全差分を含む1コミット」ができるが、
feature ブランチは元の線形なコミット列のままなので、main のそのコミットを祖先として持たない。

結果として `git merge-base main feature` が **squash より前の古いコミット**を返す。
GitHub の3点 diff は `merge-base..head` なので、**既に main にあるはずの内容が差分に出現する**。

```
main      : ... ─ 502279b(squash) ─ 7a6f8e1(squash)
                     |
feature   : ... ─ a007d99 ─ 4722877 ─ b48d5aa
            ↑ merge-base がここまで戻る
```

## 手順

### 1. 現状を必ず数値で確認する

```bash
git fetch origin
gh pr list --state open --json number,headRefName,baseRefName,headRefOid,isDraft,mergeable \
  --jq '.[]|"#\(.number) \(.headRefName) → \(.baseRefName) head=\(.headRefOid[0:8]) draft=\(.isDraft) mergeable=\(.mergeable)"'

# merge-base がどこまで落ちているか
git merge-base origin/main origin/<feature> | cut -c1-8
git log --oneline -1 $(git merge-base origin/main origin/<feature>)

# 3点 diff がどれだけ膨張するか
git diff --stat origin/main...origin/<feature> | tail -1
```

### 2. バックアップを push する（最重要）

```bash
git push origin <old-head>:refs/heads/bbackup/<branch>-pre-rebase
git ls-remote --heads origin 'bbackup/*'    # push できたか必ず確認
```

**`git branch backup/x origin/y` は upstream 設定するだけで push しない。**
「push 済み」と言ってはいけない。`git ls-remote` で実在を確認するまで保護にならない。

### 3. rebase する（upstream の指定が決め手）

```bash
git worktree add --detach /tmp/opencode/rb origin/<feature>
cd /tmp/opencode/rb
git rebase --onto origin/main <upstream> origin/<feature>
```

**`<upstream>` は、そのブランチ自身の最初のコミットの親にする。**
merge コミットを upstream にすると、同ブランチの本体コミットが落ちる。

```
* aa8a469  fix: レビュー指摘      <- 移植対象
*   6d2e313  Merge ...            <- ここを upstream にすると aa8a469 だけ残る（本体が落ちる）
|\
| * b48d5aa                        <- 正しい upstream
* | a0ea8a4  feat: ...            <- 落ちる
|/
* 4722877                          <- 正しい upstream（a0ea8a4 の親）
```

rebase は**内容重複の merge コミットを自動で drop する**
（`dropping <sha> -- patch contents already upstream`）。この挙動は期待どおり。

### 4. データ損失ゼロを証明してから push する

```bash
git rev-parse <old-head>^{tree}     # 旧 remote head
git rev-parse <new-head>^{tree}     # push 予定
# 一致すればファイル内容は 1 バイトも変わっていない
```

tree ハッシュ一致は**最強の証明**。これが出れば force-push は履歴だけの操作。

差分が空でない場合は、`git diff --stat <old> <new>` で確認し、
**意図しない差分が 0 であることを 1 ファイルずつ見る**。
空でない箇所は「下側が計算対象を変えた之类的意図した改善」の可能性がある。

### 5. `--force-with-lease` に期待 SHA を明示する

```bash
git branch -f push/<x> <new-head>
git push --force-with-lease=refs/heads/<branch>:<remote-now> origin 'push/<x>:refs/heads/<branch>'
```

**`--force` ではなく `--force-with-lease` を使う。** 期待 SHA を書くと、
fetch 後にリモートが動いていれば push が失敗する。

**zsh では `:refs` の `:r` が欠落して壊れることがある**
（`...d19f` + `efs/heads/...`）。ローカル branch を切って push すると安全。

### 6. push 後に検証する

```bash
git fetch origin <branch>
git rev-parse origin/<branch>^{tree}          # push したものと一致
git rev-parse origin/bbackup/<x>^{commit}    # 旧 head が復旧可能
```

作業ツリーに未コミット変更がある場合は `git worktree add` を使う。
削除は `git worktree remove`（`rm -rf` だと孤児が残る）。

## PR の吸収判断

下のブランチの head が上のブランチの**祖先**なら、下の PR は不要になる。

```bash
git merge-base --is-ancestor origin/<lower> origin/<upper> && echo "含む"
```

close する前に次を証明する。

- tree ハッシュ一致（rebase がファイルを変えていない）
- 下側 PR の変更ファイルが上側に存在する（blob ハッシュ照合）
- 差分が空でない箇所は意図した改善か（`measureWidthCoverage` から
  `measureSegmentsWidthCoverage` への差し替えのような場合）

## 落とし穴

- **base を `main` に変えた直後に `--force-push` すると、スタック全体が壊れる。** 下のブランチから順に直す。
- **`git branch` は push しない。** 手順 2 を省略しない。
- **upstream を merge コミットにすると本体のコミットが落ちる。** 手順 3 の図で確認。
- **衝突時に `git checkout --theirs` を不用意に使うと下側ブランチの変更が失われる。**
  両方変更したファイルでは、rebase 先の head が下の内容を含むかを先に確認する。
  実は upstream を正しく選べば衝突は起きないことが多い。
- **main と feature の tree が一致しても、3点 diff は膨張する。** 判定は必ず 3 点で。
- rebase 後は **CI が再実行される**ので、push 前に test / 型チェック / build を全部通しておく。
- 吸収して merge した後、main の履歴は **1 コミットにまとまる**。機能ごとに残したければ
  rebase merge を使うが、リポジトリの慣習（squash のみ）に背く。

## 関連

- PR のレビューとインラインコメントの投稿は `gh-pr-inline-review` を参照。
- 作業ツリーに未コミット変更がある状態での修正は `worktree-fix-merge-cycle` を参照。
