---
name: opencode-plugin-isolated-smoke-test
description: Use when developing or validating an opencode TypeScript plugin in isolation: typecheck with `bun build --no-bundle`, smoke-test plugin handlers (e.g. experimental.chat.system.transform) by importing the default export and invoking it with a mock output, isolate user-scope reads via a fake HOME dir with symlinks, and clean up temp artifacts. Trigger keywords: opencode plugin, plugin handler smoke test, agents-bridge, skill frontmatter parse, bun build --no-bundle, fake HOME symlink, system prompt transform plugin.
---

Use when developing an opencode plugin written in TypeScript (system-prompt transformers, tool hooks, session-idle watchers) and you need to verify it typechecks and behaves correctly WITHOUT launching a full opencode session, especially plugins that parse markdown-table catalogs (MANIFEST.md / .agents bridges) and inject into the system prompt.

## When to use
- Editing `experimental.chat.system.transform` / tool lifecycle handlers and want a fast loop.
- Validating markdown-table parsing logic against real catalog files.

## Procedure
1. Typecheck/build the plugin (bun typechecks on build):
   `bun build --no-bundle <abs-path>/<plugin>.ts >/dev/null && echo OK`
2. Write a smoke harness under `/tmp/opencode/` that imports the plugin DEFAULT export and awaits `plugin({})` to get the handler map:
   ```ts
   import Plugin from "<abs-path>/<plugin>.ts"
   const handlers: any = await Plugin({} as any)
   const output = { system: ["existing content"] }
   await handlers["experimental.chat.system.transform"]({}, output)
   for (const s of output.system) console.log("----", s.slice(0, 2000))
   ```
   Use the default export — a named import (`import { plugin }`) fails with a confusing error.
3. For user-scope reads, isolate with a fake HOME so real `~/.agents` / `~/.config/opencode` is never touched:
   `mkdir -p /tmp/opencode/fakehome && ln -s <real-scope-dir> /tmp/opencode/fakehome/.agents && HOME=/tmp/opencode/fakehome bun run <harness>.ts`
   Grep the output for representative expected entries.
4. Iterate: edit -> `bun build --no-bundle` -> rerun harness. Rebuild after every edit; stale harness output misleads.
5. If the plugin ships via a Nix HM module, verify Nix side with `nix-instantiate --parse <module>.nix`.
6. Clean up: `rm -rf /tmp/opencode/fakehome <harness>.ts <parse-test>.ts`.

## Verification
- `bun build --no-bundle` exits 0 (also catches TS type errors).
- Harness prints the injected system block containing the expected catalog entries.
- Header-row cells are excluded; entries with missing descriptions are flagged.

## Pitfalls
- `sed -i 's|...|...|'` fails with "unknown option to 's'" when the pattern contains `|` (e.g. a TS `||` expression). Use the edit tool instead.
- Named export imports of a plugin module can throw; always import the default export.
- Don't blanket-`.toLowerCase()` parsed names — filter header cells explicitly ("name", "名前", `---`) instead, or Japanese/Latin names get mangled.
- Parse-test scripts must mirror the plugin's real table parser (same header skip + max-entry rules) or they validate the wrong thing.
