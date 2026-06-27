import type { Plugin } from "@opencode-ai/plugin"
import { mkdir, writeFile, readFile } from "fs/promises"
import { join, dirname } from "path"
import { existsSync, appendFileSync } from "fs"

const REPETITION_THRESHOLD = 3
const ERROR_RECOVERY_THRESHOLD = 2
const MAX_CALLS_PER_SESSION = 200
const HOME = process.env.HOME ?? "~"
const HOME_SKILLS_DIR = join(HOME, ".config/opencode/skills/auto")
const GLOBAL_NUDGE_FILE = join(HOME, ".config/opencode/auto-skill-nudge.json")
const LOG_FILE = join(HOME, ".config/opencode/auto-skill.log")

type ToolCall = {
  tool: string
  args: any
  output: string
  errored: boolean
  ts: number
}

type SessionState = {
  calls: ToolCall[]
  candidates: Set<string>
  prevErrored: boolean
  recoveryPairs: Map<string, number>
}

const states = new Map<string, SessionState>()

function log(msg: string) {
  try {
    appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`)
  } catch {}
}

function normalizeArgs(tool: string, args: any): string {
  if (!args || typeof args !== "object") return ""
  if (tool === "bash" && typeof args.command === "string") {
    const cmd = args.command.trim()
    const tokens = cmd.split(/\s+/).filter(Boolean)
    const first = tokens[0] ?? ""
    const second = tokens[1] ?? ""
    if (second && /^[/.]/.test(second)) return `${first} <path>`
    if (second) return `${first} <arg>`
    return first
  }
  try {
    const clone = JSON.parse(JSON.stringify(args))
    if (typeof clone === "object" && clone !== null) {
      for (const k of Object.keys(clone)) {
        const v = clone[k]
        if (typeof v !== "string") continue
        if (v.length > 80) clone[k] = v.slice(0, 40) + "..."
        else if (/[0-9a-f-]{8,}/i.test(v)) clone[k] = "<id>"
        else if (/^[\/~]/.test(v) && v.includes("/")) clone[k] = "<path>"
      }
    }
    return JSON.stringify(clone)
  } catch {
    return ""
  }
}

function signature(tool: string, args: any): string {
  return `${tool}\x00${normalizeArgs(tool, args)}`
}

function getState(sessionID: string): SessionState {
  let s = states.get(sessionID)
  if (!s) {
    s = { calls: [], candidates: new Set(), prevErrored: false, recoveryPairs: new Map() }
    states.set(sessionID, s)
  }
  return s
}

function looksLikeError(output: string): boolean {
  if (!output) return false
  const s = output.toLowerCase()
  return s.includes("error:") || s.includes("error ") || s.includes("failed") ||
    s.includes("traceback") || s.includes("panic:") || s.includes("command failed") ||
    s.includes("exit code") || s.includes("permission denied") || s.includes("enoent")
}

async function queueNudge(entry: { name: string; scope: "global" | "project"; summary: string }) {
  let list: Array<{ name: string; scope: string; summary: string; ts: number }> = []
  try {
    if (existsSync(GLOBAL_NUDGE_FILE)) {
      list = JSON.parse(await readFile(GLOBAL_NUDGE_FILE, "utf8"))
      if (!Array.isArray(list)) list = []
    }
  } catch {
    list = []
  }
  list.push({ ...entry, ts: Date.now() })
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000
  list = list.filter(e => e.ts > cutoff)
  await mkdir(dirname(GLOBAL_NUDGE_FILE), { recursive: true })
  await writeFile(GLOBAL_NUDGE_FILE, JSON.stringify(list, null, 2))
}

async function readNudge(): Promise<Array<{ name: string; scope: string; summary: string; ts: number }>> {
  try {
    if (!existsSync(GLOBAL_NUDGE_FILE)) return []
    const list = JSON.parse(await readFile(GLOBAL_NUDGE_FILE, "utf8"))
    if (!Array.isArray(list)) return []
    const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000
    return list.filter((e: any) => typeof e?.ts === "number" && e.ts > cutoff)
  } catch {
    return []
  }
}

function slugify(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "skill"
}

async function judgeAndWrite(args: {
  client: any
  project: any
  cwd: string
  evidence: string
}): Promise<{ wrote: boolean; path?: string; reason?: string }> {
  const { client, cwd, evidence } = args

  const prompt = `You are a skill-curation subagent. Decide if the pattern below is worth a reusable SKILL.md.

Project cwd: ${cwd}
Project name: ${args.project?.name ?? "(unknown)"}

Observed pattern (recent tool calls and candidate triggers):
${evidence}

Return ONLY a JSON object (no markdown, no prose) with these fields:
{
  "worth": boolean,
  "name": "short-hyphen-name",
  "description": "One sentence starting with 'Use when...'. Include concrete trigger keywords.",
  "scope": "global" | "project",
  "body": "Markdown body of the skill. Include the when-to-use, the procedure (commands, steps), verification, and pitfalls. 200-500 words.",
  "reject_reason": "if worth=false, why"
}

Rules:
- "global" if the procedure transfers to other projects (generic patterns, common tools, debugging steps).
- "project" if it only makes sense in this specific project.
- Set worth=false if the pattern is trivial (single command, no real procedure, basic read/ls/cat, or a one-off fix).
- Set worth=true only for a reusable procedure with non-obvious steps, gotchas, or workflow value.
- Description MUST front-load concrete trigger keywords so embedding search can match it.`

  let response = ""
  let sessID: string | undefined
  try {
    const created: any = await client.session.create({})
    sessID = created?.id ?? created?.data?.id
    if (!sessID) return { wrote: false, reason: "no session id" }

    const promptRes: any = await client.session.prompt({
      path: { id: sessID },
      body: { parts: [{ type: "text", text: prompt }] },
    })
    const parts: any[] = promptRes?.parts ?? promptRes?.data?.parts ?? []
    const textParts = parts.filter(p => p?.type === "text" && typeof p.text === "string")
    response = textParts.map(p => p.text).join("\n")
    if (!response && promptRes?.error) {
      return { wrote: false, reason: `LLM error: ${promptRes.error.message ?? JSON.stringify(promptRes.error)}` }
    }
  } catch (e: any) {
    return { wrote: false, reason: `LLM error: ${e?.message ?? e}` }
  } finally {
    if (sessID) {
      try { await client.session.delete({ path: { id: sessID } }) } catch {}
    }
  }

  let parsed: any
  try {
    const m = response.match(/\{[\s\S]*\}/)
    if (!m) return { wrote: false, reason: `no JSON in response (${response.length} chars)` }
    parsed = JSON.parse(m[0])
  } catch (e: any) {
    return { wrote: false, reason: `parse error: ${e?.message ?? e}` }
  }

  if (!parsed?.worth) {
    return { wrote: false, reason: parsed?.reject_reason ?? "model said not worth" }
  }

  const name = slugify(parsed.name ?? "skill")
  const description = String(parsed.description ?? "").trim()
  const body = String(parsed.body ?? "").trim()
  if (!description || !body) {
    return { wrote: false, reason: "empty description or body" }
  }

  const scope: "global" | "project" = parsed.scope === "project" ? "project" : "global"
  const baseDir = scope === "global" ? HOME_SKILLS_DIR : join(cwd, ".opencode/skills/auto")
  const skillDir = join(baseDir, `auto-${name}-${Date.now().toString(36)}`)

  const frontmatter = `---
name: ${name}
description: ${description.replace(/"/g, '\\"')}
---

`

  try {
    await mkdir(skillDir, { recursive: true })
    await writeFile(join(skillDir, "SKILL.md"), frontmatter + body + "\n")
  } catch (e: any) {
    return { wrote: false, reason: `write error: ${e?.message ?? e}` }
  }

  await queueNudge({ name, scope, summary: description.slice(0, 120) })
  return { wrote: true, path: skillDir }
}

const AutoSkillPlugin: Plugin = async (ctx) => {
  log("plugin loaded")
  return {
    "tool.execute.after": async (input, output) => {
      const { sessionID, tool, args } = input
      const errored = looksLikeError(output.output)
      const s = getState(sessionID)
      const call: ToolCall = { tool, args, output: output.output ?? "", errored, ts: Date.now() }
      s.calls.push(call)
      if (s.calls.length > MAX_CALLS_PER_SESSION) {
        s.calls = s.calls.slice(-MAX_CALLS_PER_SESSION)
      }

      if (errored) {
        s.prevErrored = true
      } else if (s.prevErrored && s.calls.length >= 2) {
        const prev = s.calls[s.calls.length - 2]
        if (prev?.errored) {
          const key = `${prev.tool}->${tool}`
          const count = (s.recoveryPairs.get(key) ?? 0) + 1
          s.recoveryPairs.set(key, count)
          if (count >= ERROR_RECOVERY_THRESHOLD) {
            s.candidates.add(`error-recovery:${key}@${count}`)
          }
        }
        s.prevErrored = false
      }

      const counts = new Map<string, number>()
      for (const c of s.calls) {
        if (c.errored) continue
        const sig = signature(c.tool, c.args)
        counts.set(sig, (counts.get(sig) ?? 0) + 1)
      }
      for (const [sig, n] of counts) {
        if (n >= REPETITION_THRESHOLD) {
          s.candidates.add(`repeat:${sig}@${n}`)
        }
      }
    },

    event: async ({ event }) => {
      if (event.type === "session.deleted" || event.type === "session.compacted") {
        const sessionID = (event.properties as any)?.sessionID
        if (sessionID) states.delete(sessionID)
        return
      }
      if (event.type !== "session.idle") return
      const sessionID = (event.properties as any)?.sessionID
      if (!sessionID) return
      const s = states.get(sessionID)
      if (!s || s.candidates.size === 0) {
        states.delete(sessionID)
        return
      }

      const callList = s.calls.slice(-30).map(c => ({
        tool: c.tool,
        args: c.args,
        errored: c.errored,
        firstLine: c.output.split("\n").find(l => l.trim())?.slice(0, 120) ?? "",
      }))

      const evidence = [
        `Tool calls (last ${Math.min(30, s.calls.length)}):\n${JSON.stringify(callList, null, 2)}`,
        s.candidates.size > 0 ? `\nCandidate patterns:\n${[...s.candidates].join("\n")}` : "",
        s.recoveryPairs.size > 0
          ? `\nError-recovery pairs:\n${[...s.recoveryPairs.entries()].map(([k, v]) => `${k} x${v}`).join("\n")}`
          : "",
      ].join("\n")

      states.delete(sessionID)
      const result = await judgeAndWrite({
        client: ctx.client,
        project: ctx.project,
        cwd: ctx.directory,
        evidence,
      })
      if (!result.wrote) {
        log(`rejected: ${result.reason ?? "unknown"}`)
      } else {
        log(`wrote: ${result.path}`)
      }
    },

    "experimental.chat.system.transform": async (_input, output) => {
      const list = await readNudge()
      if (list.length === 0) return
      const lines = list.slice(-5).map(e => `- [auto-skill] ${e.scope}: ${e.name} — ${e.summary}`)
      const block = `[auto-skill] Recently auto-generated skills are available:\n${lines.join("\n")}\nRead SKILL.md under ~/.config/opencode/skills/auto/ or .opencode/skills/auto/ if relevant.`
      const system = output.system
      const idx = system.findIndex(s => s.includes("[auto-skill]"))
      if (idx >= 0) {
        system[idx] = block
      } else {
        system.push(block)
      }
    },
  }
}

export default AutoSkillPlugin
