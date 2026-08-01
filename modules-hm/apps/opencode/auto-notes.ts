import type { Plugin } from "@opencode-ai/plugin"
import { mkdir, writeFile, readFile } from "fs/promises"
import { join, dirname } from "path"
import { existsSync, appendFileSync } from "fs"

const HOME = process.env.HOME ?? "~"
const LOG_FILE = join(HOME, ".config/opencode/auto-notes.log")
const PROJECT_NOTES_REL = ".opencode/PROJECT_NOTES.md"
const SECTIONS = ["Decisions", "Setup / Conventions", "Open Questions / Risks", "Workflow Notes", "User Preferences"] as const
type Section = typeof SECTIONS[number]

const MAX_USER_MESSAGES = 30
const MIN_MESSAGE_LENGTH = 12

type SessionState = {
  userMessages: string[]
  hasNoted: boolean
}

const states = new Map<string, SessionState>()

function log(msg: string) {
  try { appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`) } catch {}
}

function getState(sessionID: string): SessionState {
  let s = states.get(sessionID)
  if (!s) {
    s = { userMessages: [], hasNoted: false }
    states.set(sessionID, s)
  }
  return s
}

const TEMPLATE = `# Project Notes

> Auto-maintained by the opencode auto-notes plugin. New bullets are appended
> on session.idle when an LLM subagent judges the recent user messages
> contain durable project information (decisions, conventions, setup steps,
> open questions, or user preferences). Review and prune periodically.

## Decisions

## Setup / Conventions

## Open Questions / Risks

## Workflow Notes

## User Preferences
`

function sectionHeader(s: Section): string {
  return `## ${s}`
}

function ensureFile(cwd: string): Promise<void> {
  const path = join(cwd, PROJECT_NOTES_REL)
  if (existsSync(path)) return Promise.resolve()
  return mkdir(dirname(path), { recursive: true }).then(() => writeFile(path, TEMPLATE))
}

async function readNotes(cwd: string): Promise<string> {
  const path = join(cwd, PROJECT_NOTES_REL)
  try {
    return await readFile(path, "utf8")
  } catch {
    return ""
  }
}

async function appendBullets(cwd: string, section: Section, bullets: string[]): Promise<void> {
  if (bullets.length === 0) return
  const path = join(cwd, PROJECT_NOTES_REL)
  await ensureFile(cwd)
  const current = await readNotes(cwd)
  const header = sectionHeader(section)
  const lines = current.split("\n")
  const idx = lines.findIndex(l => l.trim() === header)
  if (idx < 0) {
    const stamp = new Date().toISOString().slice(0, 10)
    const block = `\n${header}\n\n${bullets.map(b => `- ${stamp}: ${b}`).join("\n")}\n`
    await writeFile(path, current + block)
    return
  }
  const stamp = new Date().toISOString().slice(0, 10)
  const newBullets = bullets.map(b => `- ${stamp}: ${b}`).join("\n")
  let insertAt = idx + 1
  while (insertAt < lines.length && !lines[insertAt].startsWith("## ")) insertAt++
  lines.splice(insertAt, 0, newBullets)
  await writeFile(path, lines.join("\n"))
}

function extractTextParts(parts: any[]): string {
  if (!Array.isArray(parts)) return ""
  return parts
    .filter(p => p?.type === "text" && typeof p.text === "string")
    .map(p => p.text)
    .join("\n")
    .trim()
}

async function extractUserMessages(client: any, sessionID: string): Promise<string[]> {
  try {
    const res: any = await client.session.messages({ sessionID: sessionID })
    const list: any[] = res?.data ?? res ?? []
    const texts: string[] = []
    for (const m of list) {
      if (m?.info?.role !== "user") continue
      const text = extractTextParts(m?.parts ?? [])
      if (text.length >= MIN_MESSAGE_LENGTH) texts.push(text)
    }
    return texts.slice(-MAX_USER_MESSAGES)
  } catch {
    return []
  }
}

async function judgeAndAppend(args: {
  client: any
  project: any
  cwd: string
  messages: string[]
}): Promise<{ wrote: number; reason?: string }> {
  const { client, cwd, messages } = args
  if (messages.length === 0) return { wrote: 0, reason: "no messages" }

  const prompt = `You are a project-notes curator subagent. Review the recent user messages below and extract anything that should be remembered for future sessions in this project.

Project cwd: ${cwd}
Project name: ${args.project?.name ?? "(unknown)"}

Recent user messages (oldest first):
${messages.map((m, i) => `[${i + 1}] ${m}`).join("\n\n")}

Return ONLY a JSON object (no markdown, no prose) with these fields:
{
  "sections": {
    "Decisions": ["short bullet", ...],
    "Setup / Conventions": ["short bullet", ...],
    "Open Questions / Risks": ["short bullet", ...],
    "Workflow Notes": ["short bullet", ...],
    "User Preferences": ["short bullet", ...]
  },
  "skip_reason": "if all sections are empty, why nothing was worth recording"
}

Rules:
- Only record things that are durable (will matter in future sessions).
- Skip transient commands, one-off questions, debugging chatter, and tool output.
- Each bullet must be self-contained (a future agent reading just that bullet should understand it).
- Prefer concrete facts over vague statements. Names, paths, versions, commands are good.
- Empty arrays are fine; only populate a section if you found something durable.
- If everything is transient (e.g. the session was just running tests), return empty arrays and a skip_reason.`

  let response = ""
  let sessID: string | undefined
  try {
    const created: any = await client.session.create({})
    sessID = created?.id ?? created?.data?.id
    if (!sessID) return { wrote: 0, reason: "no session id" }

    const promptRes: any = await client.session.prompt({
      path: { id: sessID },
      body: { parts: [{ type: "text", text: prompt }] },
    })
    const parts: any[] = promptRes?.parts ?? promptRes?.data?.parts ?? []
    const textParts = parts.filter(p => p?.type === "text" && typeof p.text === "string")
    response = textParts.map(p => p.text).join("\n")
    if (!response && promptRes?.error) {
      return { wrote: 0, reason: `LLM error: ${promptRes.error.message ?? JSON.stringify(promptRes.error)}` }
    }
  } catch (e: any) {
    return { wrote: 0, reason: `LLM error: ${e?.message ?? e}` }
  } finally {
    if (sessID) {
      try { await client.session.delete({ path: { id: sessID } }) } catch {}
    }
  }

  let parsed: any
  try {
    const m = response.match(/\{[\s\S]*\}/)
    if (!m) return { wrote: 0, reason: `no JSON in response (${response.length} chars)` }
    parsed = JSON.parse(m[0])
  } catch (e: any) {
    return { wrote: 0, reason: `parse error: ${e?.message ?? e}` }
  }

  const sections = parsed?.sections ?? {}
  let total = 0
  for (const sec of SECTIONS) {
    const bullets = sections[sec]
    if (!Array.isArray(bullets)) continue
    const clean = bullets
      .filter((b: any) => typeof b === "string")
      .map((b: string) => b.trim())
      .filter((b: string) => b.length > 0)
      .slice(0, 5)
    if (clean.length > 0) {
      await appendBullets(cwd, sec, clean)
      total += clean.length
    }
  }
  return { wrote: total, reason: total === 0 ? parsed?.skip_reason ?? "no durable info" : undefined }
}

const AutoNotesPlugin: Plugin = async (ctx) => {
  log("plugin loaded")
  return {
    "chat.message": async (input) => {
      const text = extractTextParts((input as any).parts ?? [])
      if (text.length < MIN_MESSAGE_LENGTH) return
      const s = getState(input.sessionID)
      s.userMessages.push(text)
      if (s.userMessages.length > MAX_USER_MESSAGES * 2) {
        s.userMessages = s.userMessages.slice(-MAX_USER_MESSAGES * 2)
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
      if (!s || s.userMessages.length === 0 || s.hasNoted) {
        states.delete(sessionID)
        return
      }

      const messages = await extractUserMessages(ctx.client, sessionID)
      if (messages.length === 0) {
        states.delete(sessionID)
        return
      }

      s.hasNoted = true
      const result = await judgeAndAppend({
        client: ctx.client,
        project: ctx.project,
        cwd: ctx.directory,
        messages,
      })
      states.delete(sessionID)
      if (result.wrote > 0) {
        log(`wrote ${result.wrote} bullet(s) to ${ctx.directory}/${PROJECT_NOTES_REL}`)
      } else {
        log(`skipped: ${result.reason ?? "no bullets"}`)
      }
    },
  }
}

export default AutoNotesPlugin
