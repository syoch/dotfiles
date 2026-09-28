# agents_* tools fail for category "project"

As of 2026-09, the `agents-bridge` plugin's `agents_add` / `agents_categories` /
`agents_list` error out when asked for the project scope:
`agents_categories` → `PROJECT_SCOPE is not defined`; `agents_add category="project"`
→ `category 'project' not found`.

Workaround: create project-scope skills manually at the documented path
`<repo>/.agents/skills/<name>/SKILL.md` (flat under the project catalog root) with frontmatter:
```
---
name: <name>            # must equal the directory name
description: Use when ... (trigger keywords)
---
```
Extra files (e.g. `scripts/...`) may live alongside `SKILL.md` in the same skill dir.
User-scope categories via `agents_*` are unaffected. Re-check whether the bug is fixed
before relying on the workaround.
