# opencode - Hermes-style memory + auto-skill

This Home Manager module configures OpenCode with two layers inspired by Nous
Research's Hermes Agent: persistent cross-session memory and automatic
SKILL.md generation.

## What's enabled

| Feature | Source | Behavior |
|---|---|---|
| Cross-session memory | `@mem0/opencode-plugin` (npm) | 9 native memory tools + lifecycle hooks. Auto-injects relevant memories on session start, per-prompt, and through compaction. |
| Auto-Skill generation | `auto-skill.ts` (local plugin) | Watches tool calls; on `session.idle` it asks an LLM subagent to write a `SKILL.md` for any detected pattern. |

## Auto-skill plugin

### Triggers (per session, in-memory only)

- **Repetition**: a tool call with the same normalized args executed 3+ times
  successfully
- **Error recovery**: a (failed -> succeeded) tool pair observed 2+ times
- Both thresholds are hard-coded in `auto-skill.ts` (`REPETITION_THRESHOLD`,
  `ERROR_RECOVERY_THRESHOLD`).

When a session ends (`session.idle`), the plugin collects the trigger
evidence, sends it to a one-shot LLM subagent (via `client.session.create` +
`session.prompt`), and asks for one of:

```
{
  "worth": boolean,
  "name": "short-hyphen-name",
  "description": "Use when ...",
  "scope": "global" | "project",
  "body": "markdown body of the skill (200-500 words)",
  "reject_reason": "..."
}
```

### Output paths

- `scope = "global"` -> `~/.config/opencode/skills/auto/auto-<name>-<ts>/SKILL.md`
- `scope = "project"` -> `<cwd>/.opencode/skills/auto/auto-<name>-<ts>/SKILL.md`

The agent itself decides global vs project. Project-isolated patterns tend
to land in the project tree; reusable procedures land globally.

### Nudge on next session

The plugin writes each successfully generated skill to
`~/.config/opencode/auto-skill-nudge.json` and injects a 1-line
`[auto-skill] ...` block via `experimental.chat.system.transform` on the next
session start, so the agent knows which auto-skills are recent and where
to read them.

## Files

- `modules-hm/apps/opencode.nix` - the module
- `modules-hm/apps/opencode/tasks.ts` - existing tmux-backed task tool
- `modules-hm/apps/opencode/auto-skill.ts` - the new plugin
- `components/home/syoch/default.nix` - enables both `tasks` and `auto-skill`

## Activation

`home.activation.opencodeAutoSkill` runs after `writeBoundary` and:

1. Creates `~/.config/opencode/plugins/` and `~/.config/opencode/skills/auto/`
2. Copies `auto-skill.ts` from the Nix store into `plugins/`
3. Ensures `package.json` declares both `@opencode-ai/plugin` and `mem0ai`
4. Runs `bun install --no-save` if either is missing

`home.activation.opencodeTools` (the existing tasks hook) runs in parallel.

## Disable

Set in your component config:

```nix
hm-module.opencode.auto-skill.enable = false;
```

The plugin is not auto-loaded, no SKILL.md gets written, and no nudge
appears in subsequent sessions.
