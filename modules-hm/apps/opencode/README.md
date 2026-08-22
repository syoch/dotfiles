# opencode - managed harness: agents-bridge + global rules + catalog

This Home Manager module configures OpenCode with a deliberately small,
repo-managed harness. Skill creation is **knowledge-driven** (the global
AGENTS.md instructs the agent to skillify knowledge as it is gained), not
auto-generated from tool-call patterns.

## Feature options

| Option | Behavior |
|---|---|
| `tasks` | tmux-backed background task tool (`tasks.ts`) |
| `agents` | `.agents` catalog: symlink `~/.agents`, enable `agents_*` tools, activate agents-bridge plugin |
| `design-agent` | Consult-only primary agent for design discussions |
| `memory-tool` | Long-term memory tools at project/global scope |
| `global-agents` | Global behavioral rules file (`AGENTS.md`) |
| `orchestration` | Multi-agent orchestration plugin + leader/proposer/critic agents |

## What's enabled

| Feature | Source | Behavior |
|---|---|---|
| Agents-bridge | `agents-bridge.ts` (local plugin) | Reads the `.agents` catalog manifests and injects a compact `[agents-bridge]` block into the system prompt on every session start. |
| Global agent rules | `AGENTS.global.md` -> `~/.config/opencode/AGENTS.md` | Behavioral rules: native-first processing, lossless collection, /tmp workspace protection, `.agents` catalog management, and the knowledge-driven skillification flow (§4). |
| Design agent | `agents/design.md` -> `~/.config/opencode/agents/design.md` | Consult-only primary agent (`design`) for design discussions. Requirements elicitation, logic/architecture design, tradeoff analysis. Never implements or pushes toward implementation; records settled design decisions to `<project>/.agents/memory/`. |
| User-scope catalog | `config/agents/skills/` -> `~/.agents/skills/` | Tech-stack-categorized reusable assets (`<category>/<skill>/SKILL.md`), symlinked into the home dir. Catalog is derived dynamically from the SKILL.md tree (no MANIFEST). |
| Agents tools | `agents.ts` (tools) | `agents_categories` / `agents_list` / `agents_add` / `agents_update` / `agents_rename` / `agents_remove` / `agents_show` — manage the `.agents` catalogs by scanning the directory tree and SKILL.md frontmatter. |
| Memory tools | `memory.ts` (tools) | Durable long-term memory at project (`.agents/memory/`) and global (`~/.agents/memory/`) scope: `memory_save` (save/overwrite/append) / `memory_get` / `memory_list` / `memory_remove`. |
| Task tool | `tasks.ts` (tools) | tmux-backed background tasks. |

auto-skill / auto-notes were **removed**: repetition-based auto-generation
produced noisy, unmanaged SKILL.md files (see
`opencode-harness-review-20260819.md`). Knowledge is now captured by the
agent itself per the global AGENTS.md §4 flow.

## Agents-bridge plugin

On session start, `experimental.chat.system.transform` dynamically scans the
SKILL.md trees and reads each file's frontmatter (`name`/`description`/`args`):

- **User scope** `~/.agents/skills/<category>/<name>/SKILL.md`
- **Project scope** `<cwd>/.agents/skills/<name>/SKILL.md`

It also indexes **long-term memory topics** (`<cwd>/.agents/memory/**`,
`~/.agents/memory/**`) and injects them so agents autonomously
consult `memory_get`/`memory_save` without being told to.

It renders a compact list (`category/name (args): desc`) plus the memory
topic index, so the agent knows which reusable assets and stored context
exist and where to read the full details. No MANIFEST.md is maintained — the
directory tree + frontmatter is the single source of truth.

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

## Design agent (design)

A consult-only `primary` agent for design discussions — the first step in a
**Design → Plan → Build** workflow. Switch to it with **Tab** from anywhere;
as a primary agent it shares the current session context, so a Design→Plan
handoff within the same session needs no copying.

- **Consult only**: never implements, never pushes toward implementation
  ("if you agree, I'll implement" style output is forbidden), never writes
  code or implementation steps. Redirects implementation needs to Plan/Build.
- **Investigation**: may use `read`/`glob`/`grep`/`list` and `bash` for
  read-only investigation. Mutating commands (including ambiguous
  build/rebuild/cleanup-style scripts) are never run; side-effect-ambiguous
  commands are proposed in chat for the human to run.
- **Design record**: settled decisions are saved with the memory tool
  (`memory_save scope=project, topic=design/<topic>` ->
  `<project>/.agents/memory/design/<topic>.md`) as
  `決定事項 / 未決事項 / 残存懸念`, so design conclusions survive
  compaction/session switches.
- **Output format**: 分析 → 考慮した点（要約）→ 選択肢比較 → 推奨 →
  未決論点・確認質問, closing with explicit decisions/open points/pending
  risks.

Source: `modules-hm/apps/opencode/agents/design.md`
(symlinked to `~/.config/opencode/agents/design.md`).

## Memory tools

Durable long-term memory across sessions, distinct from the `.agents` skill
catalog (reusable procedures) — memory holds **context/knowledge** notes.

- Scopes: `project` (`<cwd>/.agents/memory/<topic>.md`, git-managed) and
  `global` (`~/.agents/memory/<topic>.md`, git-managed)
- `memory_save` — write with `mode`: `save` (new only, error if exists),
  `overwrite` (replace), `append` (extend)
- `memory_get` / `memory_list` / `memory_remove`
- Used by the design agent for design records (`design/<topic>`) and by any
  agent for lasting context.

## Global agent rules

`~/.config/opencode/AGENTS.md` is a symlink to
`modules-hm/apps/opencode/AGENTS.global.md`. Key sections:

- Command/data processing principles (native-first, lossless collection,
  no inline scripts)
- Workspace protection (intermediate files under `/tmp`)
- `.agents` catalog layout (SKILL.md tree + frontmatter as the source of truth)
- Knowledge-driven skillification: when knowledge is gained (non-obvious
  procedure, pitfalls, recovery steps, repetition), skillify it immediately
  into `<scope>/.agents/skills/<category>/<name>/SKILL.md` via the `agents_*` tools,
  then verify it is reproducible.

## Activation

All managed sources (plugins, tools, AGENTS.md) are declared as out-of-store
symlinks via `home.file` with `config.lib.file.mkOutOfStoreSymlink`, so edits
are live without a rebuild. Only imperative operations remain in activation:

- `opencodePlugins` — ensures `package.json` and `node_modules`
  (@opencode-ai/plugin) exist under `~/.config/opencode`
- `opencodeNodeModules` — symlinks the config-dir node_modules into the repo
  source dir so runtime imports of symlinked sources keep resolving

## Disable

Set per-feature in your component config:

```nix
hm-module.opencode.agents.enable = false;
```

## Files

- `modules-hm/apps/opencode.nix` - the module
- `modules-hm/apps/opencode/tasks.ts` - tmux-backed task tool
- `modules-hm/apps/opencode/agents-bridge.ts` - the catalog bridge plugin
- `modules-hm/apps/opencode/AGENTS.global.md` - global behavioral rules
- `config/agents/**` - user-scope catalog (~/.agents)
- `components/home/syoch/default.nix` - enables the harness