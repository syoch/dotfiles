---
name: worktree-admin-dir-loss-forensics
description: Use when git worktree management info under .git/worktrees/ disappeared while the working tree directories survived, or when a bot/agent/script may have run destructive git commands. Determines the culprit command from mtimes, container logs, and systemd journals, then reproduces the mechanism in a sandbox. Trigger keywords: worktree 消えた, .git/worktrees 消滅, worktree 管理情報, fatal: not a git repository, git worktree prune, worktree 調査, worktree forensics.
args: &lt;リポジトリのパス&gt;
---

## いつ使うか

- `git worktree list` が main だけになり、作業ツリーのディレクトリは残っているのに
  `.git/worktrees/<name>/` が消えた
- 作業ツリー側で `fatal: not a git repository` / `fatal: not a git repository: (null)`
- 「誰が `.git` を壊したのか」を特定したい（bot / agent / systemd service / 手動）
- `git worktree prune` が犯人かどうか切り分けたい

## 前提知識

`.git/worktrees/<name>/` は「管理情報」。`gitdir` ファイルに**絶対パス**を保持する。
これが失われると、作業ツリーは内容が無傷のまま操作不能になる。
典型的な原因と詳細な仕組みは memory `git/container-worktree-prune-hazard` を参照。

## 手順

### 1. 本物を壊さない準備

- 調査ディレクトリを作る時は **そのリポジトリの worktree を作らない**（調査対象が `.git/worktrees/` いため）。
- git を読むときは常に `git -C <メインリポジトリの絶対パス> <command>` と明示する。
- 復現実験は必ず別の sandbox（`/tmp/opencode/...`）で行う。

### 2. 「消えた」vs「中身が空」の切り分け

```bash
cd <repo>/.git
stat -c '%n  mtime=%y  ctime=%z' . worktrees worktrees/* 2>&1
```

- `worktrees` **ディレクトリ自体が無い** → ディレクトリごと削除された。
  かつ `.git` の mtime が その時刻を示す → 削除時刻が分かる。
- `worktrees` が**空** → 中身の削除とディレクトリ削除は別イベント。

### 3. 削除時刻の特定（最重要）

mtime の三段構え:

| 対象 | 意味 |
|---|---|
| `<repo>/.git` の mtime | `.git` の直下子の追加/削除があった時刻。`worktrees` が消えていればこれが削除時刻 |
| `.git/worktrees/` の mtime | その中のエントリが増減した時刻 |
| 各管理情報ファイル（HEAD / commondir / gitdir）の mtime | 作成・上書き時刻 |

- ext4 の mtime 精度は約 1〜4ms なので、**同一値 = 同一時刻**として扱える。
  これが「削除と再登録が同時刻」を示す強い証拠になる。
- 後で他操作が `.git` を触ると mtime が上書きされる。その場合は
  **当時の `ls -la .git/` の出力が会話ログに残っていないか**探す（セッション API から取得）。

### 4. 「当時までは正常だった」ことの裏付けを探す

コンテナや bot の実行ログの中に、被害**前**の `git worktree list` / `git branch -a` を探す。

- `git branch -a` で **`+` 付きのブランチ** = 別 worktree で checkout 中（= 登録当时は健在）。
- これが「その時点では正常」の証拠になる。

### 5. 犯人のコマンドの特定（一次記録から）

優先順に探す:

1. **コンテナ/ボットの実行ログ**。`docker run` の stdout をファイルに取ってあるなら
   `opencode.log` 等が最有力（opencode CLI は全ツール呼び出しを plaintext で出す）。
   ```bash
   grep -n -oE '.{80}worktree.{160}' <botの出力ログ>
   ```
2. **systemd journal**（ボットの起動・終了時刻を確定させる）。
   ```bash
   journalctl --user -u <unit名> --since "2026-10-04 16:50" --no-pager
   ```
3. **opencode セッション API**（セッションに bot を起動したコマンドが残っている場合）。
   ```bash
   curl -s "http://localhost:12000/session/<ID>/message?directory=<dir>&limit=500"
   ```
   `parts[].state.input.command` に全コマンド、`state.output` に実行結果が入る。
4. **セッション DB の全走査**（漏らし分を潰すため）。
   `~/.local/share/opencode/opencode.db` の `part` テーブルを当日範囲で走査し、
   `git worktree prune` / `worktree remove` / `worktree move` を含む tool call を全抽出する。
   - 手順は global skill `db-session-history-query`。
   - **注意**: コンテナ内で動いた opencode は別 DB（tmpfs 上）を持つので、
     この走査では**捕まらない**。コンテナ側のログを必ず直接読む。

### 6. 犯人を確定する前に「前提」を実測する

依頼された前提（例: 「prune はディレクトリが残っていれば消えない」）は
**信用せず**、別 sandbox で実験する。

```bash
# 実験A: 同じ mount namespace なら消えないか
git init repo && git -C repo worktree add ../wt-a -b a
git -C repo worktree prune -v && git -C repo worktree list
```

現象が namespace 依存なら、コンテナで再現する（本命の実験）。
`unshare -m` が権限で弾かれる環境（Jupyter/sandbox 内など）があるので、
`docker run` で既存のイメージを使うのが確実。

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  --tmpfs /runner:mode=1777 \
  -v /nix:/nix:ro \
  -v "$BASE/repo":/repo \      # ← 本番と同じ指定（:ro の有無を再現する）
  -v "$BASE/wtparent":/wtparent \
  pr-review-bot:latest sh -c 'cd /repo && git worktree list && git worktree prune -v && git worktree list'
```

- イメージ内に git がない場合は `apk add --no-cache git` するが、`--user $(id -u)` だと root ではないので失敗する。
  その場合 git 入りのイメージを選ぶ。
- `safe.directory` の回避が必要なら `GIT_CONFIG_GLOBAL` に
  `[safe]\n\tdirectory = *\n` を書いて `-e GIT_CONFIG_GLOBAL=...` で渡す。

### 7. 復旧手段も sandbox で検証する

`.git/worktrees` が空になると git は孤児 worktree を発見できない。
以下を sandbox で実測してから報告する（推測で書かない）。

| 手段 | 実測結果（2026-10-04, git 2.55 / コンテナ内 git 2.39） |
|---|---|
| `git worktree repair`（パスなし） | 無反応 |
| `git worktree repair <path>` | `error: unable to locate repository; .git file does not reference a repository` |
| 管理情報（HEAD / commondir / gitdir）を手で再構成 | **復旧する**（唯一、実証済みの方法） |

## 落とし穴

- **会話ログの `command` は 400 文字で切れていることがある。** 多行コマンドの
  途中に `rm` があれば「破壊的操作なし」と誤診する。必ず全文を取得する。
- **同じセッション ID が旧パスと新パスの両方に登録されることがある**（worktree を move した後など）。
  両方を確認する。
- **delegate/子セッションを「無実」と判断する前に、ログの該当行の全文を読む。**
  `mkdir` と複数回の `printf` が 1 つの tool call に入っていることがある。
- **`git worktree prune` には対象を絞るオプションが無い。** 「自分の worktree を片付ける」意図で
  実行すると、リポジトリ全体が影響を受ける。
- mtime は他操作で上書きされる。**当時の出力を証拠として優先する**。
- タイムゾーンが混在する（ホスト JST / コンテナ UTC）。`review.json` 等の mtime は UTC で出る。

## 検証方法

- 削除時刻（`.git` の mtime）と犯人の実行時刻（journal / コンテナログ）が一致する。
- sandbox 再現実験で、**実際の症状と同一の文字列**が観測される
  （例: `Removing worktrees/X: gitdir file points to non-existent location`、
  `fatal: not a git repository: (null)`、`.git/worktrees` ディレクトリ自体の消失）。
- 当日 DB 全走査で、犯人のセッション由来ではない `git worktree prune` が存在しないことを確認する。

## 関連

- memory `git/container-worktree-prune-hazard` — 仕組みと対策
