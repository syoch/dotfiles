---
name: nix-playwright-e2e-setup
description: Use when setting up Playwright-based E2E tests (Python) inside a Nix shell environment. Trigger keywords: playwright nix, nix playwright setup, e2e playwright nix shell, playwright chromium nix, playwright libstdc++, LD_LIBRARY_PATH playwright, nix chromium headless, E2E test python playwright nix
---

## When to use

You need to write and run Playwright (Python) E2E tests on a Nix-based system. The bundled Chromium from `playwright install chromium` often fails in Nix due to missing shared libraries (libstdc++.so.6) or binary compatibility. This skill provides a working Nix-compatible setup.

## Procedure

### 1. Create the test script (`test-e2e.py`)

Start with the standard Playwright sync API structure, but crucially:
- Accept `CHROMIUM_PATH` from the environment (for Nixpkgs Chromium)
- Pass `executable_path` and `args=["--no-sandbox", "--disable-gpu"]` to `chromium.launch()`
- Wrap the import in a try/except that prints the actual ImportError (libstdc++ issues show as ImportError, not ModuleNotFoundError)

### 2. Create the runner script (`test-e2e.sh`)

The shell script must detect Nix and wrap execution in a `nix shell` with all required packages:

```bash
# key packages: nixpkgs#chromium nixpkgs#python3 nixpkgs#stdenv.cc.cc.lib
exec nix shell nixpkgs#chromium nixpkgs#python3 nixpkgs#stdenv.cc.cc.lib -c bash << 'EOF'
cd $(dirname "$0")
LIBCPATH=$(dirname $(find $(nix eval --raw nixpkgs#stdenv.cc.cc.lib)/lib -name "libstdc++.so.6" | head -1))
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$LIBCPATH"
export CHROMIUM_PATH=$(which chromium)
.venv/bin/python3 test-e2e.py
EOF
```

### 3. Setup command

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install playwright
playwright install chromium  # for browser binaries if needed, but we use nixpkgs chromium
```

### 4. Common test checks

- **Overlap detection**: `document.querySelectorAll('.chip, .sub')` + `getBoundingClientRect()` intersection math
- **DOM structure**: count selectors (`page.locator(...).count()`)
- **Screenshot**: verify size > 10KB
- **SVG/arrow visibility**: check `getBoundingClientRect()` dimensions and `[marker-end]` count

## Verification

Run `./test-e2e.sh` and confirm "ALL CHECKS PASSED" exit 0.

## Pitfalls

1. **libstdc++.so.6 not found**: Always include `nixpkgs#stdenv.cc.cc.lib` in `nix shell` AND export `LD_LIBRARY_PATH` pointing to its `lib/` directory. Without this, `from playwright.sync_api import sync_playwright` fails with a cryptic ImportError.
2. **Bundled Chromium broken**: In Nix, use `nixpkgs#chromium` instead of Playwright's bundled one. Pass `executable_path=$(which chromium)` to `chromium.launch()`.
3. **Path confusion in nix shell**: The `nix shell -c bash` spawns a new shell — use `exec nix shell ... -c bash -c '...'` to ensure the venv python runs inside the right environment.
4. **`.venv` outside nix shell**: Create and pip-install inside `nix shell nixpkgs#python3` or use a shebang; otherwise the venv Python may mismatch the nix Python.
5. **Add `.venv/` to `.gitignore`**: `**/.venv/` or specific path to avoid committing virtualenv.
