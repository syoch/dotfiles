---
name: session-delegation
description: Use when delegating work to another OpenCode session over the Web API, or when a delegated session looks stalled: managed server on port 12000, nested model in the request body (top-level providerID/modelID hangs forever), prompt_async for fire-and-forget, backgrounding with nohup, cold-start non-determinism, completion callbacks instead of polling, the pgrep self-deadlock trap, and checking liveness with session_state.py. Trigger keywords: OpenCode Web API, opencode serve, opencode.service, delegate, delegation, セッション委任, 委任, prompt_async, noReply, fire-and-forget, バックグラウンド起動, コールドスタート, 応答が来ない, nohup, session_state, 完了通知, pgrep.
---

## Do not poll. Ask for a callback.

**Do not poll for completion.** Have the delegated session send a completion
message back to you. The waiting side does nothing until the message arrives.

```bash
# run INSIDE the DELEGATED session, when the work is done
python3 delegate.py --notify-done <parent-session-id> <marker.json>
```

The marker JSON carries `summary`, `checks`, and `notes`. The parent session
receives the report and moves on.

### `--notify-done` は委嘱時には渡さない

**これは子側の完了時に実行するコマンドであり、委嘱コマンドのオプションではない。**

`--notify-done` を渡すと `delegate.py` は `notify_done()` を実行して `return` する。
**セッションを作らない。** つまり次の 2 点が同時に起きる。

1. 委嘱が空振りする（子セッションが存在しない）
2. placeholder の marker 内容がそのまま親に届く（偽の完了通知）

```
$ delegate.py --worktree <wt> --title <t> --prompt-file <p> \
    --notify-done <parent> marker.json --log <log>
OK: ses_xxx notified (189 chars)      # ← 偽物。セッションは作られていない
$ opencode db "SELECT id FROM session WHERE directory='<wt>'"
（空）                                 # ← 実体が無い
```

**委嘱は `--worktree` と `--title` だけ渡す。** 完了通知は依頼文の中に
子自身が `--notify-done` を実行するよう書いておく。

```bash
# 委嘱（--notify-done を付けない）
delegate.py --worktree <wt> --title <task> --prompt-file <plan.md> --log <log>

# 依頼文の末尾にこれを書いて、子に完了時の実行を任せる
python3 .../delegate.py --notify-done <parent-session-id> <marker.json>
```

偽の完了通知が飛んで来たら、**`<worktree>` のセッションが存在するか**確かめること。
空なら委嘱し直す。

### 完了通知の中身がプレースホルダに見えるとき

子セッションが `--notify-done` を実行する前に通知が飛んできた場合、
それは子ではなく**呼び出し側の事故**である（上の誤用）。
`summary` に「完了したら〜」のような未来形が入っていたら疑う。

### ログの親ディレクトリは先に作る

`--log /tmp/opencode/logs/x.log` の場合、`logs/` が無いと
`FileNotFoundError` で委嘱が落ちる。
先に `mkdir -p` する。

```json
{
  "summary": "one line of what was done",
  "checks": ["what was verified"],
  "notes": ["trade-offs, what was deliberately not changed"]
}
```
