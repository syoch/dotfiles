import type { Plugin } from "@opencode-ai/plugin"
import { readFile, readdir } from "fs/promises"
import { join } from "path"
import { existsSync } from "fs"

const HOME = process.env.HOME ?? "~"
const USER_SCOPE = join(HOME, ".agents")
const PROJECT_SCOPE = join(process.cwd(), ".agents")
const PROJECT_MEMORY = join(process.cwd(), ".agent", "memory")
const GLOBAL_MEMORY = join(HOME, ".config", "opencode", "memory")
const MAX_ENTRIES_PER_SCOPE = 40
const MAX_MEMORY_TOPICS = 30

type CatalogEntry = {
  name: string
  args: string
  desc: string
}

function parseFrontmatter(md: string): { name: string; description: string; args: string } {
  const out = { name: "", description: "", args: "" }
  const m = /^---\n([\s\S]*?)\n---/.exec(md)
  if (!m) return out
  let activeKey: keyof typeof out | null = null
  for (const rawLine of m[1].split("\n")) {
    const line = rawLine.trimEnd()
    const kv = /^([a-zA-Z_][\w-]*):\s*(.*)$/.exec(line)
    if (kv) {
      const key = kv[1] as keyof typeof out
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

async function scanSkills(base: string): Promise<CatalogEntry[]> {
  const entries: CatalogEntry[] = []
  let dirs: string[]
  try {
    dirs = (await readdir(base, { withFileTypes: true }))
      .filter((d) => d.isDirectory() && !d.name.startsWith("."))
      .map((d) => d.name)
      .sort()
  } catch {
    return entries
  }

  for (const dir of dirs) {
    const skillFile = join(base, dir, "SKILL.md")
    if (!existsSync(skillFile)) continue
    let md = ""
    try {
      md = await readFile(skillFile, "utf8")
    } catch {
      continue
    }
    const fm = parseFrontmatter(md)
    const name = fm.name || dir
    entries.push({ name, args: fm.args, desc: fm.description })
    if (entries.length >= MAX_ENTRIES_PER_SCOPE) break
  }
  return entries
}

function formatEntry(entry: CatalogEntry, prefix: string): string {
  const args = entry.args && entry.args !== "-" && entry.args !== "なし" ? ` (${entry.args})` : ""
  const desc = entry.desc.length > 140 ? entry.desc.slice(0, 140) + "..." : entry.desc
  return `${prefix}${entry.name}${args}: ${desc}`
}

async function readUserCatalog(): Promise<string[]> {
  const lines: string[] = []
  let categories: string[] = []
  try {
    categories = (await readdir(USER_SCOPE, { withFileTypes: true }))
      .filter((d) => d.isDirectory() && !d.name.startsWith("."))
      .map((d) => d.name)
      .sort()
  } catch {
    return lines
  }
  for (const category of categories) {
    const entries = await scanSkills(join(USER_SCOPE, category))
    for (const e of entries) {
      lines.push(formatEntry(e, `  - ${category}/`))
    }
  }
  return lines
}

async function readProjectCatalog(): Promise<string[]> {
  const entries = await scanSkills(PROJECT_SCOPE)
  return entries.map((e) => formatEntry(e, "  - "))
}

async function walkMarkdownTopics(root: string, dir: string, acc: string[], max: number): Promise<void> {
  let entries
  try {
    entries = await readdir(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const e of entries) {
    if (e.name.startsWith(".") || e.name === "README.md") continue
    if (acc.length >= max) return
    const p = join(dir, e.name)
    if (e.isDirectory()) {
      await walkMarkdownTopics(root, p, acc, max)
    } else if (e.name.endsWith(".md")) {
      acc.push(p.slice(root.length).replace(/^[/\\]/, "").replace(/\.md$/, ""))
    }
  }
}

async function readMemoryTopics(base: string): Promise<string[]> {
  const acc: string[] = []
  await walkMarkdownTopics(base, base, acc, MAX_MEMORY_TOPICS)
  return acc.sort()
}

const AgentsBridgePlugin: Plugin = async () => {
  return {
    "experimental.session.compacting": async (_input, output) => {
      output.context.push(
        [
          "In addition to the required sections, append a final section titled '## Memory Candidates'.",
          "List there any decisions, policies, or important discoveries from the conversation that are worth keeping beyond this session but may not yet be recorded in long-term memory.",
          "One terse bullet each; write 'none' if there are none.",
        ].join(" "),
      )
    },
    "experimental.chat.system.transform": async (_input, output) => {
      const [userLines, projectLines, projectMem, globalMem] = await Promise.all([
        readUserCatalog(),
        readProjectCatalog(),
        readMemoryTopics(PROJECT_MEMORY),
        readMemoryTopics(GLOBAL_MEMORY),
      ])

      const blocks: string[] = []
      if (projectLines.length > 0) {
        blocks.push(`[agents-bridge] Project-scope asset catalog (${PROJECT_SCOPE}/):\n${projectLines.join("\n")}`)
      }
      if (userLines.length > 0) {
        blocks.push(`[agents-bridge] User-scope asset catalog (${USER_SCOPE}/):\n${userLines.join("\n")}`)
      }
      if (projectMem.length > 0) {
        blocks.push(`[agents-bridge] Project memory topics: ${projectMem.join(", ")} (read with memory_get)`)
      }
      if (globalMem.length > 0) {
        blocks.push(`[agents-bridge] Global memory topics: ${globalMem.join(", ")} (read with memory_get)`)
      }
      if (blocks.length === 0) return

      const block =
        blocks.join("\n") +
        "\nRead the corresponding SKILL.md under .agents/ or memory topic when a task matches."

      const system = output.system
      const idx = system.findIndex((s) => s.includes("[agents-bridge]"))
      if (idx >= 0) {
        system[idx] = block
      } else {
        system.push(block)
      }
    },
  }
}

export default AgentsBridgePlugin