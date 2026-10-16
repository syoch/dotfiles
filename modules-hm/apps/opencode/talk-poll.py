#!/usr/bin/env python3
"""
User-mode NextCloud Talk receiver for opencode sessions.

The bridge receives messages through a bot webhook. Users get no webhook, so we
long-poll the spreed chat endpoint instead and feed whatever the humans wrote
into the bound opencode session.

Per-row state (cursor) lives in the talk_bind table in the opencode database, so
a restart resumes exactly where it left off instead of replaying history.
"""
import argparse
import base64
import json
import os
import sqlite3
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

DB = "/home/syoch/.local/share/opencode/opencode.db"
OC = "http://127.0.0.1:12000"
CLOUD = "https://nextcloud.syoch.org"
POLL_TIMEOUT = 20
HTTP_TIMEOUT = POLL_TIMEOUT + 25

# Prefix for prompts injected on a Talk message's behalf. plugins/talk-post.ts
# matches on it to decide whether a turn answers into Talk. Keep in sync with
# TALK_MSG_MARKER in plugins/talk-post.ts.
TALK_MSG_MARKER = "[talk-msg]"

ctx = ssl.create_default_context()


def log(msg):
    print(f"[talk-poll] {msg}", flush=True)


def bindings(db):
    con = sqlite3.connect(db, timeout=10)
    con.row_factory = sqlite3.Row
    try:
        return con.execute(
            "SELECT session_id, talk_token, uid, secret, last_message_id, "
            "description, is_leader FROM talk_bind ORDER BY talk_token"
        ).fetchall()
    finally:
        con.close()


def save_cursor(db, session_id, cursor):
    con = sqlite3.connect(db, timeout=10)
    try:
        con.execute(
            "UPDATE talk_bind SET last_message_id=?, last_polled_at=?, "
            "updated_at=? WHERE session_id=?",
            (str(cursor), int(time.time()), int(time.time()), session_id),
        )
        con.commit()
    finally:
        con.close()


def b64(s):
    return base64.b64encode(s.encode()).decode()


def ocs(path, user, secret, method="GET"):
    req = urllib.request.Request(CLOUD + path, method=method)
    req.add_header("OCS-APIRequest", "true")
    req.add_header("Authorization", "Basic " + b64(f"{user}:{secret}"))
    req.add_header("User-Agent", "Mozilla/5.0")
    return urllib.request.urlopen(
        req, timeout=HTTP_TIMEOUT, context=ctx
    )


def own_id(user, secret):
    with ocs("/ocs/v2.php/cloud/user?format=json", user, secret) as r:
        return json.loads(r.read().decode())["ocs"]["data"]["id"]


def fetch_new(token, user, secret, cursor):
    """Return (messages, new_cursor). 304 means "nothing new", which is normal."""
    path = (
        f"/ocs/v2.php/apps/spreed/api/v1/chat/{token}"
        f"?lookIntoFuture=1&limit=20&format=json&timeout={POLL_TIMEOUT}"
    )
    if cursor:
        path += f"&lastKnownMessageId={cursor}"
    try:
        with ocs(path, user, secret) as r:
            body = json.loads(r.read().decode())
            return body["ocs"]["data"], r.headers.get("X-Chat-Last-Given")
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return [], None
        raise


def session_directory(session_id):
    with urllib.request.urlopen(
        f"{OC}/session/{session_id}", timeout=15
    ) as r:
        return json.loads(r.read().decode())["directory"]


def render(msg):
    """Turn spreed's raw message template into readable text."""
    text = msg.get("message") or ""
    for key, param in (msg.get("messageParameters") or {}).items():
        if not isinstance(param, dict):
            continue
        token = "{%s}" % key
        if token not in text:
            continue
        name = param.get("name") or param.get("id") or ""
        text = text.replace(
            token, ("@" + name) if key.startswith("mention") else name
        )
    return " ".join(text.split()).strip()


def deliver(session_id, directory, author, text):
    body = {
        "delivery": "queue",
        "parts": [
            {"type": "text", "text": f"{TALK_MSG_MARKER} {text}"},
        ],
    }
    url = f"{OC}/session/{session_id}/prompt_async?directory={directory}"
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()
    log(f"delivered {author} -> {session_id}: {text[:60]!r}")


# ---- role index ----
_ROLE_CACHE = {"at": 0.0, "value": {}}
ROLE_INDEX_TTL = 300


def role_index(force=False):
    now = time.time()
    if not force and now - _ROLE_CACHE["at"] < ROLE_INDEX_TTL:
        return _ROLE_CACHE["value"]
    out = {}
    for r in bindings(DB):
        try:
            out[str(own_id(r["uid"], r["secret"]))] = r["uid"]
        except Exception as e:
            log(f"role_index: cannot resolve {r['uid']}: {e}")
    _ROLE_CACHE["value"] = out
    _ROLE_CACHE["at"] = now
    return out


def mentions_self(msg, my_uid):
    for param in (msg.get("messageParameters") or {}).values():
        if not isinstance(param, dict):
            continue
        if param.get("id") == my_uid or param.get("mention-id") == my_uid:
            return True
    return False


def should_deliver(msg, me, my_uid, is_leader, roles):
    actor = str(msg.get("actorId") or "")
    if actor == str(me):
        return False, "own message"
    if msg.get("systemMessage"):
        return False, "system notice"
    mentioned = mentions_self(msg, my_uid)
    if actor in roles:
        if not mentioned:
            return False, f"role {roles[actor]} without mention"
        return True, None
    if is_leader or mentioned:
        return True, None
    return False, "human message, not addressed to me"


def poll_once(row, directory, roles):
    me = own_id(row["uid"], row["secret"])
    my_uid = row["uid"]
    is_leader = bool(row["is_leader"])
    msgs, cursor = fetch_new(
        row["talk_token"], my_uid, row["secret"], row["last_message_id"]
    )
    acted = 0
    for m in msgs:
        ok, why = should_deliver(m, me, my_uid, is_leader, roles)
        if not ok:
            log(f"{my_uid}: skip {why}")
            continue
        body = render(m)
        if not body:
            continue
        author = m.get("actorDisplayName") or f"actor{m.get('actorId')}"
        deliver(row["session_id"], directory, author, body)
        acted += 1
    if cursor:
        save_cursor(DB, row["session_id"], cursor)
    if acted:
        log(f"{my_uid}: {acted} message(s) processed")
    return acted


def loop(row, directory):
    """Poll one binding forever, isolating its failures from the others."""
    delay = 1.0
    while True:
        try:
            roles = role_index()
            current = next(
                (r for r in bindings(DB)
                 if r["session_id"] == row["session_id"]), None)
            if current is None:
                log(f"{row['uid']}: talk_bind row vanished; stopping this poller")
                return
            # re-read cursor each pass: another process may have moved it.
            fresh = {k: current[k] for k in current.keys()}
            fresh["last_message_id"] = current_cursor(row["session_id"])
            me = own_id(current["uid"], current["secret"])
            poll_once(fresh, directory, roles)
            delay = 1.0
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                log(f"{row['uid']}: AUTH FAILED ({e.code}); retry in 60s")
                delay = 60
            else:
                log(f"{row['uid']}: HTTP {e.code}; retry in {delay:.0f}s")
                delay = min(delay * 2, 60)
        except Exception as e:
            log(f"{row['uid']}: {type(e).__name__}: {e}; retry in {delay:.0f}s")
            delay = min(delay * 2, 60)
        time.sleep(delay)


def current_cursor(session_id):
    for r in bindings(DB):
        if r["session_id"] == session_id:
            return r["last_message_id"]
    return None


def send_message(row, text):
    """Post as the bound USER, not as a bot."""
    body = json.dumps({"message": text}).encode()
    req = urllib.request.Request(
        f"{CLOUD}/ocs/v2.php/apps/spreed/api/v1/chat/{row['talk_token']}?format=json",
        data=body, method="POST",
    )
    req.add_header("OCS-APIRequest", "true")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Basic " + b64(f"{row['uid']}:{row['secret']}"))
    req.add_header("User-Agent", "Mozilla/5.0")
    with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
        payload = json.loads(r.read().decode())
    if payload["ocs"]["meta"]["statuscode"] not in (200, 201):
        raise RuntimeError(f"send failed: {payload['ocs']['meta']}")
    log(f"posted as user {row['uid']} ({len(text)} chars)")
    return payload["ocs"]["data"].get("id")


# ---- local serve endpoint ----
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _reply(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path != "/ctl/post":
            return self._reply(404, {"error": "unknown path"})
        n = int(self.headers.get("Content-Length") or 0)
        try:
            req = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._reply(400, {"error": "bad json"})
        sid, text = req.get("session_id"), (req.get("message") or "").strip()
        if not sid or not text:
            return self._reply(400, {"error": "session_id and message required"})
        rows = [r for r in bindings(DB) if r["session_id"] == sid]
        if not rows:
            return self._reply(404, {"error": "no talk_bind for this session"})
        try:
            mid = send_message(rows[0], text)
        except Exception as e:
            log(f"send_message failed: {type(e).__name__}: {e}")
            return self._reply(502, {"error": str(e)})
        self._reply(200, {"ok": True, "message_id": mid})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="one poll pass, then exit")
    ap.add_argument("--uid", action="append",
                    help="only these uids (repeatable; default: every talk_bind row)")
    ap.add_argument("--dir", help="override directory (default: per-session)")
    ap.add_argument("--serve", type=int, metavar="PORT",
                    help="also expose POST /ctl/post for the opencode tool")
    a = ap.parse_args()

    if a.serve:
        srv = HTTPServer(("127.0.0.1", a.serve), Handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        log(f"user-mode post endpoint on 127.0.0.1:{a.serve}")

    def pick():
        rows = bindings(DB)
        if a.uid:
            rows = [r for r in rows if r["uid"] in set(a.uid)]
        return rows

    if a.once:
        rows = pick()
        if not rows:
            log("no talk_bind rows; nothing to poll")
            return
        roles = role_index()
        for row in rows:
            d = a.dir or session_directory(row["session_id"])
            poll_once(row, d, roles)
        return

    rows = pick()
    if not rows:
        log("no talk_bind rows yet; polling anyway so rows added later are picked up")

    seen = set()

    def supervise():
        while True:
            for row in pick():
                key = row["session_id"]
                if key in seen:
                    continue
                seen.add(key)
                try:
                    d = a.dir or session_directory(key)
                except Exception as e:
                    log(f"{row['uid']}: cannot resolve directory ({e}); skipping")
                    seen.discard(key)
                    continue
                log(f"polling {row['uid']} -> {key} ({d})")
                threading.Thread(target=loop, args=(row, d), daemon=True).start()
            time.sleep(10)

    threading.Thread(target=supervise, daemon=True).start()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
