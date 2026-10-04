#!/usr/bin/env python3
"""Ask the OpenCode server whether a session is still working.

Query the server instead of listing processes.
Trust the server response. Processes are only a weak signal.

usage:
    python3 session_state.py <session-id> [<worktree>]
    python3 session_state.py --all
"""
import json
import sys
import urllib.request

SERVER = "http://localhost:12000"
TIMEOUT = 10

# Hints that suggest the session is idle.
# Any one of them is evidence that nothing is running.
# A cold start looks the same and is NOT listed here.
IDLE_EVIDENCE = {
    "server_down": "server unreachable",
    "no_tool_running": "no tool running in the last message",
    "last_message_done": "the last message has time.completed",
}


def get(path):
    with urllib.request.urlopen(f"{SERVER}{path}", timeout=TIMEOUT) as resp:
        return json.loads(resp.read())


def server_alive():
    try:
        get("/session/status")
        return True
    except Exception as error:
        print(f"  cannot reach the server: {error}")
        return False


def inspect(session_id, worktree):
    query = f"?directory={worktree}&limit=5" if worktree else "?limit=5"
    messages = get(f"/session/{session_id}/message{query}")
    if not messages:
        print("  no messages yet (the session exists)")
        return []

    last = messages[-1]
    info = last.get("info", {})
    parts = last.get("parts", [])
    tools = [p for p in parts if p.get("type") == "tool"]
    running = [p for p in tools if p.get("state", {}).get("status") == "running"]
    completed_at = info.get("time", {}).get("completed")

    print(f"  role={info.get('role')} agent={info.get('agent')}")
    completed={'yes' if completed_at else 'no'}
    print(f"  tools={len(tools)} running={len(running)}")
    for p in running[:3]:
        state = p.get("state", {})
        inp = state.get("input", {})
        target = inp.get("command") or inp.get("filePath") or inp.get("pattern") or ""
        print(f"    - {p.get('tool')}: {str(target)[:100]}")
    if completed_at:
        text = "".join(p.get("text", "") for p in parts if p.get("type") == "text")
        if text:
            print(f"  last reply: {text[:300]}")

    evidence = []
    if not running:
        evidence.append(IDLE_EVIDENCE["no_tool_running"])
    if completed_at:
        evidence.append(IDLE_EVIDENCE["last_message_done"])
    return evidence


def list_all():
    for s in get("/session?limit=40"):
        print(f"  {s.get('id')} | {s.get('title','')[:40]} | {s.get('directory','?')}")
    return 0


def main():
    if not server_alive():
        return 1
    if "--all" in sys.argv:
        return list_all()
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 1
    print(f"=== {args[0]} ===")
    evidence = inspect(args[0], args[1] if len(args) > 1 else None)
    print("  evidence:")
    for e in evidence or ["nothing notable"]:
        print(f"    - {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())