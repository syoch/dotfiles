import { tool } from "@opencode-ai/plugin"
import { DatabaseSync } from "node:sqlite"

// Lists who is actually in this NextCloud Talk conversation.
//
// Previously this asked the bridge, which owned the venue registry. The bots
// are gone now, so the bridge has no rows to answer with and the tool failed
// with "this session is not bound to a Talk venue". Talk itself is the
// authority on membership, so ask Talk.
//
// Two APIs, and the difference matters: the v1 chat endpoint is what
// long-polling uses, but `room/<token>/participants` only exists on v4 --
// v1 answers 404 "Invalid query" for it.
//
// Default export, so the tool name is the filename: `talk-roles`.

const DB = process.env.OPENCODE_DB ?? "/home/syoch/.local/share/opencode/opencode.db"
const CLOUD = process.env.NEXTCLOUD_URL ?? "https://nextcloud.syoch.org"

/** spreed participantType -> readable. 3 is an ordinary logged-in user. */
const TYPE: Record<number, string> = {
  1: "guest",
  2: "email",
  3: "user",
  4: "remote",
  5: "federated",
}

type Bind = { talk_token: string; uid: string; secret: string; is_leader: number }
type Participant = {
  participantType?: number
  actorType?: string
  actorId?: string
  displayName?: string
}

function binding(sessionID: string): Bind | undefined {
  const db = new DatabaseSync(DB, { readOnly: true })
  try {
    return db
      .prepare(
        "SELECT talk_token, uid, secret, is_leader FROM talk_bind WHERE session_id = ?",
      )
      .get(sessionID) as Bind | undefined
  } finally {
    db.close()
  }
}

async function ocs<T>(path: string, uid: string, secret: string): Promise<T> {
  const res = await fetch(CLOUD + path, {
    headers: {
      "OCS-APIRequest": "true",
      Authorization: "Basic " + Buffer.from(`${uid}:${secret}`).toString("base64"),
      Accept: "application/json",
      "User-Agent": "Mozilla/5.0",
    },
  })
  if (!res.ok) throw new Error(`HTTP ${res.status} ${(await res.text()).slice(0, 200)}`)
  const body = (await res.json()) as { ocs: { data: T } }
  return body.ocs.data
}

export default tool({
  description:
    "List the people and agents in this NextCloud Talk conversation, marking " +
    "which are agent roles and which one is the lead. Use it to decide who to " +
    "address with an @mention.",
  args: {},
  async execute(_args, ctx) {
    const bind = binding(ctx.sessionID)
    if (!bind) {
      return "talk_roles: this session has no talk_bind row, so it is not bound " +
        "to a Talk conversation."
    }

    let participants: Participant[]
    try {
      participants = await ocs<Participant[]>(
        `/ocs/v2.php/apps/spreed/api/v4/room/${encodeURIComponent(bind.talk_token)}/participants?format=json`,
        bind.uid,
        bind.secret,
      )
    } catch (e) {
      return `talk_roles: failed to list participants (${e instanceof Error ? e.message : e})`
    }

    const db = new DatabaseSync(DB, { readOnly: true })
    let roles: { uid: string; is_leader: number; session_id: string }[]
    try {
      roles = db
        .prepare(
          "SELECT uid, is_leader, session_id FROM talk_bind WHERE talk_token = ?",
        )
        .all(bind.talk_token) as typeof roles
    } finally {
      db.close()
    }
    const byActor = new Map(roles.map((r) => [r.uid, r]))

    if (participants.length === 0) return "talk_roles: nobody is in this conversation."

    const lines = participants.map((p) => {
      const id = p.actorId ?? "?"
      const kind = TYPE[p.participantType ?? 3] ?? p.actorType ?? "user"
      const role = byActor.get(id)
      if (!role) return `- ${p.displayName || id} (${kind}, human)`
      const tag = role.is_leader ? "LEAD, agent role" : "agent role"
      return `- ${p.displayName || id} (${kind}, ${tag}) ${role.session_id}`
    })
    return [`${participants.length} participant(s):`, ...lines].join("\n")
  },
})
