---
name: nix-playwright-e2e-setup
description: Use when running Playwright-based browser tests (Python) on this machine or setting up new E2E scripts: attach to the always-on chromium-cdp systemd service via CDP instead of launching Chromium. Trigger keywords: playwright nix, e2e python playwright, connect_over_cdp, chromium cdp 9222, chromium-cdp service, headed headless switch, browser test nix
---

# Playwright E2E on Nix via the shared chromium-cdp service

## When to use

You need to write and run Playwright (Python) E2E tests against web apps in a browser on this machine. A dedicated headless Chromium runs **always-on as a systemd user service** (`chromium-cdp.service`) exposing CDP on `http://localhost:9222`. Never launch your own Chromium — attach to the shared one. This is faster (~0.1s connect vs ~1-2s spawn) and avoids Nix libstdc++ issues entirely.

## Procedure

### 1. Confirm the shared browser is up

```bash
systemctl --user is-active chromium-cdp.service && curl -s http://localhost:9222/json/version | head -3
```

If down: `systemctl --user start chromium-cdp.service` (starts with opencode.service dependency normally).

Headed switch (shows a window under Hyprland):
```bash
systemctl --user set-environment CHROMIUM_HEADED=1 && systemctl --user restart chromium-cdp
# back to headless:
systemctl --user set-environment CHROMIUM_HEADED=0 && systemctl --user restart chromium-cdp
```

### 2. Connect from Python

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp("http://localhost:9222")
    context = browser.new_context()          # fresh, isolated context
    page = context.new_page()
    page.goto("http://localhost:10002/debug/debug/")
    ...
    context.close()   # NOT browser.close() — that kills the shared service!
```

Python venv: `/tmp/opencode/pw-venv/bin/python` has playwright installed; create fresh ones with `nix shell nixpkgs#python3 -c 'python3 -m venv <dir> && <dir>/bin/pip install playwright'`. No LD_LIBRARY_PATH / CHROMIUM_PATH / executable_path needed — CDP mode never loads a local binary.

### 3. Test checks

- DOM structure: `page.locator(...).count()`, `page.evaluate(...)` returning serializable dicts
- Overlap detection: `getBoundingClientRect()` intersection math
- Screenshot: verify size > 10KB

## Verification

Script reaches its final assertion using pages served through the shared browser; confirm no new chromium processes were spawned: `pgrep -af chromium | wc -l` stays constant before/after.

## Pitfalls

1. **Never call `browser.close()` on a CDP connection** — it terminates the shared systemd service and breaks opencode's Playwright MCP. Close only contexts/pages.
2. **cworks-style kernel apps reorder keystrokes**: send a full line via `page.keyboard.insert_text("ls")` + short sleep + `page.keyboard.press("Enter")`; per-char rapid typing can arrive out of order and crash their Lua shell (`command == nil`).
3. **`.venv` outside nix shell**: create and pip-install inside `nix shell nixpkgs#python3`, otherwise the venv Python may mismatch.
4. **Add `.venv/` to `.gitignore`** to avoid committing virtualenvs.
5. Old per-skill `chromium.launch(executable_path=...)` + libstdc++ LD_LIBRARY_PATH dance is OBSOLETE for this machine — only needed when targeting remote hosts without the service.
