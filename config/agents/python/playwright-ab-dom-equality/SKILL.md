---
name: playwright-ab-dom-equality
description: Use when verifying a rebuilt/clone frontend renders DOM identical to an original server by extracting structured page state with Playwright page.evaluate and comparing json.dumps(sort_keys=True) equality across routes enumerated from homepage anchors, plus capturing 4xx/5xx responses. Trigger keywords: A/B DOM equality, rebuilt vs original DOM parity, page.evaluate JSON diff, DOM=SAME, json.dumps sort_keys comparison, enumerate routes from homepage anchors, response status >= 400, verify frontend clone parity, Playwright parity check both servers.
---

# Playwright A/B DOM Equality Verification (rebuilt vs original)

## When to use
Use when you rebuilt/rewrote a frontend (React/SSR clone) and must prove its DOM matches the original server byte-for-byte per route. Distinct from the sibling skill `nginx-mock-backend-a-b-playwright-diff` (which diffs console errors / requestfailed): this one asserts **structural DOM equality** via `page.evaluate` returning a serializable info dict, compared with `json.dumps(sort_keys=True)`. Works for any clone-parity task, not just this project.

## Procedure

1. **Run both servers side by side** (see the A/B skill for the tmux/tasks_start + `nix develop` + PORT/ROOT_DIR pattern). Original on port A (e.g. 8090), rebuilt on port B (8091). `sleep 4`, curl both.
2. **Enumerate real route slugs from the homepage** instead of hardcoding: evaluate `[...new Set(Array.from(document.querySelectorAll('a[href^="/video/"]')).map(a=>a.getAttribute('href')))]` (and `/image/`) on the rebuilt server, then probe `["/", "/videos", "/images", "/login", ...] + videoSlugs + imageSlugs`.
3. **Probe function** (one fresh context per route, desktop UA, dark scheme):
   - Attach `console` (type=="error") and `pageerror` listeners.
   - `page.goto(url+route, wait_until="networkidle", timeout=45000)`, `page.wait_for_timeout(1200)`, then `page.reload(networkidle)` + `wait_for_timeout(2500)` — reload catches client-render/hydration differences.
   - `page.evaluate("""() => {...}""")` returning counts + selective classNames: `document.querySelector('.menu').className`, `querySelectorAll('.videoTeaser,.imageTeaser').length`, sidebar item counts (`.likesList__item`, `.moreFromUser__item`, `.moreLikeThis__item`), `body.className`, computed `body` backgroundColor, h1 text, not-found marker classes.
   - Also attach a `response` listener collecting `(status, url)` for `status>=400`.
4. **Compare**: `same = json.dumps(o, sort_keys=True) == json.dumps(r, sort_keys=True)` for orig vs rebuilt; print `DOM=SAME|DIFF` plus the two payloads when different, and the rebuilt console/page errors.
5. **Fix, rebuild, loop**: edit source/mock (`server/lib/file.js` placeholders, JSX), rebuild `client/dist`, restart the rebuilt task, rerun — until all routes `DOM=SAME` with no 4xx responses on rebuilt.
6. **Regression**: re-run the project's route-probe / no-cors / e2e scripts against the rebuilt port with `BASE_URL=http://127.0.0.1:8091`, then kill tasks and confirm ports free (`ss -tlnp | grep -E '8090|8091'`).

## Nix chromium gotcha (env)
Set `CHROMIUM_PATH` to the nix store chromium binary and `LD_LIBRARY_PATH` to its `libstdc++.so.6` dir; launch with `--no-sandbox --disable-gpu --disable-dev-shm-usage`; use the project's existing `.venv/bin/python3`. Scripts live in `/tmp/opencode/`.

## Pitfalls
- Vary fields by route — always keep the evaluated schema identical between both servers or the count itself diverges.
- `networkidle` can hang; cap timeout. Use `page.wait_for_timeout`, never `time.sleep`.
- Restart servers after source/mock edits, or you diff stale output.
- Failures often show as 404 on rebuilt only (e.g. missing `/_files/image/large/...` placeholder route); fix the mock, not the component.
- Compare the *set* of each homepage's hrefs too — this catches wrong asset classes (e.g. image links leaking `/video/` slugs).
