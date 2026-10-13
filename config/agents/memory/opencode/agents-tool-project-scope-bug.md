# agents_* tools and opencode SKILL.md requirements

## CORRECTION (2026-10-05): the project-scope bug is fixed

Earlier this note claimed the `agents-bridge` plugin's `agents_*` tools error out for the
project scope (`agents_categories` -> `PROJECT_SCOPE is not defined`;
`agents_add category="project"` -> `category 'project' not found`).

**Measured 2026-10-05: both `agents_list(category="project")` and
`agents_update(category="project", ...)` succeeded.** Treat the bug as resolved. Keep the
manual path below only as a fallback if it ever regresses:

```
<repo>/.agents/skills/<name>/SKILL.md      # flat under the project catalog root
```

Extra files (e.g. `scripts/...`) may live alongside `SKILL.md` in the same skill dir.

## SKILL.md hard requirements (from https://opencode.ai/docs/skills/)

Each `SKILL.md` must begin with YAML frontmatter:

- `name` (required): must equal the containing directory name; `^[a-z0-9]+(-[a-z0-9]+)*$`;
  1-64 chars.
- `description` (required): 1-1024 chars. Write it specifically enough that the agent
  picks the right skill.
- Only `license`, `compatibility`, `metadata` (string->string map) are additionally
  recognized. **Unknown frontmatter fields are silently ignored.**

Search locations: `.opencode/skills/`, `~/.config/opencode/skills/`, `.claude/skills/`,
`~/.claude/skills/`, `.agents/skills/`, `~/.agents/skills/` -- each as `<name>/SKILL.md`.

A skill that does not show up: check the filename is `SKILL.md` in caps, frontmatter has
`name` + `description`, names are unique across locations, and no `permission.skill` `deny`.

## Trap

A `SKILL.md` that starts with `# Title` and no frontmatter still reads like plain prose, so
it is easy to miss. Treat "first line is not `---`" as the violation signal, and verify all
skills at once:

```bash
for f in .agents/skills/*/SKILL.md; do printf '%-55s ' "$f"; head -1 "$f"; done
```

Project-level detail lives in that project's `knowledge/skill-definition-format` memory.
