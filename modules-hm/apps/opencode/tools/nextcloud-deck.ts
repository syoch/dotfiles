import { tool } from "@opencode-ai/plugin"
import { DatabaseSync } from "node:sqlite"

// Reads NextCloud Deck boards, stacks and cards as this session's role.
//
// API shape, learned the hard way on NC 35 / Deck 1.19:
//   boards  -> /ocs/v2.php/apps/deck/api/v1.0/boards      works
//   stacks  -> /index.php/apps/deck/api/v1.0/boards/{id}/stacks   works
//   cards   -> there is NO list-cards route. Cards come back embedded in
//              each stack, so this flattens them instead of asking for them.
// Every /cards route answers 405 with an empty body, including the documented
// card#read, so do not try to add one later without re-checking against the
// installed app's appinfo/routes.php.
//
// Default export, so the tool name is the filename: `nextcloud-deck`.

const DB = process.env.OPENCODE_DB ?? "/home/syoch/.local/share/opencode/opencode.db"
const CLOUD = process.env.NEXTCLOUD_URL ?? "https://nextcloud.syoch.org"
const DECK = `${CLOUD}/index.php/apps/deck/api/v1.0`

type Bind = { talk_token: string; uid: string; secret: string }

type Board = {
  id: number
  title: string
  archived?: boolean
  permissions?: Record<string, boolean>
}
type Stack = {
  id: number
  title: string
  order?: number
  cards?: Card[]
  /** True for the board's "Done" column; its cards are finished, not open. */
  isDoneColumn?: boolean
}
type Card = {
  id: number
  title: string
  description?: string
  dueDate?: string | null
  archived?: boolean
  labels?: { id: number; title: string }[]
  /** Present as assignedUsers: [{participant:{uid,...},...}] when assigned. */
  assignedUsers?: { participant?: { uid?: string; displayname?: string } }[]
}

function binding(sessionID: string): Bind | undefined {
  const db = new DatabaseSync(DB, { readOnly: true })
  try {
    return db
      .prepare("SELECT talk_token, uid, secret FROM talk_bind WHERE session_id = ?")
      .get(sessionID) as Bind | undefined
  } finally {
    db.close()
  }
}

async function get<T>(path: string, bind: Bind): Promise<T> {
  const res = await fetch(path, {
    headers: {
      "OCS-APIRequest": "true",
      Authorization: "Basic " + Buffer.from(`${bind.uid}:${bind.secret}`).toString("base64"),
      Accept: "application/json",
      "User-Agent": "Mozilla/5.0",
    },
  })
  if (!res.ok) throw new Error(`HTTP ${res.status} ${(await res.text()).slice(0, 200)}`)
  // The boards endpoint wraps in an OCS envelope; the stacks one does not.
  const text = await res.text()
  try {
    const parsed = JSON.parse(text)
    return (parsed?.ocs?.data ?? parsed) as T
  } catch {
    throw new Error(`non-JSON response: ${text.slice(0, 160)}`)
  }
}

function assignees(c: Card): string[] {
  return (c.assignedUsers ?? [])
    .map((a) => a?.participant?.uid ?? a?.participant?.displayname)
    .filter((s): s is string => !!s)
}

function cardLine(c: Card, stackTitle: string): string {
  const bits = [`- [card ${c.id}] ${c.title}`, `in "${stackTitle}"`]
  if (c.dueDate) bits.push(`due ${c.dueDate}`)
  if (c.archived) bits.push("(archived)")
  const who = assignees(c)
  if (who.length) bits.push(`assigned: ${who.join(", ")}`)
  const labels = (c.labels ?? []).map((l) => l.title)
  if (labels.length) bits.push(`labels: ${labels.join(", ")}`)
  const desc = (c.description ?? "").replace(/\s+/g, " ").trim()
  if (desc) bits.push(`- ${desc.slice(0, 300)}`)
  return bits.join(" | ")
}

/** Assign this card to a role, creating the assignment if it is not there yet. */
async function assign(
  cardId: number,
  uid: string,
  bind: Bind,
  boardId: number,
): Promise<void> {
  const res = await fetch(
    `${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/cards/${cardId}/assign?format=json`,
    {
      method: "POST",
      headers: {
        "OCS-APIRequest": "true",
        Authorization: "Basic " + Buffer.from(`${bind.uid}:${bind.secret}`).toString("base64"),
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
        "User-Agent": "Mozilla/5.0",
      },
      body: new URLSearchParams({ userId: uid }).toString(),
    },
  )
  if (!res.ok) throw new Error(`assign HTTP ${res.status} ${(await res.text()).slice(0, 160)}`)
  // boardId is unused by the endpoint but keeps the call readable in logs.
  void boardId
}

/**
 * Move a card to another stack. This is the one kanban verb Deck really needs.
 *
 * `order` is not optional even though we never read it back: the controller
 * signature is (id, boardId, stackId, order) with no nullable parameters, and
 * omitting it returns a bare 400 with no body. Sending a large value parks the
 * card at the end of the destination stack.
 */
async function move(
  cardId: number,
  stackId: number,
  boardId: number,
  bind: Bind,
): Promise<void> {
  const res = await fetch(
    `${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/cards/${cardId}/reorder?format=json`,
    {
      method: "PUT",
      headers: {
        "OCS-APIRequest": "true",
        Authorization: "Basic " + Buffer.from(`${bind.uid}:${bind.secret}`).toString("base64"),
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
        "User-Agent": "Mozilla/5.0",
      },
      body: new URLSearchParams({
        stackId: String(stackId),
        boardId: String(boardId),
        order: "999",
      }).toString(),
    },
  )
  if (!res.ok) throw new Error(`reorder HTTP ${res.status} ${(await res.text()).slice(0, 160)}`)
}

export default tool({
  description:
    "Track this venue's tasks in NextCloud Deck. action='mine' lists the open " +
    "cards assigned to you -- start here. action='take' claims an unassigned " +
    "card, action='create' adds a task assigned to you, action='move' moves a " +
    "card between stacks, action='boards' lists boards, and action='cards' " +
    "flattens a whole board.",
  args: {
    action: tool.schema
      .enum(["mine", "take", "create", "move", "boards", "stacks", "cards"])
      .describe("What to do."),
    board_id: tool.schema
      .number()
      .optional()
      .describe("Board to act on. Optional for 'mine'; from action='boards' otherwise."),
    card_id: tool.schema
      .number()
      .optional()
      .describe("Card to act on, for 'take' and 'move'."),
    title: tool.schema.string().optional().describe("For 'create': the card title."),
    description: tool.schema.string().optional().describe("For 'create': optional body."),
    stack: tool.schema
      .string()
      .optional()
      .describe("For 'create' and 'move': stack title, e.g. 'To Do'. Case-insensitive."),
    include_archived: tool.schema
      .boolean()
      .optional()
      .describe("Include archived cards in listings. Default false."),
  },
  async execute(args, ctx) {
    const bind = binding(ctx.sessionID)
    if (!bind) {
      return "nextcloud_deck: this session has no talk_bind row, so it has no " +
        "NextCloud identity to read Deck with."
    }

    const me = bind.uid

    try {
      if (args.action === "boards") {
        const boards = await get<Board[]>(`${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/boards?format=json`, bind)
        if (!boards.length) return "nextcloud_deck: no boards are visible to this role."
        return boards
          .map((b) => {
            const canEdit = b.permissions?.PERMISSION_EDIT ? ", editable" : ", read-only"
            return `- board ${b.id}: ${b.title} (${b.archived ? "archived" : "active"}${canEdit})`
          })
          .join("\n")
      }

      // Resolve which boards to work on: explicit, or every board this role can see.
      let boards: Board[]
      if (args.board_id !== undefined) {
        boards = [await get<Board>(`${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/board/${args.board_id}?format=json`, bind)]
      } else {
        boards = await get<Board[]>(`${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/boards?format=json`, bind)
      }
      if (!boards.length) return "nextcloud_deck: no boards are visible to this role."

      // ---- read-only listings -------------------------------------------
      if (args.action === "mine") {
        const out: string[] = []
        for (const b of boards) {
          const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
          for (const s of stacks) {
            // A stack flagged isDoneColumn is the "Done" column, so its cards
            // are finished and must not show up as open work.
            if (s.isDoneColumn) continue
            for (const c of s.cards ?? []) {
              if (c.archived && !args.include_archived) continue
              if (!assignees(c).includes(me)) continue
              out.push(`${b.title}: ${cardLine(c, s.title)}`)
            }
          }
        }
        if (!out.length) {
          return `nextcloud_deck: no open cards assigned to ${me}. ` +
            `Use action='take' with a card_id to claim unassigned work.`
        }
        return [`${out.length} open card(s) assigned to ${me}:`, ...out].join("\n")
      }

      if (args.action === "stacks") {
        const b = boards[0]
        const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
        if (!stacks.length) return `nextcloud_deck: board ${b.id} has no stacks.`
        return stacks
          .map(
            (s) =>
              `- stack ${s.id}: ${s.title} (${(s.cards ?? []).length} card(s))` +
              `${s.isDoneColumn ? " [done column]" : ""}`,
          )
          .join("\n")
      }

      if (args.action === "cards") {
        const b = boards[0]
        const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
        if (!stacks.length) return `nextcloud_deck: board ${b.id} has no stacks.`
        const lines: string[] = []
        for (const s of stacks) {
          for (const c of s.cards ?? []) {
            if (c.archived && !args.include_archived) continue
            lines.push(cardLine(c, s.title))
          }
        }
        if (!lines.length) return `nextcloud_deck: board ${b.id} has no active cards.`
        return [`${lines.length} card(s) on board ${b.id}:`, ...lines].join("\n")
      }

      // ---- writes --------------------------------------------------------
      if (args.action === "take") {
        if (args.card_id === undefined) return "nextcloud_deck: action='take' needs card_id."
        const b = boards[0]
        const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
        const found = stacks
          .flatMap((s) => (s.cards ?? []).map((c) => ({ c, s })))
          .find((x) => x.c.id === args.card_id)
        if (!found) return `nextcloud_deck: card ${args.card_id} is not on board ${b.id}.`
        if (assignees(found.c).length) {
          return (
            `nextcloud_deck: card ${args.card_id} is already assigned to ` +
            `${assignees(found.c).join(", ")}. Unassign it in the UI first.`
          )
        }
        await assign(found.c.id, me, bind, b.id)
        return `nextcloud_deck: card ${args.card_id} "${found.c.title}" is now assigned to ${me}.`
      }

      if (args.action === "create") {
        const title = (args.title ?? "").trim()
        if (!title) return "nextcloud_deck: action='create' needs title."
        const b = boards[0]
        const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
        if (!stacks.length) return `nextcloud_deck: board ${b.id} has no stacks.`
        const want = (args.stack ?? "To Do").toLowerCase()
        const target =
          stacks.find((s) => s.title.trim().toLowerCase() === want) ??
          stacks.find((s) => !s.isDoneColumn)
        if (!target) return `nextcloud_deck: no usable stack on board ${b.id}.`
        const res = await fetch(`${CLOUD}/ocs/v2.php/apps/deck/api/v1.0/cards?format=json`, {
          method: "POST",
          headers: {
            "OCS-APIRequest": "true",
            Authorization: "Basic " + Buffer.from(`${bind.uid}:${bind.secret}`).toString("base64"),
            "Content-Type": "application/x-www-form-urlencoded",
            Accept: "application/json",
            "User-Agent": "Mozilla/5.0",
          },
          body: new URLSearchParams({
            title,
            stackId: String(target.id),
            type: "task",
            description: args.description ?? "",
          }).toString(),
        })
        if (!res.ok) {
          return `nextcloud_deck: create failed (${res.status}) ${(await res.text()).slice(0, 160)}`
        }
        const data = (JSON.parse(await res.text()) as { ocs: { data: { id: number } } }).ocs.data
        await assign(data.id, me, bind, b.id)
        return `nextcloud_deck: created card ${data.id} "${title}" in "${target.title}", assigned to ${me}.`
      }

      // move
      if (args.card_id === undefined) return "nextcloud_deck: action='move' needs card_id."
      if (!args.stack) return "nextcloud_deck: action='move' needs stack (the destination title)."
      const b = boards[0]
      const stacks = await get<Stack[]>(`${DECK}/boards/${b.id}/stacks?format=json`, bind)
      const want = args.stack.trim().toLowerCase()
      const dest = stacks.find((s) => s.title.trim().toLowerCase() === want)
      if (!dest) {
        return (
          `nextcloud_deck: no stack named "${args.stack}" on board ${b.id}. ` +
          `Available: ${stacks.map((s) => s.title).join(", ")}`
        )
      }
      const here = stacks.find((s) => (s.cards ?? []).some((c) => c.id === args.card_id))
      if (!here) return `nextcloud_deck: card ${args.card_id} is not on board ${b.id}.`
      if (here.id === dest.id) {
        return `nextcloud_deck: card ${args.card_id} is already in "${dest.title}".`
      }
      await move(args.card_id, dest.id, b.id, bind)
      return `nextcloud_deck: moved card ${args.card_id} "${here.cards!.find((c) => c.id === args.card_id)!.title}" from "${here.title}" to "${dest.title}".`
    } catch (e) {
      return `nextcloud_deck: failed (${e instanceof Error ? e.message : e})`
    }
  },
})
