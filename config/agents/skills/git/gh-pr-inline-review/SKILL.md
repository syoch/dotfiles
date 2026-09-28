---
name: gh-pr-inline-review
description: Use when posting a GitHub PR review with line-level (inline) comments via gh api. Trigger keywords: PR review, inline comment, gh pr review, 行コメント, レビュー投稿, review with evidence.
---

# gh で PR にインラインコメント付きレビューを投稿する

## いつ使うか
- GitHub PR を精査し、**行単位のインラインコメント**を付けてレビューを投稿したいとき。
- レビュー本文は事前に下書き・確認したいが、インラインは diff の行に直接付けたいとき。

## 手順
1. 事前調査（読み取りのみ）
   ```bash
   gh pr view <N> --json number,title,state,headRefName,baseRefName,author,mergeable,mergeStateStatus,reviewDecision,files,headRefOid
   gh pr view <N> --json commits --jq '.commits[]|.oid[0:7]+" "+.messageHeadline'
   gh pr view <N> --json statusCheckRollup --jq '.statusCheckRollup[]|{name:(.name//.context),conclusion:(.conclusion//.state)}'
   gh pr diff <N> > /tmp/opencode/pr<N>/pr.patch
   ```
   - `git status` がクリーンでローカル HEAD == PR head sha なら、チェックアウト済みファイルをそのまま読める（差分ファイルは `gh api "repos/$O/$R/contents/<path>?ref=<sha>"` でも取得可。`?` は zsh で glob になるため **必ず引用**）。
2. 変更ファイルを読み、**根拠（実行結果・実測・コード）と責任範囲**をセットで整理する。推測で書かない。可能なら再現実行する。
   - 純 TS モジュールは型のみなら `nix-shell -p nodejs_22 --run "node --experimental-strip-types test.ts"` で直接実行できる（動かない場合は別途トランスパイル）。
   - ブラウザ挙動は Playwright で DOM 件数（例 `path.leaflet-interactive` / `.leaflet-marker-icon`）とコンソールを実測すると強い根拠になる。
3. **コメント可能な行（= diff の追加行）を把握する**。GitHub は diff 内の行にしかインラインコメントできない。パッチを解析して追加行番号を得る:
   ```bash
   python3 - <<'EOF'
   import re
   lines=open('/tmp/opencode/pr<N>/pr.patch').read().split('\n')
   cur=None; newno=None; added={}
   for l in lines:
       m=re.match(r'^diff --git a/(\S+) b/(\S+)',l)
       if m: cur=m.group(2); added.setdefault(cur,[]); newno=None; continue
       h=re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@',l)
       if h: newno=int(h.group(1)); continue
       if cur is None or newno is None: continue
       if l.startswith('+++') or l.startswith('---'): continue
       if l.startswith('+'): added[cur].append(newno); newno+=1
       elif l.startswith('-'): pass
       elif l.startswith(' ') or l=='': newno+=1
   for k,v in added.items(): print(k,v)
   EOF
   ```
   新規ファイルは `@@ -0,0 +1,N @@` なので全行が追加行。**範囲コメント**は `start_line` + `line`（両方 `side: RIGHT`）。
4. payload を JSON で作る（本文とコメントを1ファイルに）:
   ```json
   {
     "body": "レビュー本文",
     "event": "COMMENT",
     "comments": [
       {"path": "app/src/x.ts", "line": 12, "side": "RIGHT", "body": "..."},
       {"path": "app/src/y.ts", "start_line": 5, "line": 9, "start_side": "RIGHT", "side": "RIGHT", "body": "..."}
     ]
   }
   ```
   Python で生成するとエスケープ事故が無い（`json.dump(..., ensure_ascii=False, indent=2)`）。
5. 投稿:
   ```bash
   gh api repos/$O/$R/pulls/<N>/reviews --input /tmp/opencode/pr<N>/review.json --jq '{id:.id,state:.state,html_url:.html_url}'
   ```
6. 検証（必須）:
   ```bash
   gh api repos/$O/$R/pulls/<N>/comments --jq '.[]|select(.pull_request_review_id==<ID>)|"\(.path):\(.line // .original_line)"'
   gh api repos/$O/$R/pulls/<N>/comments --jq '[.[]|select(.pull_request_review_id==<ID>)]|length'
   ```

## 落とし穴
- **diff 外の行にコメントすると API エラー**（`Line could not be resolved`）。追加行番号で指定する。
- 既存レビューが `CHANGES_REQUESTED` の場合、`event:"COMMENT"` なら状態は変わらない。`REQUEST_CHANGES` は重複に見えるので、意図を確認してから。
- 本人の PR に `REQUEST_CHANGES` は付けられない/不自然。既定は `COMMENT`。
- レビュー本文に**特定ファイルの指摘を書くとインラインと重複**する。本文は「全体方針・前提・責任範囲・差分外（コメント不可）の補足」だけにする。
- `?ref=` 付き URL や日本語パスはシェルのクォートに注意（zsh は `?` を glob 展開する）。
- 投稿前にユーザーが「下書き確認」を求めていないかを確認する（求められたら `review.json` まで作って提示）。
- 公開操作（投稿）はアカウント名義で行われる。ユーザーの同意なく連投しない。
