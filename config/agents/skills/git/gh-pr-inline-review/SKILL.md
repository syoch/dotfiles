---
name: gh-pr-inline-review
description: Use when posting a GitHub PR review with line-level (inline) comments via gh api. Trigger keywords: PR review, inline comment, gh pr review, 行コメント, レビュー投稿, review with evidence.
---

## いつ使うか
- PR にインラインコメント（行コメント）を投稿したいとき
- 既存のレビューコメントに返信したいとき
- 対応済みのレビュースレッドを Resolve Conversation したいとき

## 前提: リポジトリ変数を設定する

```bash
O=<owner>; R=<repo>
```

## 手順

### インラインコメントを投稿する

1. `git diff` で対象箇所の行番号を確認する（`line` は RIGHT 基準）。
2. payload を JSON で作る（本文とコメントを1ファイルに）。**必ず後述の作法に従う。**

     ```json
     {
       "body": "レビュー本文",
       "event": "COMMENT",
       "comments": [
         {"path": "app/src/x.ts", "line": 12, "side": "RIGHT", "body": "..."}
       ]
     }
     ```

3. 投稿する。

     ```bash
     gh api repos/$O/$R/pulls/<N>/reviews --input /tmp/opencode/pr<N>/review.json --jq '{id:.id,state:.state,html_url:.html_url}'
     ```

4. 検証（必須）。

     ```bash
     gh api repos/$O/$R/pulls/<N>/comments --jq '.[]|select(.pull_request_review_id==<ID>)|"\(.path):\(.line)"'
     gh api repos/$O/$R/pulls/<N>/comments --jq '[.[]|select(.pull_request_review_id==<ID>)]|length'
     ```

### 既存コメントに返信する

`pulls/<N>/comments/<comment_id>/replies` を使う。
スレッドID（`PRRT_...`）ではなく**コメントの数値 id** を渡す。

```bash
gh api repos/$O/$R/pulls/<N>/comments/<comment_id>/replies -f body="対応内容"
```

対象行が削除・変更されて `pulls/<N>/comments` の新規作成が 422 で失敗する場合は、
インラインコメントの新規作成が 422 で失敗する場合は、
返信エンドポイントを使い、既存コメントへの返信として投げる。

### Resolve Conversation する

**対応内容を返信してから resolve する。順序を逆にすると、
変更していないコメント解決扱いになる。**

1. スレッド一覧と解決状況を確認する。

     ```bash
     gh api graphql -f query='
     query { repository(owner:"'"$O"'", name:"'"$R"'") { pullRequest(number:<N>) { reviewThreads(first:100) {
       nodes { id isResolved isOutdated path line
               comments(first:1){ nodes { databaseId body } } } } } } }' \
       --jq '.data.repository.pullRequest.reviewThreads.nodes
              | map(select(.isResolved==false))
              | {unresolved: length, ids: map(.id)}'
     ```

2. 1 件ずつ、対応内容を返信してから resolve する。

     ```bash
     gh api repos/$O/$R/pulls/<N>/comments/<databaseId>/replies -f body="対応しました。..."
     gh api graphql -f query='
     mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { id isResolved } } }' \
       -f id="<PRRT_kwDO...>"
     ```

3. 全部消えたことを確認する。

     ```bash
     gh api graphql -f query='
     query { repository(owner:"'"$O"'", name:"'"$R"'") { pullRequest(number:<N>) { reviewThreads(first:100) {
       nodes { isResolved } } } } }' \
       --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved==false)) | length'
     ```

`isOutdated: true` は、レビューされた行が後から変わったことを意味する。
`line` が `null` になるので、新規インラインコメントではなく返信で応じる。

## 最重要の落とし穴: 日本語 body を生成すると文字化けする

長文日本語を 1 つの文字列リテラルとして生成すると、途中で語句の混入や欠落が起きる。
実測で 6 回発生し、修正のための置換が新たな混入を生んだ。
公開 API への投稿なので取り消しが利かない。

**本文とコメントを別ファイルに分けて `json.dumps` で組み立てる。**
エスケープ事故も混入も減る。

## その他の落とし穴

- **diff 外の行にコメントすると API エラー**（`Line could not be resolved`）。
  追加行番号で指定する
- 既存レビューが `CHANGES_REQUESTED` の場合、`event:"COMMENT"` なら状態は変わらない。
  `REQUEST_CHANGES` は重複に見えるので、意図を確認してから
- 本人の PR に `REQUEST_CHANGES` は付けられない／不自然。既定は `COMMENT`
- レビュー本文に**特定ファイルの指摘を書くとインラインと重複**する。
  本文は「全体方針・前提・責任範囲・差分外（コメント不可）の補足」だけにする
- `?ref=` 付き URL や日本語パスはシェルのクォートに注意。
  zsh は `?` を glob 展開する
- 投稿前にユーザーが「下書き確認」を求めていないかを確認する。
  求められたら `review.json` まで作って提示する
- 公開操作（投稿）はアカウント名義で行われる。ユーザーの同意なく連投しない
- **Resolve Conversation は opencode の API に無い。**
  `gh api` の GraphQL を使う
- **返信は `comments/<id>/replies`。** スレッドID（`PRRT_...`）ではない

## 関連

- セッションを委任して作業を任せる: `session-delegation`
- Resolve Conversation の GraphQL: 上記「Resolve Conversation する」
