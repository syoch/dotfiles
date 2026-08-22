import { tool } from "@opencode-ai/plugin"
import type { Plugin } from "@opencode-ai/plugin"
import { mkdir, readFile, writeFile, appendFile } from "fs/promises"
import { join, resolve } from "path"

const ALLOWED_AGENT = "leader"
const MAX_PARALLEL = 3

type State = {
  createdAt: string
  participants: Record<string, string>
}

const OrchestrationPlugin: Plugin = async (input) => {
  const client = input.client

  return {
    tool: {
      orchestrate_run: tool({
        description:
          "Run a multi-agent orchestration step. Sends the same instruction to the given participant agents (by agent type name, e.g. proposer, critic, design) and returns each participant's full reply. Sessions are persisted per orchestration name (state in .agents/orchestration/<name>.json), so reusing the same name resumes the same participant sessions and preserves their conversation context. mode='sequential' runs participants one after another; mode='parallel' runs them concurrently (max 3).",
        args: {
          name: tool.schema
            .string()
            .describe(
              "Orchestration identifier. Becomes the state file .agents/orchestration/<name>.json. Use a stable slug (e.g. 'cache-invalidation-review') to keep conversation context across calls.",
            ),
          participants: tool.schema
            .array(tool.schema.string())
            .describe("Agent type names to run (e.g. ['proposer', 'critic']). Existing sessions are resumed."),
          mode: tool.schema
            .enum(["sequential", "parallel"])
            .describe("sequential = one after another; parallel = concurrent (max 3 at once)"),
          instruction: tool.schema
            .string()
            .describe("Instruction to send to each participant agent (the topic/question/request)."),
        },
        async execute(args, ctx) {
          if (ctx.agent !== ALLOWED_AGENT) {
            return `error: orchestrate_run is only available to the '${ALLOWED_AGENT}' agent (current agent: ${ctx.agent})`
          }
          const base = resolve(join(ctx.directory, ".agents", "orchestration"))
          await mkdir(base, { recursive: true })
          const stateFile = join(base, `${args.name}.json`)
          const logFile = join(base, `${args.name}.log`)

          let state: State
          try {
            state = JSON.parse(await readFile(stateFile, "utf8"))
          } catch {
            state = { createdAt: new Date().toISOString(), participants: {} }
          }
          if (!state.participants) state.participants = {}
          if (!state.createdAt) state.createdAt = new Date().toISOString()

          const participants = (args.participants ?? []).filter((p) => typeof p === "string" && p.length > 0)
          if (participants.length === 0) {
            return "error: participants must be a non-empty array of agent type names"
          }
          const mode = args.mode === "parallel" ? "parallel" : "sequential"
          const results: Record<string, string> = {}

          const runOne = async (agentName: string): Promise<void> => {
            try {
              let sid = state.participants[agentName]
              if (!sid) {
                const created: any = await client.session.create({
                  query: { directory: ctx.directory },
                  body: { title: `orchestration:${args.name}:${agentName}` },
                })
                sid = created?.id ?? created?.data?.id
                if (!sid) {
                  results[agentName] = `[error] session create failed for '${agentName}': ${JSON.stringify(created).slice(0, 200)}`
                  return
                }
                state.participants[agentName] = sid
              }
              const res: any = await client.session.prompt({
                path: { id: sid },
                body: { agent: agentName, parts: [{ type: "text", text: args.instruction }] },
              })
              const info = res?.data?.info ?? {}
              const text = (res?.data?.parts ?? [])
                .filter((p: any) => p.type === "text")
                .map((p: any) => p.text)
                .join("")
              if (info.error) {
                results[agentName] = `[error] prompt failed for '${agentName}': ${info.error.message ?? JSON.stringify(info.error).slice(0, 200)}`
                return
              }
              results[agentName] = text
            } catch (e: any) {
              results[agentName] = `[error] ${e?.message ?? String(e)}`
            }
          }

          if (mode === "parallel") {
            for (let i = 0; i < participants.length; i += MAX_PARALLEL) {
              await Promise.all(participants.slice(i, i + MAX_PARALLEL).map((p) => runOne(p)))
            }
          } else {
            for (const p of participants) {
              await runOne(p)
            }
          }

          await writeFile(stateFile, JSON.stringify(state, null, 2)).catch(() => {})
          const log =
            `[${new Date().toISOString()}] mode=${mode} participants=[${participants.join(", ")}]\n` +
            `> instruction: ${args.instruction}\n` +
            participants.map((p) => `--- ${p} ---\n${results[p] ?? "(no output)"}\n`).join("") +
            "\n"
          await appendFile(logFile, log).catch(() => {})

          return {
            output: participants
              .map((p) => `<${p}>\n${results[p] ?? ""}\n</${p}>`)
              .join("\n\n"),
          }
        },
      }),
    },
  }
}

export default OrchestrationPlugin
