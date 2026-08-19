---
name: nginx-mock-ab-diff
description: Use when comparing a rebuilt/managed frontend server against the original mock/proxy server for functional parity using Playwright headless Chromium: run old and new servers side by side (different ports, mock/local vs proxy/remote BACKEND modes), script route probing and UI interactions (video card click, search fill+Enter, 404 route, requestfailed collection), diff console_errors/pageerrors/requestfailed between the two, then kill the background tmux tasks. Trigger keywords: A/B frontend comparison, rebuilt vs original parity, playwright console_errors, pageerrors, requestfailed, mock vs proxy backend, route probe, server side-by-side ports, headless chromium LD_LIBRARY_PATH nix.
---

# Playwright A/B Frontend Parity Diff (mock vs proxy / rebuilt vs original)

## When to use
Use when you rebuilt or modified a frontend/server and must confirm functional parity with the original, or when you need to compare two server modes (local mock backend vs remote proxy backend) for identical browser-visible behavior. The goal is to catch JS pageerrors, console errors, and failed network requests that only appear under real Chromium.

## Setup: run both servers side by side
Start each variant via the background task tool (`tasks_start`), one per tmux pane:
- Rebuilt/local: `nix develop -c bash -c 'cd server && ROOT_DIR=../client/dist PORT=8082 node index.js'`
- Original: `nix develop -c bash -c 'cd server && node index.js'`
- Proxy mode: `BACKEND=proxy ROOT_DIR=../client/dist PORT=8084 node index.js`
Give each a distinct name and port. `sleep 4` before probing.

## Script the probes (reusable pattern)
Write standalone Playwright scripts under /tmp/opencode/ that attach three listeners before navigation:
```python
ce, pe, rf = [], [], []
page.on("console", lambda m: ce.append(m.text) if m.type=="error" else None)
page.on("pageerror", lambda e: pe.append(str(e)))
page.on("requestfailed", lambda r: rf.append((r.url, r.failure)))
```
- Route probe: `goto` each route with `wait_until="networkidle", timeout=60000`, wait 1-2s, record status.
- Interaction probe: click first `a[href^='/video/']`, goto `/images`, fill a search `input` then `press("Enter")`, hit a nonexistent 404 route. Settings like viewport and launch args (`--no-sandbox --disable-gpu --disable-dev-shm-usage`) are repeated boilerplate.
- Print `json.dumps(..., default=str)` for stable parsing.

## Run headless Chromium (Nix gotcha)
Prefer an already-installed `chromium` on PATH. If absent, fall back to a nix shell; the critical gotcha is that headless chromium needs libstdc++ from stdenv — set:
```
LIBCPATH="$(dirname "$(find "$(nix eval --raw nixpkgs#stdenv.cc.cc.lib)/lib" -name libstdc++.so.6 | head -1)")"
export LD_LIBRARY_PATH="$LIBCPATH"
export CHROMIUM_PATH="$(command -v chromium)"
```
Reuse an existing `.venv/bin/python3` for Playwright rather than the system python. Detect PATH availability first: `if command -v chromium`.

## Verify
- Run the same script against BOTH servers (different BASE_URL) and diff console_errors, pageerrors, requestfailed hosts (use `Counter(u.split("/")[2]...)` to aggregate failed hosts).
- Clean up each probe with the original `tasks_kill` ids after each run.

## Pitfalls
- Keep each browser session fresh; stale listeners accumulate across routes.
- `wait_until="networkidle"` can hang on long-poll pages — cap with timeout.
- Aggregate failed hosts before printing, or output is noisy.
- Kill background tasks when done (`ss -tlnp | grep -E ':(PORT)'` to confirm none listening).
