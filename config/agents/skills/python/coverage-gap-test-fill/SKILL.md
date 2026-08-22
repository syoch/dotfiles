---
name: coverage-gap-test-fill
description: Use when you need to fill Python test coverage gaps by iteratively running coverage reports, identifying uncovered lines, and writing targeted test cases. Trigger keywords: coverage run, coverage report --show-missing, missing coverage, increase coverage, test gap, uncovered lines, pytest coverage, code coverage improvement, branch coverage.
---

## Coverage Gap Test Fill

Systematic procedure to identify and write tests for uncovered lines in a Python project.

### When to use
- Coverage report shows <100% on key modules
- You need to methodically close coverage gaps
- You're adding tests for a recently refactored module

### Procedure

1. **Measure baseline** — Run coverage with source filter:
   ```bash
   python3 -m coverage run --source=src/my_pkg -m pytest tests/ -x -q
   python3 -m coverage report --show-missing | grep "src/my_pkg/(module)"
   ```

2. **Identify gaps** — Note the specific missing line numbers.

3. **Read source** — Read the uncovered lines in context to understand what logic path isn't tested:
   - Error branches (early returns, validation failures)
   - Edge cases (empty inputs, boundary values)
   - Optional features (debug flags, alternative strategies)

4. **Write targeted test** — Add to the appropriate test file:
   - Use the module's convention (unittest class or standalone functions)
   - Each test exercises exactly one uncovered path
   - Include type annotations matching project style

5. **Verify** — Rerun coverage and confirm lines are now hit:
   ```bash
   rm -f .coverage && python3 -m coverage run --source=src/my_pkg -m pytest tests/ -x -q
   python3 -m coverage report --show-missing
   ```

6. **Iterate** — Repeat steps 2-5 until target module reaches desired coverage.

### Pitfalls
- `rm -f .coverage` before each run — stale data doubles line counts
- Worktree/tmp dirs: ensure you're running from the correct directory
- Nix shell: `coverage` may not be in the environment; install with pip or use `nix develop -c python3 -m coverage ...`
- Pytest collection warnings on AST classes are harmless; ignore
- Filter coverage report with `grep` to focus on one module at a time
- For `assert` with `in`, write test expectations that match actual format (e.g., `",10?"` not `",10;"`) — inspect the actual output first with a debug print
