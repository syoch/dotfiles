import { tool } from "@opencode-ai/plugin"

// Posts a message to the NextCloud Talk conversation this session belongs to.
//
// Why the bridge does the POST rather than this file talking to Nextcloud
// directly: the public instance URL is behind Cloudflare Access, which answers
// 302 to a sign-in page, so a direct call never reaches the Talk API. The bridge
// runs on sv01 beside Nextcloud and can reach it over loopback.
//
// The bot secret therefore never leaves sv01: this tool sends the message, and
// the bridge looks up the venue from the opencode session id and signs it.
//
// NOTE: a tool defined inside a plugin's `tool: {}` map is not exposed to the
// model, while a named export under ~/.config/opencode/tools/ is. That is why
// this is its own file, and why the tool the model sees is `talk_post_post`.

const CTL_BASE = process.env.TALK_BRIDGE_CTL ?? "http://127.0.0.1:8788"

/**
 * User-mode endpoint owned by the long-poll receiver.
 *
 * A session listed in `talk_bind` posts as its own NextCloud *user* app
 * password, so the reply survives the bot being uninstalled. That receiver
 * answers 404 when the session has no talk_bind row, which is the signal to
 * fall back to the bridge and post as a bot like before.
 *
 * Keeping the app password in the receiver rather than here means this tool
 * never reads the credential at all.
 */
const USER_CTL = process.env.TALK_USER_CTL ?? "http://127.0.0.1:8790"
/** spreed refuses anything longer; 413 comes back otherwise. */
const MAX_MESSAGE_CHARS = 32000

export const post = tool({
  description:
    "Post a message to the NextCloud Talk conversation this session belongs to. " +
    "Use it for the reply you want the human to read. Call it exactly once with " +
    "the final answer; if you have nothing to say, call nothing.",
  args: {
    text: tool.schema.string().describe("The message to post to Talk, as-is."),
  },
  async execute(args, ctx) {
    const message = args.text.trim()
    if (!message) return "talk_post: empty text, nothing posted."
    if (message.length > MAX_MESSAGE_CHARS) {
      return `talk_post: ${message.length} characters exceeds the ${MAX_MESSAGE_CHARS} limit; shorten the message.`
    }

    const body = JSON.stringify({ session_id: ctx.sessionID, message })

    // User mode first: this session may be bound to a NextCloud user in
    // talk_bind, in which case the bot identity is either gone or unwanted.
    try {
      const userRes = await fetch(`${USER_CTL}/ctl/post`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
      })
      if (userRes.status === 200) return "talk_post: posted (as user)."
      if (userRes.status !== 404) {
        const detail = (await userRes.text().catch(() => "")).slice(0, 300)
        return `talk_post: user-mode send failed (${userRes.status}) ${detail}`
      }
      // 404 == no talk_bind row, so this is an ordinary bot session.
    } catch {
      // Receiver not running (or down). Fall through to the bridge.
    }

    const res = await fetch(`${CTL_BASE}/ctl/post`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    })

    if (res.status === 200) return "talk_post: posted."
    const detail = (await res.text().catch(() => "")).slice(0, 300)
    if (res.status === 404) {
      return (
        "talk_post: this session is not bound to a Talk venue, so there is nowhere to post. " +
        "Answer normally; the human will see it where you were invoked from."
      )
    }
    return `talk_post: failed (${res.status}) ${detail}`
  },
})