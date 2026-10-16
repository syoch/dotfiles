import { tool, type Plugin } from "@opencode-ai/plugin"

// The Talk side of the venue bridge, on the outbound half.
//
// The bridge on sv01 stays the single registry: it holds the webhook secret for
// inbound HMAC verification, and the plugin asks it (GET /ctl/route) which
// venue a given opencode session speaks for. Nothing is duplicated here.
//
// Why an event hook rather than the bridge posting the reply: the bridge had to
// guess when a turn ended -- `idle`, then a text-stability timer, then a
// "newer turn appeared" signal -- and every version of that guess was wrong
// somewhere (posts commentary mid-tool, or holds a finished reply for minutes
// when a session sits in `retry`). `session.idle` is the edge-triggered signal
// the server already emits, so the question disappears.

/** Per opencode session: the turn in flight, and whether it already posted. */
type TurnState = { messageID: string; posted: boolean; nudged: boolean; fromTalk: boolean }
const turns = new Map<string, TurnState>()

/**
 * The name the model sees: opencode turns a named export in tools/ into
 * `<file>_<export>`, so tools/talk-post.ts exporting `post` becomes
 * `talk-post_post`.
 *
 * NOT exported. opencode calls every export of a plugin file as a plugin
 * function, so a stray `export const` string makes the whole file fail to load
 * -- silently, leaving the venue with no nudge and no briefing.
 */
const TALK_POST_TOOL = "talk-post_post"

/**
 * The delegation tool (tools/talk-delegate.ts, a default export so the name is
 * the filename). It also speaks in the conversation -- it posts the message it
 * hands off -- so a turn that delegates has "said something" and must not be
 * nudged afterwards.
 */
const DELEGATE_TOOL = "talk-delegate"

// Guards the pairing with tools/talk-post.ts, which must export `post` from a
// file named `talk-post.ts` for the model to see `talk_post_post`. If either
// side is renamed, every reply silently stops being treated as posted and the
// nudge fires on every turn.
if (TALK_POST_TOOL !== "talk-post_post") {
  throw new Error(
    `talk-post tool name drift: expected "talk-post_post" (file tools/talk-post.ts exporting \`post\`), got ${TALK_POST_TOOL}`,
  )
}

/**
 * Sentinel that identifies the nudge prompt.
 *
 * Without it the nudge's own turn resets `nudged` and the bridge nudges itself
 * forever: nudge -> idle -> nudge -> idle, which is exactly what a probe session
 * ended up doing. Checking the prompt text closes the loop without needing to
 * know the id of the nudge message.
 */
const NUDGE_MARKER = "[talk-bridge-nudge]"

const NUDGE =
  `${NUDGE_MARKER} System: 話すことがあれば talk-post_post ツールを実行してください。` +
  "なければ何もしなくてよいです"

/**
 * Prefix talk-poll.py puts on every prompt it delivers for a Talk message.
 *
 * It is the one signal that separates a turn which answers into Talk from a
 * turn typed locally into the same session, and it implies the session has a
 * venue at all (the receiver only delivers to talk_bind rows). Gating the
 * nudge on it stops the "nothing to say" churn in sessions that can never
 * post. Keep in sync with TALK_MSG_MARKER in talk-poll.py.
 */
const TALK_MSG_MARKER = "[talk-msg]"

const CTL_BASE = process.env.TALK_BRIDGE_CTL ?? "http://127.0.0.1:8788"

type Route = { bound: boolean; token?: string; role?: string }

/**
 * Which venue this opencode session speaks for. Read-only: the bridge owns the
 * registry and the bot secret, and the nudge turn below needs only the names to
 * put in the briefing.
 */
async function resolveRoute(opencodeSessionId: string): Promise<Route> {
  const res = await fetch(`${CTL_BASE}/ctl/route?session_id=${encodeURIComponent(opencodeSessionId)}`)
  if (!res.ok) return { bound: false }
  return (await res.json()) as Route
}

const TalkPost: Plugin = async ({ client }) => {
  return {
    // `input.messageID` is optional and arrives undefined here, which left the
    // turn untracked and the nudge silent. The authoritative id is the user
    // message itself, which assistant steps carry as `parentID`.
    "chat.message": async ({ sessionID, messageID }, output) => {
      const id = messageID || output?.message?.id
      if (!id) return
      const text = (output?.parts ?? [])
        .map((p) => ("text" in p ? String(p.text ?? "") : ""))
        .join("")
      const isNudge = text.includes(NUDGE_MARKER)
      const fromTalk = text.includes(TALK_MSG_MARKER)
      turns.set(sessionID, { messageID: id, posted: false, nudged: isNudge, fromTalk })
    },

    "experimental.chat.system.transform": async (input, output) => {
      // This hook runs on every request, so a compacted session still gets the
      // briefing: nothing here depends on conversation history.
      if (!input.sessionID) return
      const route = await resolveRoute(input.sessionID)
      if (!route.bound || !route.token || !route.role) return
      const block = [
        `You are the \`${route.role}\` role agent for the NextCloud Talk conversation \`${route.token}\`.`,
        "",
        "Rules:",
        "- You are a PEER of the human in this conversation, not an approver.",
        "- Speak only when the topic concerns your role; otherwise stay silent.",
        "- Keep messages short, like an ordinary chat message.",
        "",
        "Speaking and delegation:",
        "- `talk-post_post`: post your final answer to the human. Call it once, then stop.",
        "- `talk-delegate`: hand a task to another role. It posts the message AND delivers it to that role, which answers you back. Call `talk-roles` first to see who exists.",
        "- If you have nothing to say, call nothing; silence is a valid answer.",
        "",
        "Venue control:",
        // A role agent was observed hunting 8787/9101/10002 for this and giving
        // up, because the bridge is only reachable at the forwarded port. Spell
        // the base URL, the token and the role out so binding never needs a guess.
        `- The bridge control API is at ${CTL_BASE} (env: TALK_BRIDGE_CTL).`,
        `- This venue token is \`${route.token}\`; your role is \`${route.role}\`.`,
        "- Read the `nextcloud-talk-venue` skill for the exact payloads.",
      ].join("\n")
      // Match on the token, not a `[role]` marker: the marker was read as the
      // sender and is gone.
      const idx = output.system.findIndex((s) => s.includes(`NextCloud Talk conversation \`${route.token}\``))
      if (idx >= 0) output.system[idx] = block
      else output.system.push(block)
    },

    // "Did this turn post?" must come from the tool hook, not from message
    // shape: every assistant reply carries `parentID` equal to the prompt id, so
    // a parentID match says nothing about whether the tool ran.
    "tool.execute.after": async ({ tool, sessionID }) => {
      if (tool !== TALK_POST_TOOL && tool !== DELEGATE_TOOL) return
      const state = turns.get(sessionID)
      if (state) state.posted = true
    },

    event: async ({ event }) => {
      const e = event as unknown as { type: string; properties?: Record<string, unknown> }
      if (e.type !== "session.idle") return
      const sessionID = e.properties?.sessionID as string | undefined
      if (!sessionID) return
      const state = turns.get(sessionID)
      turns.delete(sessionID)
      if (!state) return

      // A nudge's own turn: its outcome is the feedback that says whether the
      // nudge earns its keep (it caught a forgotten reply) or was noise.
      if (state.nudged) {
        console.error(`[talk-post] nudge ${state.posted ? "accepted" : "declined"} session=${sessionID}`)
        return
      }

      // Only a turn a Talk message started is expected to answer in Talk.
      // Local turns and sessions with no venue can never post, so nudging them
      // only produces "nothing to say" churn.
      if (state.posted || !state.fromTalk) return

      // The turn ended without posting. Ask once whether the agent meant to say
      // something. If it declines, that is the answer: nothing is posted.
      state.nudged = true
      turns.set(sessionID, state)
      await client.session
        .promptAsync({
          path: { id: sessionID },
          body: { parts: [{ type: "text", text: NUDGE }] },
        })
        .catch((err: unknown) => {
          console.error(`[talk-post] nudge failed for ${sessionID}: ${String(err)}`)
        })
    },
  }
}

export default TalkPost