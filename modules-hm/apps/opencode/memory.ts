import { tool } from "@opencode-ai/plugin"
import { mkdir, readFile, readdir, writeFile, rm, stat } from "fs/promises"
import { join, resolve, dirname } from "path"
import { existsSync } from "fs"

const HOME = process.env.HOME ?? "~"
const PROJECT_MEMORY = resolve(join(process.cwd(), ".agent", "memory"))
const GLOBAL_MEMORY = resolve(join(HOME, ".config", "opencode", "memory"))
const STALE_DAYS = 7

function ageDaysOf(mtimeMs: number): number {
  return Math.max(0, Math.floor((Date.now() - mtimeMs) / 86400000))
}

async function ageDaysOfFile(file: string): Promise<number> {
  try {
    return ageDaysOf((await stat(file)).mtimeMs)
  } catch {
    return -1
  }
}

const TOPIC_RE = /^[a-z0-9][a-z0-9/-]*$/
type Scope = "project" | "global"

function resolveBase(scope: string): string {
  if (scope === "project") return PROJECT_MEMORY
  if (scope === "global") return GLOBAL_MEMORY
  throw new Error(`invalid scope: ${scope} (must be 'project' or 'global')`)
}

function resolveTopicFile(base: string, topic: string): { file: string; rel: string } {
  if (!TOPIC_RE.test(topic)) throw new Error(`invalid topic: ${topic} (must match ${TOPIC_RE})`)
  const file = resolve(join(base, `${topic}.md`))
  const rBase = resolve(base)
  if (!file.startsWith(rBase + "/")) throw new Error(`topic escapes memory base: ${topic}`)
  return { file, rel: `${topic}.md` }
}

async function ensureBase(base: string) {
  await mkdir(base, { recursive: true })
}

export const save = tool({
  description:
    "Save a long-term memory note at project (.agent/memory/) or global (~/.config/opencode/memory/) scope. mode: 'save' creates only if the topic does not exist (error if it does), 'overwrite' replaces existing (or creates), 'append' appends to the end (or creates).",
  args: {
    scope: tool.schema.string().describe("'project' or 'global'"),
    topic: tool.schema.string().describe("Topic name (lowercase alphanumeric, '/' allowed for namespacing, e.g. design/agent)"),
    content: tool.schema.string().describe("Memory content (markdown)"),
    mode: tool.schema.string().describe("'save' | 'overwrite' | 'append'"),
  },
  async execute(args) {
    const { scope, topic, content, mode } = args
    if (mode !== "save" && mode !== "overwrite" && mode !== "append") {
      return JSON.stringify({ status: "error", message: `invalid mode: ${mode} (must be save|overwrite|append)` })
    }
    let base: string
    let file: string
    try {
      base = resolveBase(scope as string)
      ;({ file } = resolveTopicFile(base, topic as string))
      await ensureBase(base)
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    try {
      const exists = existsSync(file)
      if (mode === "save" && exists) {
        return JSON.stringify({
          status: "error",
          message: `topic '${topic}' already exists at ${scope} scope. Use mode 'overwrite' to replace or 'append' to extend.`,
        })
      }
      await mkdir(dirname(file), { recursive: true })
      if (mode === "append" && exists) {
        const prev = await readFile(file, "utf8")
        await writeFile(file, (prev.endsWith("\n") ? prev : prev + "\n") + "\n" + content.trim() + "\n")
      } else {
        await writeFile(file, content.trim() + "\n", { flag: "w" })
      }
      return JSON.stringify({ status: "ok", scope, topic, mode, path: file })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})

export const get = tool({
  description: "Read a long-term memory note from project or global scope.",
  args: {
    scope: tool.schema.string().describe("'project' or 'global'"),
    topic: tool.schema.string().describe("Topic name"),
  },
  async execute(args) {
    const { scope, topic } = args
    let file: string
    try {
      file = resolveTopicFile(resolveBase(scope as string), topic as string).file
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    if (!existsSync(file)) {
      return JSON.stringify({ status: "error", message: `not found: ${scope}/${topic}` })
    }
    try {
      const ageDays = await ageDaysOfFile(file)
      const stale = ageDays >= STALE_DAYS
      return JSON.stringify({
        status: "ok",
        scope,
        topic,
        content: await readFile(file, "utf8"),
        ageDays,
        ...(stale
          ? { note: `This note is ${ageDays} days old - verify it is still accurate before relying on it.` }
          : {}),
      })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})

async function walkMds(dir: string, prefix: string, acc: string[]): Promise<void> {
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const e of entries) {
    if (e.name.startsWith(".")) continue
    const p = join(dir, e.name)
    if (e.isDirectory()) {
      await walkMds(p, prefix, acc)
    } else if (e.name.endsWith(".md")) {
      const rel = p.slice(prefix.length).replace(/\.md$/, "")
      acc.push(rel.replace(/^\//, ""))
    }
  }
}

export const list = tool({
  description: "List long-term memory topics at project or global scope, optionally filtered by prefix.",
  args: {
    scope: tool.schema.string().describe("'project' or 'global'"),
    prefix: tool.schema.string().optional().describe("Topic prefix filter (e.g. 'design')"),
  },
  async execute(args) {
    const { scope, prefix } = args
    let base: string
    try {
      base = resolveBase(scope as string)
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    const acc: string[] = []
    await walkMds(base, base, acc)
    acc.sort()
    const p = (prefix as string | undefined)?.trim()
    const topics = p ? acc.filter((t) => t.startsWith(p)) : acc
    const ages: Record<string, number> = {}
    for (const t of topics) {
      ages[t] = await ageDaysOfFile(join(base, `${t}.md`))
    }
    return JSON.stringify({ status: "ok", scope, count: topics.length, topics, ages })
  },
})

export const find = tool({
  description:
    "Search memory note contents by keywords (OR match, case-insensitive) at project or global scope. Use BEFORE memory_save to detect existing topics that already cover the same knowledge; if a match covers the new note, append/overwrite it instead of creating a duplicate topic.",
  args: {
    scope: tool.schema.string().describe("'project' or 'global'"),
    keywords: tool.schema
      .array(tool.schema.string())
      .describe("Keywords; a topic matches if ANY keyword occurs in its content"),
  },
  async execute(args) {
    const { scope } = args
    const keywords = (args.keywords ?? [])
      .map((k) => k.trim().toLowerCase())
      .filter((k) => k.length > 0)
    if (keywords.length === 0) {
      return JSON.stringify({ status: "error", message: "keywords must not be empty" })
    }
    let base: string
    try {
      base = resolveBase(scope as string)
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    const MAX_MATCHES = 20
    const MAX_LINES = 5
    const topics: string[] = []
    await walkMds(base, base, topics)
    topics.sort()
    const matches: { topic: string; ageDays: number; lines: string[] }[] = []
    let truncated = false
    for (const t of topics) {
      if (matches.length >= MAX_MATCHES) {
        truncated = true
        break
      }
      const file = join(base, `${t}.md`)
      let content: string
      try {
        content = await readFile(file, "utf8")
      } catch {
        continue
      }
      const hitLines: string[] = []
      content.split("\n").forEach((ln, i) => {
        if (hitLines.length >= MAX_LINES) return
        const low = ln.toLowerCase()
        if (keywords.some((k) => low.includes(k))) hitLines.push(`L${i + 1}: ${ln.trim()}`)
      })
      if (hitLines.length === 0) continue
      matches.push({ topic: t, ageDays: await ageDaysOfFile(file), lines: hitLines })
    }
    return JSON.stringify({ status: "ok", scope, keywords, count: matches.length, truncated, matches })
  },
})

export const remove = tool({
  description: "Delete a long-term memory note (project or global scope). force must be true.",
  args: {
    scope: tool.schema.string().describe("'project' or 'global'"),
    topic: tool.schema.string().describe("Topic name to delete"),
    force: tool.schema.boolean().describe("Must be true to delete"),
  },
  async execute(args) {
    const { scope, topic, force } = args
    if (!force) {
      return JSON.stringify({ status: "error", message: "refusing to delete: pass force=true to remove the memory note" })
    }
    let file: string
    try {
      file = resolveTopicFile(resolveBase(scope as string), topic as string).file
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    if (!existsSync(file)) {
      return JSON.stringify({ status: "error", message: `not found: ${scope}/${topic}` })
    }
    try {
      await rm(file, { force: true })
      return JSON.stringify({ status: "ok", removed: `${scope}/${topic}` })
    } catch (e: any) {
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
  },
})