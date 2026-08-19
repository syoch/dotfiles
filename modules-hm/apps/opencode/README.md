# opencode - managed harness: agents-bridge + global rules + catalog

This Home Manager module configures OpenCode with a deliberately small,
repo-managed harness. Skill creation is **knowledge-driven** (the global
AGENTS.md instructs the agent to skillify knowledge as it is gained), not
auto-generated from tool-call patterns.

## What's enabled

| Feature | Source | Behavior |
|---|---|---|
| Agents-bridge | `agents-bridge.ts` (local plugin) | Reads the `.agents` catalog manifests and injects a compact `[agents-bridge]` block into the system prompt on every session start. |
| Global agent rules | `AGENTS.global.md` -> `~/.config/opencode/AGENTS.md` | Behavioral rules: native-first processing, lossless collection, /tmp workspace protection, `.agents` catalog management, and the knowledge-driven skillification flow (§4). |
| User-scope catalog | `config/agents/` -> `~/.agents` | Tech-stack-categorized reusable assets (`<category>/<skill>/SKILL.md`), symlinked into the home dir. Catalog is derived dynamically from the SKILL.md tree (no MANIFEST). |
| Agents tools | `agents.ts` (tools) | `agents_categories` / `agents_list` / `agents_add` / `agents_update` / `agents_rename` / `agents_remove` / `agents_show` — manage the `.agents` catalogs by scanning the directory tree and SKILL.md frontmatter. |
| Task tool | `tasks.ts` (tools) | tmux-backed background tasks. |

auto-skill / auto-notes were **removed**: repetition-based auto-generation
produced noisy, unmanaged SKILL.md files (see
`opencode-harness-review-20260819.md`). Knowledge is now captured by the
agent itself per the global AGENTS.md §4 flow.

## Agents-bridge plugin

On session start, `experimental.chat.system.transform` dynamically scans the
SKILL.md trees and reads each file's frontmatter (`name`/`description`/`args`):

- **User scope** `~/.agents/<category>/<name>/SKILL.md`
- **Project scope** `<cwd>/.agents/<name>/SKILL.md`

It renders a compact list (`category/name (args): desc`), so the agent knows
which reusable assets exist and where to read the full details (the co-located
`SKILL.md`). No MANIFEST.md is maintained — the directory tree + frontmatter
is the single source of truth.

## Agents tools

`agents_*` tools manage the catalogs by operating on the SKILL.md tree
(never editing a MANIFEST):

- `agents_categories` — list valid categories (`project` = project root, plus
  existing user-scope categories)
- `agents_list` — list entries (optionally filtered by category)
- `agents_add` — create a skill (`SKILL.md` with generated frontmatter);
  rejects unknown categories; `force=true` overwrites
- `agents_update` — replace description/args/body
- `agents_rename` — rename/move a skill to another category (incl. `project`)
- `agents_remove` — delete a skill (requires `force=true`)
- `agents_show` — read a skill's full content

New categories are **not** auto-created by the tools (unknown categories are
rejected); create them with the Shell tool when the user requests it.

## Global agent rules

`~/.config/opencode/AGENTS.md` is a symlink to
`modules-hm/apps/opencode/AGENTS.global.md`. Key sections:

- Command/data processing principles (native-first, lossless collection,
  no inline scripts)
- Workspace protection (intermediate files under `/tmp`)
- `.agents` catalog layout (SKILL.md tree + frontmatter as the source of truth)
- Knowledge-driven skillification: when knowledge is gained (non-obvious
  procedure, pitfalls, recovery steps, repetition), skillify it immediately
  into `<scope>/.agents/<category>/<name>/SKILL.md` via the `agents_*` tools,
  then verify it is reproducible.

## Activation

All managed sources (plugins, tools, AGENTS.md) are out-of-store symlinks
into `~/dotfiles/modules-hm/apps/opencode/`, so edits are live without a
rebuild. Activations:

- `opencodePlugins` — symlinks `agents-bridge.ts`, ensures `package.json` and
  `node_modules` (@opencode-ai/plugin) exist under `~/.config/opencode`
- `opencodeTools` — symlinks `tasks.ts`
- `opencodeAgentsTool` — symlinks `agents.ts`
- `opencodeGlobalAgents` — symlinks `AGENTS.md`
- `opencodeAgentsLink` — symlinks `~/.agents -> ~/dotfiles/config/agents`
- `opencodeNodeModules` — symlinks the config-dir node_modules into the repo
  source dir so runtime imports of symlinked sources keep resolving

## Disable

Set per-feature in your component config:

```nix
hm-module.opencode.agents-bridge.enable = false;
```

## Files

- `modules-hm/apps/opencode.nix` - the module
- `modules-hm/apps/opencode/tasks.ts` - tmux-backed task tool
- `modules-hm/apps/opencode/agents-bridge.ts` - the catalog bridge plugin
- `modules-hm/apps/opencode/AGENTS.global.md` - global behavioral rules
- `config/agents/**` - user-scope catalog (~/.agents)
- `components/home/syoch/default.nix` - enables the harness