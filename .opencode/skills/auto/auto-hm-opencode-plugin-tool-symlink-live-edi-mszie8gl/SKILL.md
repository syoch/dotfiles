---
name: hm-opencode-plugin-tool-symlink-live-edi
description: Use when managing opencode plugins/tools/AGENTS.md from a Nix home-manager config by replacing `install -m 0644` copies with `ln -sfn` activation symlinks for live editing without rebuild, and fixing the realpath node_modules resolution gotcha. Trigger keywords: opencode plugin not loading, custom tasks tool not recognized, tasks_list Unknown, install -m 0644 vs ln -sfn, home.activation symlink opencode, node_modules realpath resolution, symlinked plugin import @opencode-ai/plugin fails, opencode live-edit without rebuild, plugin source symlink into dotfiles repo.
---

## When to use
Use when opencode custom plugins/tools/AGENTS.md are managed by Nix home-manager activation scripts in `modules-hm/apps/opencode.nix`, and you want to switch from static `install -m 0644 ${src}` copies to out-of-store symlinks (`ln -sfn .../dotfiles/modules-hm/apps/opencode/<file>.ts ~/.config/opencode/...`) so repo edits are live without a rebuild. Also use when a symlinked plugin/tool fails at runtime with module-resolution errors.

## Procedure
1. **Replace copies with symlinks** in `home.activation.*` blocks:
   ```nix
   home.activation.opencodePlugins = mkIf (...) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
     mkdir -p "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/skills/auto"
     ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/auto-skill.ts" "$HOME/.config/opencode/plugins/auto-skill.ts"
     # ...same for tasks.ts -> tools/tasks.ts, AGENTS.md, ~/.agents -> config/agents
   '');
   ```
2. **Handle the realpath node_modules gotcha**: opencode resolves imports of symlinked sources from their REALPATH (the repo, not `~/.config/opencode`). Therefore expose the config-dir node_modules at the repo path:
   ```nix
   home.activation.opencodeNodeModules = mkIf (cfg.tasks.enable || ...) (
     lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       ln -sfn "$HOME/.config/opencode/node_modules" "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/node_modules"
     ''
   );
   ```
   Add `modules-hm/apps/opencode/node_modules` to `.gitignore` so the symlink is never tracked.
3. **Remove now-dead `let` bindings** (the `./opencode/tasks.ts` file-paths) from the module `let ... in` block.
4. **Rebuild**: `nix-instantiate --parse modules-hm/apps/opencode.nix && git add modules-hm/apps/opencode.nix && make rebuild-hm` (note: `make rebuild-hm` runs `git add .` first).

## Verification
- `for f in ~/.agents ~/.config/opencode/AGENTS.md ~/.config/opencode/plugins/*.ts ~/.config/opencode/tools/tasks.ts ~/dotfiles/modules-hm/apps/opencode/node_modules; do echo "$f -> $(readlink $f)"; done` — every managed source must be a symlink into the repo.
- Smoke-test the plugin/tool module directly: `bun -e 'const t = await import("./tasks.ts"); JSON.parse(await t.list.execute({},{sessionID:"test"}))'` from `modules-hm/apps/opencode/`.
- Run `timeout 120 opencode run "<prompt referencing the plugin>"` and confirm the plugin/tool actually fires (grep output for the tool name; a bare success with no error is NOT proof the plugin loaded — probe for its injected content).

## Pitfalls
- `make rebuild-hm` auto-stages everything; keep the tree clean first.
- A green `opencode run` does not prove the plugin loaded — verify via `--print-logs` or a prompt that requires plugin output.
- The node_modules symlink must exist AFTER `writeBoundary`; order activations correctly.
- Don't forget `.gitignore` for the repo-side node_modules symlink or it will get committed.
