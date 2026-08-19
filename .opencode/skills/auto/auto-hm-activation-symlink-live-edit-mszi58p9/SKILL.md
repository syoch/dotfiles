---
name: hm-activation-symlink-live-edit
description: Use when replacing a Home Manager `home.file.\".dir\" = { source = config.lib.file.mkOutOfStoreSymlink ...; }` with an activation-time real symlink (`home.activation` + `ln -sfn` + `lib.hm.dag.entryAfter [\"writeBoundary\"]`) so edits to the repo target are reflected immediately without a rebuild. Trigger keywords: home.file mkOutOfStoreSymlink, home.activation ln -sfn, writeBoundary entryAfter, out-of-store symlink rebuild, live-editable dotfiles symlink, instant reflection without rebuild, nix-instantiate --parse, readlink ~/.agents, direct edit reflection test.
---

# Home Manager activation-time symlink for live-editable dotfiles

## When to use

Use this pattern when a dotfiles directory (e.g. `~/.agents` -> `~/dotfiles/config/agents`) should be a real symlink that reflects edits to the repo *immediately*, without a `nixos-rebuild` / `home-manager switch`. `home.file."<name>"` with `mkOutOfStoreSymlink` creates the link only at activation time too, but switching to an explicit `home.activation` hook is the reliable way to control DAG ordering and behavior for repo-managed catalogs.

Applies to this repo's Home Manager modules (`modules-hm/`).

## Procedure

1. Replace the `home.file` block:
   ```nix
   # before
   home.file.".agents" = mkIf cfg.enable {
     source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/agents";
   };
   # after
   home.activation.opencodeAgentsLink = mkIf cfg.agents-catalog.enable (
     lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       ln -sfn "${config.home.homeDirectory}/dotfiles/config/agents" "$HOME/.agents"
     ''
   );
   ```
   Note: the option name uses the `cfg.<feature>.enable` sub-option, and the hook name must be a unique valid Nix identifier.

2. Fast parse check before the slow rebuild:
   ```bash
   nix-instantiate --parse modules-hm/apps/opencode.nix >/dev/null && echo "parse OK"
   ```

3. Rebuild Home Manager (no sudo): `git add . && make rebuild-hm`.

4. Verify the link and live-edit reflection:
   ```bash
   ls -la ~/.agents && readlink ~/.agents
   echo "# テスト追記" >> ~/.agents/MANIFEST.md && tail -3 ~/dotfiles/config/agents/MANIFEST.md
   ```
   The appended line must appear in the repo file immediately (proof the link is a real symlink).

5. Clean up test artifacts and docs:
   ```bash
   git restore config/agents/MANIFEST.md   # undo the test append
   git status --short
   ```
   Update the module README (`modules-hm/apps/opencode/README.md`) to mention the new activation hook.

## Verification

- `readlink ~/.agents` prints the repo path (not a Nix store path).
- Appending to `~/.agents/MANIFEST.md` shows up in `~/dotfiles/config/agents/MANIFEST.md` with no rebuild.
- `git restore` cleanly reverts the test line; final `git status` shows only intended A/M files.

## Pitfalls

- `home.activation` entries need `lib.hm.dag.entryAfter [ "writeBoundary" ]` so the link is created after files are written.
- `ln -sfn` (not `ln -s`) so re-activation idempotently replaces an existing link.
- Run `git restore` (or `git checkout --`) on the MANIFEST before staging, otherwise the test line gets committed.
- Full `nixos-rebuild switch` is unnecessary; `make rebuild-hm` suffices for a Home Manager-only change.
