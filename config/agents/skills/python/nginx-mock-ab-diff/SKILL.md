---
name: nginx-mock-ab-diff
description: Use when comparing a rebuilt/managed frontend server against the original mock/proxy server for functional parity using Playwright over the shared chromium-cdp service (connect_over_cdp): run old and new servers side by side (different ports, mock/local vs proxy/remote BACKEND modes), script route probing and UI interactions (video card click, search fill+Enter, 404 route, requestfailed collection), diff console_errors/pageerrors/requestfailed between the two, then kill the background tmux tasks. Trigger keywords: A/B frontend comparison, rebuilt vs original parity, playwright console_errors, pageerrors, requestfailed, mock vs proxy backend, connect_over_cdp 9222, chromium-cdp service, route probe
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

## Browser: attach to the shared chromium-cdp service
Do NOT launch Chromium. Attach once per script run:
```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp("http://localhost:9222")
    context = browser.new_context()
    page = context.new_page()
    ...
    context.close()  # never browser.close() — it kills the shared service
```
Confirm the service first: `systemctl --user is-active chromium-cdp.service`. Headed switch if you need to watch it: `systemctl --user set-environment CHROMIUM_HEADED=1 && systemctl --user restart chromium-cdp` (back: `...CHROMIUM_HEADED=0...`). No LD_LIBRARY_PATH / CHROMIUM_PATH / executable_path needed in CDP mode.

## Script the probes (reusable pattern)
Write standalone Playwright scripts under /tmp/opencode/ that attach three listeners before navigation:
```python
ce, pe, rf = [], [], []
page.on("console", lambda m: ce.append(m.text) if m.type=="error" else None)
page.on("pageerror", lambda e: pe.append(str(e)))
page.on("requestfailed", lambda r: rf.append((r.url, r.failure)))
```
- Route probe: `goto` each route with `wait_until="networkidle", timeout=60000`, wait 1-2s, record status.
- Interaction probe: click first `a[href^='/video/']`, goto `/images`, fill a search `input` then `press("Enter")`, hit a nonexistent 404 route.
- Print `json.dumps(..., default=str)` for stable parsing.

## Verify
- Run the same script against BOTH servers (different BASE_URL) and diff console_errors, pageerrors, requestfailed hosts (use `Counter(u.split("/")[2]...)` to aggregate failed hosts).
- Clean up each probe with the original `tasks_kill` ids after each run.

## Pitfalls
- Keep each browser session fresh; stale listeners accumulate across routes.
- `wait_until="networkidle"` can hang on long-poll pages — cap with timeout.
- Aggregate failed hosts before printing, or output is noisy.
- Kill background tasks when done (`ss -tlnp | grep -E ':(PORT)'` to confirm none listening).
- Python venv with playwright: `/tmp/opencode/pw-venv/bin/python`; recreate via `nix shell nixpkgs#python3 -c 'python3 -m venv <dir> && <dir>/bin/pip install playwright'`.
