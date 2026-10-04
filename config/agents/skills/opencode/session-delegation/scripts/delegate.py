#!/usr/bin/env python3
"""Delegate work over the OpenCode Web API.

Create or find a session, send a prompt, and send a completion callback.

# Delegate in the background
    python3 delegate.py --worktree <worktree> --title <task name> \\
        --prompt-file <plan.md> --log <log>

# Block until the run finishes
    python3 delegate.py --worktree <worktree> --title <task name> \\
        --prompt-file <plan.md> --wait

# Target an existing session id (review requests, follow-ups)
    python3 delegate.py --session <session-id> --prompt-file <plan.md> --wait

# Send the completion callback from the DELEGATED session
    python3 delegate.py --notify-done <parent-session-id> <marker.json>
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVER = "http://localhost:12000"
PROVIDER = "opencode-go"
MODEL = "space-bunny-free"

EXIT_OK = 0
EXIT_ERROR = 1


def post(path, payload, timeout=180):
    req = urllib.request.Request(
        f"{SERVER}{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json", "accept": "application/json"},
        method="POST",
    )
    return urllib.request.urlopen(req, timeout=timeout)


def get(path, timeout=30):
    return json.loads(urllib.request.urlopen(f"{SERVER}{path}", timeout=timeout).read())


def find_session(worktree, title, poll_seconds=180):
    """Find a session by directory and title, creating it when absent."""
    existing = get(f"/session?directory={worktree}")
    for s in existing:
        if s.get("title") == title:
            return s["id"], True

    body = json.loads(post(f"/session?directory={worktree}", {"title": title}).read())
    sid = body.get("id") or body.get("info", {}).get("id")
    if not sid:
        raise RuntimeError(f"session creation failed: {body}")
    return sid, False


def resolve_session(args):
    """Use --session when given, otherwise look up by worktree and title."""
    if args.session:
        return args.session, True
    return find_session(args.worktree, args.title)


def delegate(args):
    prompt = pathlib.Path(args.prompt_file).read_text(encoding="utf-8")
    sid, reused = resolve_session(args)
    print(f"session: {sid}{'(reused)' if reused else '(new)'}")
    print(f"prompt: {len(prompt)} chars")

    started = time.time()
    payload = {
        "parts": [{"type": "text", "text": prompt}],
        "model": {"providerID": PROVIDER, "modelID": MODEL},
    }
    resp = post(f"/session/{sid}/message?directory={args.worktree}", payload, timeout=3600)
    elapsed = time.time() - started

    body = json.loads(resp.read().decode("utf-8"))
    info = body.get("info", {})
    if info.get("error"):
        print(f"ERROR: {info['error']}")
        return EXIT_ERROR
    print(f"HTTP {resp.status} / {elapsed:.1f}s")

    text = "".join(p.get("text", "") for p in body.get("parts", []) if p.get("type") == "text")
    print("---")
    print(text)
    return EXIT_OK


def notify_done(args):
    marker = json.loads(pathlib.Path(args.marker_or_none).read_text(encoding="utf-8"))
    prompt = build_done_prompt(marker)
    resp = post(f"/session/{args.notify_done}/message", {
        "parts": [{"type": "text", "text": prompt}],
        "model": {"providerID": PROVIDER, "modelID": MODEL},
    })
    body = json.loads(resp.read().decode("utf-8"))
    if body.get("info", {}).get("error"):
        print(f"ERROR: {body['info']['error']}")
        return EXIT_ERROR
    print(f"OK: {args.notify_done} notified ({len(prompt)} chars）")
    return EXIT_OK


def build_done_prompt(marker):
    lines = ["Delegated work is complete. Report below.", ""]
    for key in ("branch", "pr", "ci", "summary"):
        value = marker.get(key)
        if value:
            lines.append(f"- **{key}**: {value}")
    for section, title in (("checks", "Verified"), ("notes", "Notes")):
        items = marker.get(section)
        if items:
            lines.append("")
            lines.append(f"{title}:")
            lines.extend(f"- {item}" for item in items)
    lines.append("")
    lines.append("Review this and continue with any follow-up work needed.")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--notify-done", metavar="DEST", help="parent session id that receives the completion callback")
    parser.add_argument("marker_or_none", nargs="?", help="completion marker JSON")
    parser.add_argument("--session", help="target this session id directly")
    parser.add_argument("--worktree", help="delegated worktree, used as the directory scope")
    parser.add_argument("--title", help="session title")
    parser.add_argument("--prompt-file", help="file holding the prompt text")
    parser.add_argument("--log", help="log file for the background run")
    parser.add_argument("--wait", action="store_true", help="block until the run finishes")
    args = parser.parse_args()

    try:
        if args.notify_done:
            if not args.marker_or_none:
                parser.error("--notify-done requires a marker JSON path")
            return notify_done(args)
        if not args.prompt_file:
            parser.error("--prompt-file is required")
        if not args.session and not (args.worktree and args.title):
            parser.error("need --session, or both --worktree and --title")
        if args.wait:
            return delegate(args)
        cmd = [sys.executable, __file__, "--prompt-file", args.prompt_file, "--wait"]
        if args.session:
            cmd += ["--session", args.session]
        else:
            cmd += ["--worktree", args.worktree, "--title", args.title]
        log = open(args.log, "w", encoding="utf-8") if args.log else subprocess.DEVNULL
        subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        print(f"started in the background. log: {args.log or '(none)'}")
        return EXIT_OK
    except urllib.error.URLError as error:
        print(f"cannot reach the server: {error}")
        print(f"check opencode.service ({SERVER}）")
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())