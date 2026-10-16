import { tool } from "@opencode-ai/plugin"

// Delegates a task to another role in this NextCloud Talk venue.
//
// Unlike `talk-post_post` (which only posts to the conversation), this both
// posts the message as you AND hands it to the target role's session as a turn.
// Talk never delivers a bot message to another bot ("No bots for bots"), so the
// bridge on sv01 performs the hand-off. The target answers with its own tools.
//
// The tool is a default export, so its name is the filename: `talk-delegate`.
// A named export would become `talk-delegate_<name>`.

const CTL_BASE = process.env.TALK_BRIDGE_CTL ?? "http://127.0.0.1:8788"
/** spreed refuses anything longer; 413 comes back otherwise. */
const MAX_MESSAGE_CHARS = 32000

export default tool({
  description:
    "Hand a task to another role in this NextCloud Talk venue. The message is " +
    "posted to the conversation as you AND delivered to that role's session, " +
    "which then answers you back. Use `talk-roles` first to see who exists. For " +
    "a message to the human with no hand-off, use `talk-post_post` instead.",
  args: {
    role: tool.schema.string().describe("The target role name, e.g. `procon-docs`."),
    message: tool.schema.string().describe("The instruction for that role, as-is."),
  },
  async execute(args, ctx) {
    const message = args.message.trim()
    const role = args.role.trim()
    if (!message) return "talk_delegate: empty message, nothing sent."
    if (message.length > MAX_MESSAGE_CHARS) {
      return `talk_delegate: ${message.length} characters exceeds the ${MAX_MESSAGE_CHARS} limit; shorten it.`
    }

    const res = await fetch(`${CTL_BASE}/ctl/delegate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: ctx.sessionID, target_role: role, message }),
    })

    if (res.status === 200) return `talk_delegate: sent to ${role}.`
    const body = (await res.json().catch(() => null)) as { reason?: string } | null
    if (res.status === 404) return `talk_delegate: ${body?.reason ?? "target not found"}.`
    if (res.status === 429) {
      return "talk_delegate: delegation budget exhausted; stop delegating and answer the human."
    }
    return `talk_delegate: failed (${res.status}) ${JSON.stringify(body ?? {})}`
  },
})
