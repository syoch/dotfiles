---
name: playwright-ab-dom-equality
description: Use when verifying a rebuilt/clone frontend renders DOM identical to an original server by extracting structured page state with Playwright page.evaluate (over connect_over_cdp to the shared chromium-cdp service) and comparing json.dumps(sort_keys=True) equality across routes enumerated from homepage anchors, plus capturing 4xx/5xx responses. Trigger keywords: A/B DOM equality, rebuilt vs original DOM parity, page.evaluate JSON diff, DOM=SAME, json.dumps sort_keys comparison, enumerate routes from homepage anchors, response status >= 400, verify frontend clone parity
---

# Playwright A/B DOM Equality Verification (rebuilt vs original)

## When to use
Use when you rebuilt/rewrote a frontend (React/SSR clone) and must prove its DOM matches the original server per route. Distinct from the sibling skill `nginx-mock-ab-diff` (which diffs console errors / requestfailed): this one asserts **structural DOM equality** via `page.evaluate` returning a serializable info dict, compared with `json.dumps(sort_keys=True)`. Works for any clone-parity task.

## Procedure

1. **Run both servers side by side** (see the A/B skill for the tmux/tasks_start + `nix develop` + PORT/ROOT_DIR pattern). Original on port A (e.g. 8090), rebuilt on port B (8091). `sleep 4`, curl both.
2. **Browser**: attach to the shared chromium-cdp service — `browser = p.chromium.connect_over_cdp("http://localhost:9222")`, fresh `context`/`page` per route, `context.close()` at end (NEVER `browser.close()`; it kills the shared systemd service). Check service first: `systemctl --user is-active chromium-cdp.service`.
3. **Enumerate real route slugs from the homepage** instead of hardcoding: evaluate `[...new Set(Array.from(document.querySelectorAll('a[href^="/video/"]')).map(a=>a.getAttribute('href')))]` (and `/image/`) on the rebuilt server, then probe `["/", "/videos", "/images", "/login", ...] + videoSlugs + imageSlugs`.
4. **Probe function** (one fresh context per route, desktop UA, dark scheme):
   - Attach `console` (type=="error") and `pageerror` listeners.
   - `page.goto(url+route, wait_until="networkidle", timeout=45000)`, `page.wait_for_timeout(1200)`, then `page.reload(networkidle)` + `wait_for_timeout(2500)` — reload catches client-render/hydration differences.
   - `page.evaluate("""() => {...}""")` returning counts + selective classNames: `document.querySelector('.menu').className`, `querySelectorAll('.videoTeaser,.imageTeaser').length`, sidebar item counts (`.likesList__item`, `.moreFromUser__item`, `.moreLikeThis__item`), `body.className`, computed `body` backgroundColor, h1 text, not-found marker classes.
   - Also attach a `response` listener collecting `(status, url)` for `status>=400`.
5. **Compare**: `same = json.dumps(o, sort_keys=True) == json.dumps(r, sort_keys=True)` for orig vs rebuilt; print `DOM=SAME|DIFF` plus the two payloads when different, and the rebuilt console/page errors.
6. **Fix, rebuild, loop**: edit source/mock (`server/lib/file.js` placeholders, JSX), rebuild `client/dist`, restart the rebuilt task, rerun — until all routes `DOM=SAME` with no 4xx responses on rebuilt.
7. **Regression**: re-run the project's route-probe / no-cors / e2e scripts against the rebuilt port with `BASE_URL=http://127.0.0.1:8091`, then kill tasks and confirm ports free (`ss -tlnp | grep -E '8090|8091'`).

## Environment
Python venv with playwright: `/tmp/opencode/pw-venv/bin/python` (recreate via `nix shell nixpkgs#python3 -c 'python3 -m venv <dir> && <dir>/bin/pip install playwright'`). CDP mode needs no CHROMIUM_PATH / LD_LIBRARY_PATH / launch args. Scripts live in `/tmp/opencode/`.

## Pitfalls
- Vary fields by route — always keep the evaluated schema identical between both servers or the count itself diverges.
- `networkidle` can hang; cap timeout. Use `page.wait_for_timeout`, never `time.sleep`.
- Restart servers after source/mock edits, or you diff stale output.
- Failures often show as 404 on rebuilt only (e.g. missing `/_files/image/large/...` placeholder route); fix the mock, not the component.
- Compare the *set* of each homepage's hrefs too — this catches wrong asset classes (e.g. image links leaking `/video/` slugs).
