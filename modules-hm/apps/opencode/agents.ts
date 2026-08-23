import { tool } from "@opencode-ai/plugin"
import { readFile, readdir, mkdir, writeFile, rm, rename } from "fs/promises"
import { join, resolve } from "path"
import { existsSync } from "fs"

const HOME = process.env.HOME ?? "~"
const USER_SCOPE = resolve(join(HOME, ".agents", "skills"))

// Project scope must come from the tool context (per-session worktree), NOT
// process.cwd(): custom tools run in the opencode server process whose cwd
// is the server's start dir (e.g. $HOME for the systemd webui unit).
function projectScope(ctx: { directory?: string; worktree?: string }): string {
  const root = ctx?.worktree || ctx?.directory || process.cwd()
  return resolve(join(root, ".agents", "skills"))
}

const NAME_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/
const CAT_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

type Frontmatter = { name: string; description: string; args: string }

function parseFrontmatter(md: string): Frontmatter {
  const out: Frontmatter = { name: "", description: "", args: "" }
  const m = /^---\n([\s\S]*?)\n---/.exec(md)
  if (!m) return out
  let activeKey: keyof Frontmatter | null = null
  for (const rawLine of m[1].split("\n")) {
    const line = rawLine.trimEnd()
    const kv = /^([a-zA-Z_][\w-]*):\s*(.*)$/.exec(line)
    if (kv) {
      const key = kv[1] as keyof Frontmatter
      if (key in out) {
        out[key] = kv[2].trim()
        activeKey = key
        continue
      }
      activeKey = null
    } else if (activeKey && line.startsWith(" ") && out[activeKey]) {
      out[activeKey] += " " + line.trim()
    }
  }
  return out
}

function splitFrontmatterAndBody(md: string): { fm: Frontmatter; body: string } {
  const m = /^---\n([\s\S]*?)\n---\n?\n?([\s\S]*)$/.exec(md)
  if (!m) return { fm: { name: "", description: "", args: "" }, body: md }
  let frontmatter: Record<string, string> = {}
  for (const rawLine of m[1].split("\n")) {
    const kv = /^([a-zA-Z_][\w-]*):\s*(.*)$/.exec(rawLine)
    if (kv) frontmatter[kv[1]] = kv[2].trim()
  }
  return {
    fm: { name: frontmatter.name ?? "", description: frontmatter.description ?? "", args: frontmatter.args ?? "" },
    body: m[2].trim(),
  }
}

function renderFrontmatter(name: string, description: string, args: string): string {
  const out = [`---`, `name: ${name}`, `description: ${description.replace(/\n/g, " ")}`]
  if (args) out.push(`args: ${args.replace(/\n/g, " ")}`)
  out.push(`---`, ``)
  return out.join("\n")
}

function resolveBase(category: string, ctx: { directory?: string; worktree?: string }): { base: string; category: string } {
  if (category === "project") {
    return { base: projectScope(ctx), category: "project" }
  }
  if (!CAT_RE.test(category)) {
    throw new Error(`invalid category: ${category} (must match ${CAT_RE})`)
  }
  return { base: resolve(USER_SCOPE, category), category }
}

function assertInside(base: string, target: string) {
  const rBase = resolve(base)
  const rTarget = resolve(target)
  if (!(rTarget === rBase || rTarget.startsWith(rBase + "/"))) {
    throw new Error(`path escapes base: ${rTarget}`)
  }
}

async function listUserCategories(): Promise<string[]> {
  try {
    const dirs = await readdir(USER_SCOPE, { withFileTypes: true })
    return dirs
      .filter((d) => d.isDirectory() && !d.name.startsWith(".") && CAT_RE.test(d.name))
      .map((d) => d.name)
      .sort()
  } catch {
    return []
  }
}

function hasProjectScope(): boolean {
  return existsSync(PROJECT_SCOPE)
}

async function scanSkills(base: string): Promise<Array<{ name: string; description: string; args: string }>> {
  const out: Array<{ name: string; description: string; args: string }> = []
  let dirs: string[]
  try {
    dirs = (await readdir(base, { withFileTypes: true }))
      .filter((d) => d.isDirectory() && !d.name.startsWith(".") && NAME_RE.test(d.name))
      .map((d) => d.name)
      .sort()
  } catch {
    return out
  }
  for (const dir of dirs) {
    const file = join(base, dir, "SKILL.md")
    if (!existsSync(file)) continue
    try {
      const fm = parseFrontmatter(await readFile(file, "utf8"))
      out.push({ name: fm.name || dir, description: fm.description, args: fm.args })
    } catch {}
  }
  return out
}

async function readSkill(base: string, name: string) {
  if (!NAME_RE.test(name)) throw new Error(`invalid name: ${name} (must match ${NAME_RE})`)
  const file = join(base, name, "SKILL.md")
  assertInside(base, file)
  if (!existsSync(file)) throw new Error(`not found: ${name}`)
  return { file, md: await readFile(file, "utf8") }
}

export const categories = tool({
  description:
    "List the available .agents catalog categories. 'project' = project-scope catalog (<cwd>/.agents, flat); other values are user-scope categories under ~/.agents. Category 'project' is always the flat project root.",
  args: {},
  async execute() {
    const userCats = await listUserCategories()
    const project = hasProjectScope() ? ["project"] : []
    return JSON.stringify({ scopes: { user: userCats, project: project ? ["project"] : [] }, categories: [...project, ...userCats] })
  },
})

export const list = tool({
  description: "List .agents catalog entries (skills with their descriptions). Optionally filter by category.",
  args: {
    category: tool.schema.string().optional().describe("Filter by category (e.g. 'nix') or 'project' for project scope"),
  },
  async execute(args, ctx) {
    const category = args.category as string | undefined
    let rows: Array<{ category: string; name: string; description: string; args: string }> = []

    if (category) {
      const { base, category: c } = resolveBase(category, ctx)
      if (!existsSync(base)) {
        return JSON.stringify({ status: "empty", category, entries: [] })
      }
      for (const e of await scanSkills(base)) {
        rows.push({ category: c, name: e.name, description: e.description, args: e.args })
      }
    } else {
      for (const c of await listUserCategories()) {
        for (const e of await scanSkills(join(USER_SCOPE, c))) {
          rows.push({ category: c, name: e.name, description: e.description, args: e.args })
        }
      }
      if (hasProjectScope()) {
        for (const e of await scanSkills(PROJECT_SCOPE)) {
          rows.push({ category: "project", name: e.name, description: e.description, args: e.args })
        }
      }
    }

    return JSON.stringify({ status: "ok", count: rows.length, entries: rows }, null, 2)
  },
})

export const add = tool({
  description:
    "Add a new skill to the .agents catalog: creates <category>/<name>/SKILL.md with frontmatter (name, description, args). Rejects unknown categories (run agents_categories). Use force=true to overwrite an existing skill.",
  args: {
    category: tool.schema.string().describe("Category: 'project' or an existing user-scope category (see agents_categories)"),
    name: tool.schema.string().describe("Skill name (lowercase alphanumeric with single hyphens)"),
    description: tool.schema.string().describe("Short description; ideally each sentence starting with 'Use when'. Include trigger keywords."),
    body: tool.schema.string().describe("Markdown body: when to use, procedure (steps/commands), verification, pitfalls"),
    args: tool.schema.string().optional().describe("Optional usage arguments, e.g. '<file> <out>'"),
    force: tool.schema.boolean().optional().describe("Overwrite an existing skill if true (default false)"),
  },
  async execute(args, ctx) {
    const { category: categoryArg, name, description, body, args: usageArgs, force } = args
    if (!NAME_RE.test(name)) {
      return JSON.stringify({ status: "error", message: `invalid name: ${name} (must match ${NAME_RE})` })
    }
    if (!description || !description.trim()) {
      return JSON.stringify({ status: "error", message: "description is required" })
    }
    if (!body || !body.trim()) {
      return JSON.stringify({ status: "error", message: "body is required" })
    }

    let base: string
    try {
      base = resolveBase(categoryArg as string, ctx).base
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    if (!existsSync(base)) {
      return JSON.stringify({
        status: "error",
        message: `category '${categoryArg}' not found. Run agents_categories for valid categories. Create new categories manually when the user requests it.`,
      })
    }

    const dir = join(base, name)
    const file = join(dir, "SKILL.md")
    assertInside(base, dir)
    if (existsSync(file) && !force) {
      return JSON.stringify({ status: "error", message: `skill '${name}' already exists in '${categoryArg}'. Pass force=true to overwrite.` })
    }
    try {
      await mkdir(dir, { recursive: true })
      await writeFile(file, renderFrontmatter(name, description, (usageArgs as string) ?? "") + "\n" + body.trim() + "\n")
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    return JSON.stringify({ status: "ok", category: categoryArg, name, path: file })
  },
})

export const update = tool({
  description: "Update an existing .agents skill: replace description/args (frontmatter) and/or body.",
  args: {
    category: tool.schema.string().describe("Category: 'project' or an existing user-scope category"),
    name: tool.schema.string().describe("Skill name to update"),
    description: tool.schema.string().optional().describe("New description (frontmatter)"),
    body: tool.schema.string().optional().describe("New markdown body"),
    args: tool.schema.string().optional().describe("New args (frontmatter); empty string clears it"),
  },
  async execute(args, ctx) {
    const { category: categoryArg, name, description, body, args: usageArgs } = args
    let base: string
    try {
      base = resolveBase(categoryArg as string, ctx).base
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    try {
      const { file, md } = await readSkill(base, name)
      const { fm, body: oldBody } = splitFrontmatterAndBody(md)
      const newFm = {
        name: fm.name || name,
        description: description !== undefined ? (description as string) : fm.description,
        args: usageArgs !== undefined ? (usageArgs as string) : fm.args,
      }
      const newBody = body !== undefined ? (body as string).trim() : oldBody
      await writeFile(file, renderFrontmatter(newFm.name, newFm.description, newFm.args) + "\n" + newBody + "\n")
      return JSON.stringify({ status: "ok", category: categoryArg, name, path: file })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})

export const rename = tool({
  description:
    "Rename or move a .agents skill: change its name and/or move it to another category (including 'project'). Updates the directory and frontmatter name.",
  args: {
    category: tool.schema.string().describe("Current category: 'project' or a user-scope category"),
    name: tool.schema.string().describe("Current skill name"),
    newName: tool.schema.string().optional().describe("New skill name"),
    newCategory: tool.schema.string().optional().describe("Target category ('project' or a user-scope category); defaults to current"),
  },
  async execute(args, ctx) {
    const { category: categoryArg, name, newName, newCategory } = args
    let srcBase: string
    let dstBase: string
    try {
      srcBase = resolveBase(categoryArg as string, ctx).base
      dstBase = resolveBase((newCategory as string) ?? (categoryArg as string), ctx).base
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    const dst = (newName as string | undefined) ?? name
    if (!NAME_RE.test(dst)) {
      return JSON.stringify({ status: "error", message: `invalid new name: ${dst} (must match ${NAME_RE})` })
    }
    try {
      const srcDir = join(srcBase, name)
      const dstDir = join(dstBase, dst)
      assertInside(srcBase, srcDir)
      assertInside(dstBase, dstDir)
      if (!existsSync(srcDir)) throw new Error(`not found: ${categoryArg}/${name}`)
      if (existsSync(dstDir) && resolve(srcDir) !== resolve(dstDir)) {
        throw new Error(`destination already exists: ${newCategory ?? categoryArg}/${dst}`)
      }
      await mkdir(dstBase, { recursive: true })
      await rename(srcDir, dstDir)
      const file = join(dstDir, "SKILL.md")
      if (existsSync(file)) {
        const { fm, body } = splitFrontmatterAndBody(await readFile(file, "utf8"))
        await writeFile(file, renderFrontmatter(dst, fm.description, fm.args) + "\n" + body + "\n")
      }
      return JSON.stringify({ status: "ok", from: `${categoryArg}/${name}`, to: `${newCategory ?? categoryArg}/${dst}`, path: dstDir })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})

export const remove = tool({
  description: "Remove a .agents skill (deletes its directory). force must be true.",
  args: {
    category: tool.schema.string().describe("Category: 'project' or a user-scope category"),
    name: tool.schema.string().describe("Skill name to remove"),
    force: tool.schema.boolean().describe("Must be true to delete"),
  },
  async execute(args, ctx) {
    const { category: categoryArg, name, force } = args
    if (!force) {
      return JSON.stringify({ status: "error", message: "refusing to delete: pass force=true to remove the skill and its directory" })
    }
    let base: string
    try {
      base = resolveBase(categoryArg as string, ctx).base
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    const dir = join(base, name)
    try {
      assertInside(base, dir)
      if (!existsSync(dir)) throw new Error(`not found: ${categoryArg}/${name}`)
      await rm(dir, { recursive: true, force: true })
      return JSON.stringify({ status: "ok", removed: `${categoryArg}/${name}` })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})

export const show = tool({
  description: "Show the full content of a .agents skill (SKILL.md).",
  args: {
    category: tool.schema.string().describe("Category: 'project' or a user-scope category"),
    name: tool.schema.string().describe("Skill name"),
  },
  async execute(args, ctx) {
    const { category: categoryArg, name } = args
    let base: string
    try {
      base = resolveBase(categoryArg as string, ctx).base
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    try {
      const { file, md } = await readSkill(base, name)
      return JSON.stringify({ status: "ok", path: file, content: md })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})