---
name: deadcode-coverage-elimination
description: Use when eliminating dead code by cross-referencing coverage report missing lines with manual source inspection. Trigger keywords: dead code elimination, coverage report, unused code, coverage missing lines, --show-missing, code cleanup, delete unused functions, remove dead branches.
---

# Dead Code Elimination via Coverage Analysis

## When to use
A source file has coverage gaps (reported by `coverage report --show-missing`), and you need to determine whether each uncovered block is **dead** (safe to delete) or merely **untested** (must keep). This skill gives you the systematic procedure.

## Procedure

### 1. Baseline coverage scan
```bash
python3 -m coverage run --source=src/cm2gen -m pytest tests/ -x -q
```
Key flags:
- `--source=<package>` — scope to your package (avoids stdlib/third-party noise)
- `-x` — stop on first failure (avoid cascading noise)
- `-q` — quiet output

### 2. Identify candidates
```bash
python3 -m coverage report --show-missing
```
Look at the **Missing** column. Lines not exercised by any test are candidates.

### 3. Classify each candidate block
Read the source file around each missing line. Ask:
- Is this a **debug helper**, **deprecated path**, **safety guard** that can never fire in practice? → dead, delete.
- Is this a **core logic branch** with no test coverage? → untested, **keep**, add test.
- Is this an **`if __name__ == "__main__"`** or **REPL-only** block? → usually safe to delete from library code.

Delete dead blocks. Do NOT delete untested-but-important logic — that breaks functionality.

### 4. Verify tests still pass
```bash
python3 -m coverage run --source=src/cm2gen -m pytest tests/ -x -q
```
No test should fail. If a test fails, the deleted code was not dead — revert.

### 5. Re-run coverage report to confirm progress
```bash
python3 -m coverage report --show-missing
```
Compare before/after. Expect the Miss count to drop.

## Verification
- `pytest tests/ -x -q` passes with zero failures.
- `coverage report --show-missing` shows fewer missing lines than before (no regressions in other files).
- The diff contains no deletions of called functions, exported symbols, or API surface.

## Pitfalls
- **False sense of safety**: 100% line coverage does not mean all paths are covered. Dead code can exist in covered lines (e.g. untaken branches). Use branch coverage (`--branch`) for deeper analysis.
- **Untested ≠ dead**: A module's public API may have zero tests but is called from other modules. Grep for `import` / function references before deleting.
- **Coverage data stale**: After edits, re-run coverage. Don't rely on pre-edit report.
- **Files deleted during worktree**: If `read` errors with file-not-found, the file was deleted earlier in the workflow — check worktree state with `git status`.

## Related
- `cm2gen-code-review` — systematic code review across all source files.
- `cm2gen-multi-phase-refactoring` — large-scale coordinated changes.
