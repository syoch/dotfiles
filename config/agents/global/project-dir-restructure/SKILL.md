---
name: project-dir-restructure
description: Use when restructuring a project's directory layout (moving dirs/files to a new location or to top level) and you must systematically update all stale path references in shell scripts and markdown docs so the build still works. Trigger keywords: restructure project, move directory, relocate files, reorganize layout, update path references, stale paths, tree diagram out of date, SCRIPT_DIR parent, fix ROOT_DIR, directory restructure.
---

# Project Directory Restructure — Update All Path References

## When to use

After moving directories or files to a new location (e.g. hoisting nested `build/`, `apk/`, `tools/` to the project top level), every consumer of the old paths must be updated: shell scripts, script header comments, README/guide tree diagrams, and inline markdown references. Skip nothing or the build silently breaks or docs drift.

## Procedure

1. **Move and record the new layout**
   ```sh
   mv build/build_apk.sh build/prepare_apk.sh .
   mv build/tools build/work build/keystore build/dist .
   rmdir build apk
   ls -la   # capture the new tree; you'll mirror it in docs
   ```
2. **Find every reference to the old paths** across all file types
   ```sh
   grep -rn 'build/\|apk/\|ROOT_DIR\|WORK_DIR' --include='*.sh' --include='*.py' --include='*.nix' --include='*.md' .
   ```
   Use precise patterns — bare `build/` will match build tools and build dirs everywhere.
3. **Fix script path logic** — this is the top breakage point. Scripts that assumed a parent dir (`ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"`) break when the script moves up a level. After hoisting, set `ROOT_DIR="$SCRIPT_DIR"`.
4. **Update header comments and usage lines** in the scripts (they embed old input/output paths like `build/work/base/` or `build/dist/`).
5. **Update markdown**: both inline prose paths AND the `tree diagram` blocks (`├── ...`). Diagrams are the most often missed; they must match reality exactly.
6. **Re-grep** the same patterns to confirm zero stale references remain.
7. **Verify with a clean rebuild**: delete generated dirs (e.g. `rm -rf .cache dist`) and run the actual build/CI, not just `ls`. Confirm output lands in the new location.

## Verification

- `grep -rn 'old/path' .` returns nothing.
- Scripts run from the repo root in a fresh shell.
- A clean build produces the artifact at the new path.

## Pitfalls

- Tree diagrams in docs are easy to miss — always update them in the same pass as the prose.
- Path vars computed relative to `SCRIPT_DIR` change meaning when the script's depth changes.
- A build output path is usually documented in BOTH README.md and a dedicated guide; grep for every mention.
- `grep 'build/'` matches build logs and build tool names too; anchor with quotes or the specific dir name.
- Verify by rebuilding from scratch — stale references often only break at runtime/build time, not on `ls`.
