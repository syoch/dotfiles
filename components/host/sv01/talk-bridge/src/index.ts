/**
 * talk-bridge: a NextCloud Talk <-> opencode bridge.
 *
 * Listens on loopback only. Two interfaces:
 *   A. webhook  (Talk -> bridge)   POST /hook/<token>/<role>
 *   B. control  (leader -> bridge) /ctl/*
 *
 * Design constraints encoded here:
 *   - The webhook path carries token+role so the bridge knows which bot's
 *     secret to verify against, without trial-and-error across secrets.
 *   - The bridge never pushes message bodies proactively. One measured
 *     session held 1,205 text parts / 470,032 chars; injecting that would
 *     destroy the receiving agent's context. The leader fetches on demand.
 *   - Role identity is prompt-level, not an opencode agent definition, because
 *     opencode caches agent config at server start and cannot pick up new
 *     agent files without a restart.
 */

import { loadConfig } from "./config.ts"
import { Registry, pendingVenues } from "./db.ts"
import { Occ } from "./occ.ts"
import { Opencode } from "./opencode.ts"
import { VenueService, VenueError } from "./venue.ts"
import { webhookPath, isValidSlug, leaderRole, isValidOpencodeSessionId, parseModel } from "./naming.ts"

const cfg = loadConfig()
const registry = new Registry(cfg.dbUrl)
await registry.ensureSchema()

const occ = new Occ("nextcloud-occ", cfg.nextcloudUrl, cfg.occTimeoutMs)
const clients = new Map<string, Opencode>()
function opencodeFor(serverUrl: string): Opencode {
  const key = serverUrl.replace(/\/+$/, "")
  let c = clients.get(key)
  if (!c) {
    c = new Opencode(key, cfg.opencodeTimeoutMs)
    clients.set(key, c)
  }
  return c
}

const venues = new VenueService(
  registry,
  occ,
  cfg.nextcloudUrl,
  cfg.publicUrl,
  cfg.defaultOpencodeUrl,
  cfg.defaultHumanUser,
  opencodeFor,
  cfg.agent,
)

/**
 * The header a role sees when a message is delivered.
 *
 * Identity ("you are the <role> agent") is supplied by the `talk-post` plugin's
 * system prompt, so the bridge only labels *who is speaking* and *who is
 * addressed*. A bare `[role]` marker used to sit in front of the body and was
 * repeatedly read as the *sender*, so it is gone.
 */
function msgHeader(from: string, kind: "human" | "role", toRole: string, body: string): string {
  return `From: ${from} (${kind})\nTo: You (${toRole})\n---\n${body}`
}

/** Does `text` address this role as `@role`? */
function mentionsRole(text: string, role: string): boolean {
  const escaped = role.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  return new RegExp(`@${escaped}(?![a-zA-Z0-9-])`).test(text)
}

/**
 * A one-line notice that a hand-off happened, with a short preview.
 *
 * The full delegation message is for the target role, not the conversation: a
 * venue with a chatty lead<->specialist dialogue flooded Talk when every prompt
 * was posted verbatim. The human only needs to see that a hand-off happened.
 */
function delegateNotice(targetRole: string, message: string): string {
  const oneLine = message.replace(/\s+/g, " ").trim()
  const preview = oneLine.length > 60 ? `${oneLine.slice(0, 60)}…` : oneLine
  return `（システム）${targetRole} にプロンプトを投げました: ${preview}`
}

/**
 * Delegated-turn budget, per venue, reset on each human message.
 *
 * Hop depth was dropped because a lead<->specialist dialogue is legitimate, but
 * an unbounded loop still has to be stoppable. Counting the delegated turns
 * spawned from one human message is the cheapest sufficient guard.
 */
const delegateBursts = new Map<string, number>()

function resetDelegateBudget(token: string): void {
  delegateBursts.set(token, 0)
}

function takeDelegateBudget(token: string): boolean {
  const n = (delegateBursts.get(token) ?? 0) + 1
  delegateBursts.set(token, n)
  return n <= cfg.delegateBudget
}

// ---------------------------------------------------------------- helpers

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

function fail(msg: string, status = 400): Response {
  return json({ error: msg }, status)
}

async function readJson<T>(req: Request): Promise<T | null> {
  try {
    return (await req.json()) as T
  } catch {
    return null
  }
}

// ---------------------------------------------------- A. webhook interface

/**
 * Verify a Talk webhook signature.
 *
 * The signed payload is `random + <raw body>` and the headers are the
 * non-`Bot`-prefixed ones (`X-Nextcloud-Talk-Random` / `-Signature`); the
 * `Bot`-prefixed pair is what a bot sends when calling into NextCloud.
 * The random seed is 64 bytes and must be at least 32.
 */
async function verifySignature(
  secret: string,
  random: string | null,
  signature: string | null,
  body: string,
): Promise<boolean> {
  if (!random || !signature) return false
  if (random.length < 32) return false
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const expected = Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(random + body))))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
  const a = expected.toLowerCase()
  const b = signature.toLowerCase()
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

type WebhookEvent = {
  text: string
  actor: string
  /** "users" for a human, "bots" for another bot. Decides who may start a turn. */
  actorType: string
  actorId: string
  messageId: string
}

/**
 * Extract the chat text from the Activity Streams payload Talk sends.
 *
 * The text is NOT at `content.message`: it lives in `object.content`, which is
 * itself a JSON string of `{ message, parameters }`.
 *
 * The discriminating field is `type`, and Talk v25 uses several of them
 * (verified against BotService in spreed v25.0.0):
 *
 *   Create  - a chat message          <- the only one that is a turn
 *   Activity- a system message        (join/leave/topic changes, ...)
 *   Like    - a reaction was added
 *   Undo    - a reaction was removed
 *   Join / Leave - participant changes
 *
 * Only `Create` is a chat turn. Accepting `Activity` would mean dispatching
 * system messages and dropping every real message.
 */
function parseWebhookEvent(raw: string): WebhookEvent | null {
  let payload: any
  try {
    payload = JSON.parse(raw)
  } catch {
    return null
  }
  if (payload?.type !== "Create") return null
  let inner: any
  try {
    inner = JSON.parse(payload?.object?.content ?? "")
  } catch {
    return null
  }
  const text = typeof inner?.message === "string" ? inner.message : ""
  return {
    text,
    actor: payload?.actor?.name ?? payload?.actor?.id ?? "unknown",
    actorType: payload?.actorType ?? "users",
    actorId: String(payload?.actor?.id ?? ""),
    messageId: String(payload?.object?.id ?? ""),
  }
}

/**
 * Webhook: Talk -> bridge.
 *
 * Routing is hub-and-spoke: a human message drives the venue's leader (its
 * oldest role) plus any role the human explicitly @mentioned. Every other bot in
 * the room receives the same webhook and is skipped here, so a specialist no
 * longer reacts to chatter that was never addressed to it.
 *
 * The bridge only *enqueues* the turn. Posting is owned by the `talk-post`
 * plugin (`talk-post_post` plus its idle nudge), so there is no reply to wait
 * for and none to route. Fire-and-forget also removes the whole "which assistant
 * text is the reply" class of bugs: a multi-step turn has several text parts and
 * only the last one was ever scanned, so a mention in an earlier step was lost.
 */
async function handleWebhook(req: Request, token: string, role: string): Promise<Response> {
  const agent = await registry.getAgent(token, role)
  if (!agent) {
    // A venue registers its bot BEFORE `talk:bot:setup` can finish, so Talk
    // probes the webhook during setup and finds no row. Answering 404 there
    // makes NextCloud raise the bot's error_count, and a bot with errors stops
    // receiving webhooks -- the venue is then permanently deaf while looking
    // healthy in `talk:bot:list`.
    const probing = pendingVenues.has(`${token}/${role}`)
    if (probing) return json({ ok: true, skipped: "venue still being set up" })
    return fail(`unknown agent: ${token}/${role}`, 404)
  }

  const random = req.headers.get("x-nextcloud-talk-random")
  const signature = req.headers.get("x-nextcloud-talk-signature")
  const raw = await req.text()
  if (!(await verifySignature(agent.secret, random, signature, raw))) {
    return fail("signature verification failed", 401)
  }

  const event = parseWebhookEvent(raw)
  if (!event) return json({ ok: true, skipped: "not a chat message" })

  // Mentions are the turn signal, not content.
  const text = event.text.replace(/\{mention-[^}]+\}/g, "").trim()
  if (!text) return json({ ok: true, skipped: "empty message" })

  // A human message starts a fresh delegation burst for this venue.
  resetDelegateBudget(token)

  // Hub-and-spoke delivery.
  const agents = await registry.listAgentsByToken(token)
  const leader = agents[0]?.role
  if (role !== leader && !mentionsRole(text, role)) {
    return json({ ok: true, skipped: "not addressed" })
  }

  // Talk's webhook request has a hard 5s timeout (`'timeout' => 5` in
  // BotService::sendAsyncRequest) while a turn takes minutes, so enqueue and
  // return. The prompt id is supplied so the reply can still be correlated.
  const messageID = `msg_${crypto.randomUUID().replace(/-/g, "")}`
  void opencodeFor(agent.server_url)
    .promptAsync(agent.session_id, {
      messageID,
      agent: cfg.agent,
      text: msgHeader(event.actor, "human", role, text),
    })
    .catch((e) => console.error(`[bridge] ${token}/${role}: dispatch failed: ${String(e)}`))
  return json({ ok: true, queued: true })
}

// ---------------------------------------------------- B. control interface

async function handleControl(req: Request, url: URL): Promise<Response> {
  const p = url.pathname

  // GET /ctl/sessions?project_path=&limit=&offset=&prefix=&stats=1&server_url=
  if (req.method === "GET" && p === "/ctl/sessions") {
    const projectPath = url.searchParams.get("project_path")
    if (!projectPath) return fail("project_path is required")
    const limit = Number(url.searchParams.get("limit") ?? "20")
    const offset = Number(url.searchParams.get("offset") ?? "0")
    const prefix = url.searchParams.get("prefix") ?? ""
    const stats = url.searchParams.get("stats") === "1"
    const serverUrl = url.searchParams.get("server_url") ?? undefined
    const out = await venues.listMigrationCandidates(projectPath, { limit, offset, prefix, stats, serverUrl })
    return json(out)
  }

  // POST /ctl/venue
  if (req.method === "POST" && p === "/ctl/venue") {
    const body = await readJson<any>(req)
    if (!body) return fail("invalid JSON body")
    for (const f of ["project_path", "slug"]) {
      if (typeof body[f] !== "string" || !body[f]) return fail(`${f} is required`)
    }
    // Model is mandatory: the leader session is switched to it and roles added
    // later inherit it. There is no default.
    const model = parseModel(body.model)
    if (!model) {
      return fail(`model is required as "<provider>/<id>" (got ${JSON.stringify(body.model ?? null)})`)
    }
    if (body.migrate && !Array.isArray(body.migrate.sessions)) {
      return fail("migrate.sessions must be an explicit array of session ids")
    }
    try {
      return json(await venues.createVenue({ ...body, model }), 201)
    } catch (e) {
      const status = e instanceof VenueError ? 409 : 500
      return fail(String(e instanceof Error ? e.message : e), status)
    }
  }

  // GET /ctl/venues
  if (req.method === "GET" && p === "/ctl/venues") {
    return json({ venues: await registry.listVenues() })
  }

  // GET /ctl/agents?token=
  if (req.method === "GET" && p === "/ctl/agents") {
    const token = url.searchParams.get("token")
    if (!token) return fail("token is required")
    const agents = await registry.listAgentsByToken(token)
    return json({
      token,
      agents: agents.map((a) => ({ role: a.role, server_url: a.server_url, session_id: a.session_id, created_at: a.created_at })),
    })
  }

  // POST /ctl/bot  { token, role, project_path, secret?, description?, server_url? }
  if (req.method === "POST" && p === "/ctl/bot") {
    const body = await readJson<any>(req)
    if (!body?.token || !body?.role || !body?.project_path) {
      return fail("token, role and project_path are required")
    }
    // A role with no opencode session behind it can never answer, and that
    // failure is invisible: the bot installs fine and just stays quiet.
    // The role becomes an immutable bot name and a URL path segment, so it
    // must obey the naming rules rather than be taken verbatim.
    if (!isValidSlug(body.role)) {
      return fail(`invalid role: ${body.role} (expected lowercase ascii + hyphens)`)
    }
    // Every role of a venue shares the project prefix, which is what keeps bot
    // names unique instance-wide.
    const slug = body.project_slug
    if (slug !== undefined && body.role !== leaderRole(slug) && !body.role.startsWith(`${slug}-`)) {
      return fail(`role ${body.role} does not belong to project ${slug}`)
    }
    if ((await registry.getAgent(body.token, body.role)) !== null) {
      return fail(`agent already exists: ${body.token}/${body.role}`, 409)
    }
    const secret = `bc_${Bun.randomUUIDv7()}${Bun.randomUUIDv7()}${Bun.randomUUIDv7()}`.slice(0, 96)
    const serverUrl = (body.server_url ?? cfg.defaultOpencodeUrl).replace(/\/+$/, "")
    const hookUrl = `${cfg.publicUrl}${webhookPath(body.token, body.role)}`
    let botId: number | null = null
    try {
      // A role has to be announced before `setup` runs, because setup probes the
      // webhook while no registry row exists yet and a 404 there makes Nextcloud
      // count an error against the bot and stop delivering its webhooks.
      botId = await occ.installBot(body.role, secret, hookUrl, body.description)
      venues.beginSetup(body.token, body.role)
      try {
        await occ.setupBot(botId, body.token)
      } finally {
        venues.endSetup(body.token, body.role)
      }

      // The session is NOT created here. The caller creates it through the
      // opencode API and picks the model, then binds it with POST /ctl/session.
      // Deciding the model is opencode's business; doing it from here meant the
      // venue silently inherited a model that may be unavailable, leaving the
      // turn stuck in `retry` with no way to recover from the bridge.
      const sessionId = body.session_id
      if (!isValidOpencodeSessionId(sessionId)) {
        throw new VenueError(
          `session_id is required and must look like an opencode session id (got ${JSON.stringify(sessionId ?? null)})`,
        )
      }
      const description = typeof body.description === "string" ? body.description : null
      // Roles inherit the venue's (leader's) model unless explicitly overridden.
      const agents = await registry.listAgentsByToken(body.token)
      const modelRef = parseModel(typeof body.model === "string" ? body.model : agents[0]?.model)
      const model = modelRef ? `${modelRef.providerID}/${modelRef.id}` : null
      await registry.insertAgent({
        token: body.token,
        role: body.role,
        secret,
        server_url: serverUrl,
        session_id: sessionId,
        description,
        model,
      })
      if (modelRef) {
        await opencodeFor(serverUrl).switchModel(sessionId, modelRef)
      }
      return json({ token: body.token, role: body.role, secret, server_url: serverUrl, session_id: sessionId, description, model }, 201)
    } catch (e) {
      // Do not leave a live bot behind for a role that was never registered.
      if (botId !== null) {
        await occ.removeBotFromConversation(botId, body.token).catch(() => {})
        await occ.uninstallBot(botId).catch(() => {})
      }
      throw e
    }
  }

  // GET /ctl/route?session_id=<opencode session id>
  //
  // The reverse of /ctl/agents: a plugin only knows its own opencode session id
  // and needs to know which venue it speaks for. The registry stays here so the
  // bot secret has exactly one home -- a copy in a plugin or a config file
  // would be a second source of truth that can drift from the row the webhook
  // signature is verified against.
  if (req.method === "GET" && p === "/ctl/route") {
    const sessionId = url.searchParams.get("session_id")
    if (!sessionId) return fail("session_id is required")
    if (!isValidOpencodeSessionId(sessionId)) {
      return fail(`invalid session_id: ${sessionId}`)
    }
    const agent = await registry.findAgentBySessionId(sessionId)
    if (!agent) return json({ session_id: sessionId, bound: false }, 200)
    return json({
      session_id: sessionId,
      bound: true,
      token: agent.token,
      role: agent.role,
      secret: agent.secret,
      server_url: agent.server_url,
    })
  }

  // POST /ctl/post  { session_id, message }
  //
  // Outbound only. The desktop cannot post to Talk itself: the public URL is
  // behind Cloudflare Access, which answers 302 to a sign-in page, so a plugin's
  // direct call never reaches Nextcloud. The bridge runs on sv01 and can reach
  // the instance over loopback, and it already owns the bot secret, so it signs
  // the request. That also means no bot secret ever leaves sv01.
  if (req.method === "POST" && p === "/ctl/post") {
    const body = await readJson<any>(req)
    const message = typeof body?.message === "string" ? body.message.trim() : ""
    if (!message) return fail("message is required")
    if (!isValidOpencodeSessionId(body?.session_id)) {
      return fail(`invalid session_id: ${JSON.stringify(body?.session_id ?? null)}`)
    }
    const agent = await registry.findAgentBySessionId(body.session_id)
    if (!agent) {
      return json({ ok: false, reason: "session not bound to a venue" }, 404)
    }
    try {
      await occ.sendBotMessage(agent.token, agent.secret, message)
      return json({ ok: true, token: agent.token, role: agent.role })
    } catch (e) {
      return fail(`post failed: ${String(e)}`, 502)
    }
  }

  // POST /ctl/session  { token, role, session_id }
  if (req.method === "POST" && p === "/ctl/session") {
    const body = await readJson<any>(req)
    if (!body?.token || !body?.role || !body?.session_id) return fail("token, role and session_id are required")
    const ok = await registry.setSessionId(body.token, body.role, body.session_id)
    if (!ok) return fail(`agent not found: ${body.token}/${body.role}`, 404)
    return json({ ok: true })
  }

  // DELETE /ctl/bot?token=&role=
  if (req.method === "DELETE" && p === "/ctl/bot") {
    const token = url.searchParams.get("token")
    const role = url.searchParams.get("role")
    if (!token || !role) return fail("token and role are required")
    const agent = await registry.getAgent(token, role)
    if (!agent) return fail(`agent not found: ${token}/${role}`, 404)
    try {
      // Uninstall by webhook url: it is the unique column and we know it
      // exactly, so no name-collision guesswork is needed.
      await occ.uninstallBotByUrl(`${cfg.publicUrl}${webhookPath(token, role)}`)
    } catch (e) {
      console.error(`[bridge] uninstall failed for ${role}: ${String(e)}`)
    }
    await registry.deleteAgent(token, role)
    return json({ ok: true, removed: role })
  }

  // GET /ctl/session/<id>/messages?limit=
  if (req.method === "GET" && p.startsWith("/ctl/session/")) {
    const m = p.match(/^\/ctl\/session\/([^/]+)\/messages$/)
    if (!m) return fail("bad path", 404)
    const sessionId = decodeURIComponent(m[1])
    const limit = Number(url.searchParams.get("limit") ?? "20")
    const directory = url.searchParams.get("directory") ?? undefined
    const server = url.searchParams.get("server_url") ?? cfg.defaultOpencodeUrl
    const msgs = await opencodeFor(server).readTextMessages(sessionId, limit, directory)
    return json({ session_id: sessionId, count: msgs.length, messages: msgs })
  }

  // DELETE /ctl/venue?token=
  //
  // Removes the whole venue: every role's registry row, plus (best effort) the
  // Talk bot and the conversation. Without this, tearing down a venue leaves
  // orphaned rows and, worse, a live bot whose webhook 404s.
  if (req.method === "DELETE" && p === "/ctl/venue") {
    const token = url.searchParams.get("token")
    if (!token) return fail("token is required")
    const agents = await registry.listAgentsByToken(token)
    if (agents.length === 0) return fail(`venue not found: ${token}`, 404)
    const warnings: string[] = []
    for (const a of agents) {
      try {
        await occ.uninstallBotByUrl(`${cfg.publicUrl}${webhookPath(token, a.role)}`)
      } catch (e) {
        warnings.push(`uninstall ${a.role}: ${String(e)}`)
      }
    }
    const removed = await registry.deleteAgentsByToken(token)
    // Conversation last: if this fails the roles are already unregistered, so
    // retrying is safe and will not double-uninstall.
    try {
      await occ.deleteConversation(token)
    } catch (e) {
      warnings.push(`delete conversation: ${String(e)}`)
    }
    return json({ ok: warnings.length === 0, token, roles_removed: removed, warnings })
  }

  // GET /ctl/occ?args=talk:bot:list --output json
  //
  // Diagnostic escape hatch. `occ` only works from the `nextcloud` user, and
  // every other way to run it from a shell needs privileges the bridge's
  // caller does not have. This runs the same wrapper the bridge itself uses,
  // so it is exactly what the service can see -- no more, no less.
  if (req.method === "GET" && p === "/ctl/occ") {
    const args = url.searchParams.get("args")
    if (!args) return fail("args is required")
    const argv = args.split(/\s+/).filter(Boolean)
    if (argv.some((a) => !/^[A-Za-z0-9:_./=-]+$/.test(a))) return fail("args contains unsupported characters")
    try {
      const r = await occ.tryRun(argv)
      return json({ code: r.code, stdout: r.stdout.slice(0, 8000), stderr: r.stderr.slice(0, 4000) })
    } catch (e) {
      return fail(String(e instanceof Error ? e.message : e), 500)
    }
  }

  // POST /ctl/delegate  { session_id, target_role, message }
  //
  // The delegation primitive. It replaces the old prose relay: the agent calls
  // `talk-delegate` deliberately, so no @mention scanning is involved and a
  // multi-step turn cannot lose the hand-off. The message is posted to Talk as
  // the delegator (so the human sees the exchange) and delivered to the target
  // role's session as a turn.
  if (req.method === "POST" && p === "/ctl/delegate") {
    const body = await readJson<any>(req)
    const message = typeof body?.message === "string" ? body.message.trim() : ""
    const targetRole = typeof body?.target_role === "string" ? body.target_role : ""
    if (!message) return fail("message is required")
    if (!isValidSlug(targetRole)) return fail(`invalid target_role: ${JSON.stringify(body?.target_role ?? null)}`)
    if (!isValidOpencodeSessionId(body?.session_id)) {
      return fail(`invalid session_id: ${JSON.stringify(body?.session_id ?? null)}`)
    }
    const source = await registry.findAgentBySessionId(body.session_id)
    if (!source) return json({ ok: false, reason: "session not bound to a venue" }, 404)
    if (source.role === targetRole) return fail("cannot delegate to yourself")
    const target = await registry.getAgent(source.token, targetRole)
    if (!target) return json({ ok: false, reason: `unknown role: ${targetRole}` }, 404)
    if (!takeDelegateBudget(source.token)) {
      return json({ ok: false, reason: "budget", limit: cfg.delegateBudget }, 429)
    }
    try {
      // Post a compact notice, not the full message: the delegation content is
      // for the target role, and posting every prompt verbatim flooded Talk.
      await occ.sendBotMessage(source.token, source.secret, delegateNotice(targetRole, message))
      await opencodeFor(target.server_url).promptAsync(target.session_id, {
        messageID: `msg_${crypto.randomUUID().replace(/-/g, "")}`,
        agent: cfg.agent,
        text: msgHeader(source.role, "role", targetRole, message),
      })
      return json({ ok: true, token: source.token, from: source.role, to: targetRole })
    } catch (e) {
      return fail(`delegate failed: ${String(e)}`, 502)
    }
  }

  // GET /ctl/roles?session_id=<id>   (or ?token=<venue token>)
  //
  // The venue's role roster, for the `talk-roles` tool. Kept out of the system
  // prompt on purpose: a growing roster would bloat every request, and the lead
  // only needs it when actually choosing someone to delegate to.
  if (req.method === "GET" && p === "/ctl/roles") {
    let token = url.searchParams.get("token")
    const sessionId = url.searchParams.get("session_id")
    if (!token && sessionId) {
      const a = await registry.findAgentBySessionId(sessionId)
      if (!a) return json({ ok: false, reason: "session not bound to a venue" }, 404)
      token = a.token
    }
    if (!token) return fail("token or session_id is required")
    const agents = await registry.listAgentsByToken(token)
    return json({
      token,
      roles: agents.map((a) => ({ role: a.role, description: a.description, model: a.model })),
    })
  }

  // POST /ctl/model  { token, model }
  //
  // Project-wide model switch. The bridge never passes a model per prompt; it
  // writes the venue's model onto every bound session (`session.model` is the
  // source of truth) and stores it so roles added later inherit it. Runtime: no
  // restart, and an individual session can still be switched on its own.
  if (req.method === "POST" && p === "/ctl/model") {
    const body = await readJson<any>(req)
    if (typeof body?.token !== "string" || !body.token) return fail("token is required")
    const modelRef = parseModel(body.model)
    if (!modelRef) {
      return fail(`model is required as "<provider>/<id>" (got ${JSON.stringify(body.model ?? null)})`)
    }
    const agents = await registry.listAgentsByToken(body.token)
    if (agents.length === 0) return fail(`venue not found: ${body.token}`, 404)
    const value = `${modelRef.providerID}/${modelRef.id}`
    const updated = await registry.setModelForToken(body.token, value)
    const warnings: string[] = []
    for (const a of updated) {
      try {
        await opencodeFor(a.server_url).switchModel(a.session_id, modelRef)
      } catch (e) {
        warnings.push(`${a.role}: ${String(e)}`)
      }
    }
    return json({ ok: warnings.length === 0, token: body.token, model: value, roles: updated.map((a) => a.role), warnings })
  }

  return fail("not found", 404)
}

// ---------------------------------------------------------------- server

const server = Bun.serve({
  port: cfg.port,
  hostname: "127.0.0.1",
  async fetch(req) {
    const url = new URL(req.url)
    try {
      const hook = url.pathname.match(/^\/hook\/([^/]+)\/([^/]+)$/)
      if (req.method === "POST" && hook) {
        return await handleWebhook(req, decodeURIComponent(hook[1]), decodeURIComponent(hook[2]))
      }
      if (url.pathname.startsWith("/ctl/")) {
        return await handleControl(req, url)
      }
      if (req.method === "GET" && url.pathname === "/healthz") {
        return json({ ok: true, venues: (await registry.listVenues()).length })
      }
      return fail("not found", 404)
    } catch (e) {
      console.error(`[bridge] ${req.method} ${url.pathname}:`, e)
      return fail(String(e instanceof Error ? e.message : e), 500)
    }
  },
})

console.log(`[bridge] listening on http://127.0.0.1:${server.port} (publicUrl=${cfg.publicUrl})`)

for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => {
    console.log(`[bridge] ${sig} received, shutting down`)
    server.stop()
    registry.close().finally(() => process.exit(0))
  })
}