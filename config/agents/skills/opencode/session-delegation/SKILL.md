---
name: session-delegation
description: Use when delegating work to another OpenCode session over the Web API, or when a delegated session looks stalled: managed server on port 12000, nested model in the request body (top-level providerID/modelID hangs forever), prompt_async for fire-and-forget, backgrounding with nohup, cold-start non-determinism, completion callbacks instead of polling, the pgrep self-deadlock trap, and checking liveness with session_state.py. Trigger keywords: OpenCode Web API, opencode serve, opencode.service, delegate, delegation, セッション委任, 委任, prompt_async, noReply, fire-and-forget, バックグラウンド起動, コールドスタート, 応答が来ない, nohup, session_state, 完了通知, pgrep.
args: &lt;worktree&gt; &lt;prompt file&gt;
---

# Delegating work to another OpenCode session

How to hand a task to a separate OpenCode session over the Web API, and how to
get the result back without babysitting it.

Scripts live next to this file:

- `scripts/delegate.py` — create/find a session, send a prompt, send a completion callback
- `scripts/session_state.py` — ask the server whether a session is still working

## Use the managed server

`opencode.service` (systemd user service) is the canonical server.

```bash
systemctl --user is-active opencode.service
curl -s -o /dev/null -w "%{http_code}" http://localhost:12000/session
```

**Do not start an ad-hoc `opencode serve --port <port>`.** Two servers cause
confusion, and an ad-hoc one misses credential refreshes.

## Read the spec when something looks wrong

- Server docs: <https://opencode.ai/docs/server/>
- Local OpenAPI: `curl -s http://localhost:12000/doc | python3 -m json.tool | less`

**This machine runs opencode v1.** The v2 docs use a different request shape, so
getting-started and session examples from v2 may not apply.

## Send a prompt

```bash
# Find or create a session scoped to the worktree, then send the prompt
python3 delegate.py --worktree <worktree> --title "<task>" --prompt-file <plan.md>

# Target an existing session by id (review requests, follow-ups)
python3 delegate.py --session <session-id> --prompt-file <plan.md>

# Block until the run finishes (background it — see below)
python3 delegate.py --session <session-id> --prompt-file <plan.md> --wait
```

## Request body (get this wrong and it hangs forever)

**`providerID` / `modelID` must be nested under `model`.** Not top level.

```
wrong: { "parts": [...], "providerID": "...", "modelID": "..." }
right: { "parts": [...], "model": { "providerID": "...", "modelID": "..." } }
```

The schema sets `additionalProperties: false`, so the wrong form is rejected
silently: an assistant message is created with zero parts and **no run starts**.
The POST never returns. Switching providers does not help.

## `prompt_async` for fire-and-forget

```bash
curl -s -X POST "http://localhost:12000/session/<ID>/prompt_async?directory=<worktree>" \
  -H 'content-type: application/json' \
  -d '{"model":{"providerID":"...","modelID":"..."},"parts":[{"type":"text","text":"..."}]}'
```

**`noReply: true` does not start a run.** It means "do not generate a reply".
It is not a fire-and-forget flag. Backgrounding is a process-side concern.

## POST blocks until the run completes

Launch it as a background process so the current session can keep working.

```bash
nohup python3 delegate.py --session <ID> --prompt-file <plan.md> --wait \
  > <log> 2>&1 &
```

## Do not poll. Ask for a callback.

**Do not poll for completion.** Have the delegated session send a completion
message back to you. The waiting side does nothing until the message arrives.

```bash
# run inside the DELEGATED session, when the work is done
python3 delegate.py --notify-done <parent-session-id> <marker.json>
```

The marker JSON carries `summary`, `checks`, and `notes`. The parent session
receives the report and moves on.

```json
{
  "summary": "one line of what was done",
  "checks": ["what was verified"],
  "notes": ["trade-offs, what was deliberately not changed"]
}
```

A failed callback does not lose the work. The marker file survives, so it can be
sent later — write it **after** pushing and committing.

### Polling self-deadlocks

**Never write a `pgrep` / `sleep` wait loop.** This has actually happened and
the session looked hung while producing nothing for ten minutes.

```bash
# WRONG: never terminates. pgrep matches its own command line
for i in $(seq 1 10); do
  sleep 60
  if ! pgrep -f send_prompt.py >/dev/null; then break; fi
done
```

`pgrep -f` matches **the polling shell itself**, so `! pgrep` stays false forever
and `break` is never reached. It just sleeps.

Processes are a weak signal. Ask the server instead:

```bash
python3 session_state.py <session-id> <worktree>
```

| Output | Meaning |
|---|---|
| a tool is running | still working |
| 0 tools / completed | idle at a message boundary |
| `/session/status` empty | no session is running |
| server unreachable | check `opencode.service` |

**Never declare a session stopped from one observation.** A cold start looks
identical to a stall.

## Cold start looks like a stall

Right after launch this is normal:

```
messages: 2 (1 user + 1 assistant)
assistant parts: 0
/session/status: {}
```

**That is the cold-start gap, not a stop.** The response arrives on its own if
you wait. Cold start is **non-deterministic**: the same prompt both succeeds and
times out (observed: 500 characters timed out, 1000–6000 succeeded — size is not
the cause).

## What to put in the prompt

- Write the plan to a file, then embed its contents
- State the rules that apply (comment style, forbidden edits, commit trailers)
- **Instruct it to do the post-push work too** (resolve review threads, report)
- Say explicitly not to stop partway
- **Name the files it must not touch.** If another PR is in flight, a symlink
  makes it collide
- Point it at the skill that governs the task instead of restating the skill

## Verify completion

| Means | Confirms |
|---|---|
| completion callback | the delegate's report |
| `gh pr checks <N>` | the final CI result |
| opening the session in the web UI | progress and content |
| the log file | the background process's return value |

## Pitfalls

- **A malformed body hangs.** Switching providers does not help
- **`noReply: true` does not start a run.**
- **Never judge "stopped" from one observation.** Cold start is non-deterministic
- **Never wait with a `pgrep` / `sleep` loop.** See "Polling self-deadlocks"
- **Send the callback once.** Not repeatedly during the work
- **Do not delegate `git commit --amend` or `git push --force`.** A careless force
  push destroys someone else's work
- **`session.create` takes the directory as a query parameter**, not in the body.
  The body is `{ "title": ... }` only

## Related

- Archiving and deleting sessions: `session-archive-workflow`
- Posting inline review comments: `gh-pr-inline-review`
- Resolving review threads: `gh-pr-inline-review`
