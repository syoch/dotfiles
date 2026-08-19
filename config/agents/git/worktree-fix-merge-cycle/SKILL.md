---
name: worktree-fix-merge-cycle
description: Use when making a small fix or adding a regression test via a separate git worktree and merging it back to the main branch. Trigger keywords: git worktree add, fix branch, worktree already in use, branch already used by worktree, ff-only merge, worktree remove --force, git worktree prune, git branch -d, merge fix branch into main, /tmp/opencode/wt-, isolated change on branch, test in worktree before merge.
---

## git worktree fix-merge cycle

Use when you need to isolate a small fix / regression test on its own branch without disturbing the main working tree, then land it cleanly (e.g. review-fix loops, adding one test).

### Procedure
1. Create the fix branch from the current base branch and attach a worktree:
   ```bash
   git branch fix/<name> <base-branch>
   git worktree add /tmp/opencode/wt-<name> fix/<name>
   ```
2. Make your edits in the worktree directory (NOT the main checkout).
3. Verify inside the worktree before merging:
   ```bash
   cd /tmp/opencode/wt-<name>
   cargo test && cargo clippy --all-targets && cargo fmt --check
   ```
4. Commit in the worktree:
   ```bash
   git add -A && git commit -m "fix/..."
   ```
5. Merge back from the base branch with a fast-forward (keeps history linear):
   ```bash
   cd <repo>
   git checkout <base-branch>
   git merge fix/<name> --ff-only
   git log --oneline -1
   ```
6. Clean up branch + worktree metadata:
   ```bash
   git worktree remove /tmp/opencode/wt-<name> --force
   git worktree prune
   git branch -d fix/<name>
   ```

### Verification
- `git log --oneline -1` shows your commit at the tip of the base branch.
- `git branch --show-current` == base branch; `git status --short` is empty.
- `git worktree list` shows only the base branch's worktree.

### Pitfalls
- **"already used by worktree"**: `git worktree add` fails if the branch is checked out elsewhere. Run `git worktree list` to find the conflicting path and remove it first.
- **Cleanup ordering matters**: `git branch -d` fails while the worktree still references the branch. Remove the worktree first, then prune, then delete the branch.
- **`--force` on worktree remove**: only use it after confirming uncommitted changes are disposable (or after you committed them). It discards uncommitted changes silently.
- **ff-only merge failure**: if the base branch advanced past the fix branch, `--ff-only` errors. Rebase the fix branch onto the base branch (`git rebase <base-branch>`) in the worktree, re-test, then retry the merge.
- **Stale build**: run tests in the worktree, not the main checkout; cargo may pick up an unrelated build directory otherwise.
- Use a short consistent worktree path prefix (e.g. `/tmp/opencode/wt-<name>`) so `git worktree list` is easy to scan.
