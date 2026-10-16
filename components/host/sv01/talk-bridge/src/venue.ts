/**
 * Venue (conversation) lifecycle and session migration.
 *
 * A "venue" is one Talk group conversation bound to one project directory.
 * Creating a venue performs the 9-step sequence agreed in design:
 *   1. duplicate check        6. parse bot id
 *   2. create conversation    7. bot setup into the conversation
 *   3. (human invited at create)  8. create the leader session
 *   4. generate secret        9. insert the registry row
 *
 * On any failure every created artifact is undone in reverse order, so no
 * orphaned half-venues are left behind.
 */

import { leaderRole, migratedSessionTitle, isMigratedTitle, webhookPath, isValidOpencodeSessionId, type ModelRef } from "./naming.ts"
import { pendingVenues, type Registry } from "./db.ts"
import type { Occ } from "./occ.ts"
import type { Opencode, SessionStats } from "./opencode.ts"

export type MigrationCandidate = {
  id: string
  title: string
  updated_at: number | null
  already_renamed: boolean
  /** Present only when `stats` was requested. */
  stats?: SessionStats
}

export type CreateVenueInput = {
  project_path: string
  slug: string
  server_url?: string
  description?: string
  /**
   * Existing opencode session to bind as the leader. Required.
   *
   * The caller creates it through the opencode API so the model is chosen
   * there. Optional used to mean "create a session for me", which silently
   * inherited whatever model opencode defaulted to.
   */
  session_id: string
  /**
   * Model for the venue. Required: the leader session is switched to it, and
   * roles added later inherit it (the leader's model is the venue's model).
   * There is deliberately no default.
   */
  model: ModelRef
  migrate?: {
    /** Explicitly chosen session ids. Never inferred from a count. */
    sessions: string[]
    /** Prefix applied when renaming the chosen sessions. */
    rename_prefix?: string
  }
}

export type CreateVenueResult = {
  token: string
  leader_role: string
  session_id: string
  conversation_url: string
  migrated: { id: string; title: string }[]
}

export class VenueService {
  constructor(
    private readonly registry: Registry,
    private readonly occ: Occ,
    private readonly nextcloudUrl: string,
    private readonly publicUrl: string,
    private readonly defaultServerUrl: string,
    private readonly defaultHumanUser: string,
    private readonly opencodeFor: (serverUrl: string) => Opencode,
    /** opencode agent for venue turns, or null to let the session decide. */
    private readonly agent: string | null = null,
    /** Model for venue turns, or null to let opencode choose its default. */
    private readonly model: { providerID: string; modelID: string } | null = null,
  ) {}

  private conversationUrl(token: string): string {
    return `${this.nextcloudUrl}/index.php/call/${token}`
  }

  /** Talk requires the bot secret to be 40..128 characters. */
  private newSecret(): string {
    return `bc_${Bun.randomUUIDv7()}${Bun.randomUUIDv7()}${Bun.randomUUIDv7()}`.slice(0, 96)
  }

  /**
   * List migration candidates for a project directory.
   *
   * `stats` costs one full message-list request per candidate, so it is
   * opt-in. The size numbers are the judgement inputs for choosing what to
   * migrate: a session holding ~485k chars is not something to adopt blindly.
   */
  async listMigrationCandidates(
    projectPath: string,
    opts: { limit: number; offset: number; prefix: string; serverUrl?: string; stats?: boolean },
  ): Promise<{ total: number; candidates: MigrationCandidate[] }> {
    const oc = this.opencodeFor(opts.serverUrl ?? this.defaultServerUrl)
    const all = await oc.listSessions(projectPath)
    const ordered = [...all].sort((a, b) => (b.time?.updated ?? 0) - (a.time?.updated ?? 0))
    const slice = ordered.slice(opts.offset, opts.offset + opts.limit)
    const candidates: MigrationCandidate[] = []
    for (const s of slice) {
      const c: MigrationCandidate = {
        id: s.id,
        title: s.title ?? "",
        updated_at: s.time?.updated ?? null,
        already_renamed: isMigratedTitle(s.title ?? "", opts.prefix),
      }
      if (opts.stats) {
        c.stats = await oc.sessionStats(s.id, projectPath).catch(() => ({
          messages: 0,
          text_parts: 0,
          chars: 0,
        }))
      }
      candidates.push(c)
    }
    return { total: ordered.length, candidates }
  }

  /**
   * Mark a role as mid-setup so the webhook acknowledges Talk's probe instead
   * of 404ing. Without this the bot's error_count rises during setup and
   * Nextcloud stops delivering its webhooks, while `talk:bot:list` still shows
   * it as enabled.
   */
  beginSetup(token: string, role: string): void {
    pendingVenues.add(`${token}/${role}`)
  }

  endSetup(token: string, role: string): void {
    pendingVenues.delete(`${token}/${role}`)
  }

  async createVenue(input: CreateVenueInput): Promise<CreateVenueResult> {
    const slug = input.slug
    const leader = leaderRole(slug)
    const serverUrl = (input.server_url ?? this.defaultServerUrl).replace(/\/+$/, "")
    const prefix = input.migrate?.rename_prefix ?? `${slug}/prev`
    const oc = this.opencodeFor(serverUrl)

    // 1. duplicate check: the leader role must not already exist
    const dupes = await this.registry.listRolesByPrefix(slug)
    if (dupes.length > 0) {
      throw new VenueError(
        `project "${slug}" already has ${dupes.length} role(s): ` +
          dupes.map((d) => d.role).join(", "),
      )
    }

    // Undo stack, applied in reverse on failure.
    let token: string | null = null
    let botId: number | null = null
    let rowInserted = false
    try {
      // 2. create the conversation (the human is invited here, so Talk rolls
      //    the room back itself if the invite fails)
      const conv = await this.occ.createConversation(slug, [this.defaultHumanUser], input.description)
      token = conv.token

      // 3. generate the secret
      const secret = this.newSecret()

      // 4. install the leader bot
      const hookUrl = `${this.publicUrl}${webhookPath(token, leader)}`
      // 5. resolve the bot id
      botId = await this.occ.installBot(leader, secret, hookUrl)

      // 6. set the bot up in the conversation.
      // The registry row does not exist yet, so `setup` may probe the webhook
      // and get a 404, which raises the bot's error_count and can silence it
      // for good. Announce the role first so those probes are acknowledged.
      this.beginSetup(token, leader)
      try {
        await this.occ.setupBot(botId, token)
      } finally {
        this.endSetup(token, leader)
      }

      // 7. bind an existing session.
      //
      // The session is created by the caller through the opencode API so that
      // the model is chosen there, not inherited here. A venue that picked the
      // model itself silently used whatever opencode happened to default to,
      // and when that model was unavailable the turn sat in `retry` forever
      // with no error anywhere. Required, so a venue can never be created
      // without a session behind it.
      if (!isValidOpencodeSessionId(input.session_id)) {
        throw new VenueError(
          `session_id is required and must look like an opencode session id (got ${JSON.stringify(input.session_id ?? null)})`,
        )
      }
      const sessionId = input.session_id

      // 8. insert the registry row
      await this.registry.insertAgent({
        token,
        role: leader,
        secret,
        server_url: serverUrl,
        session_id: sessionId,
        // The venue description doubles as the leader's scope, so the roster
        // tool (`talk-roles`) can show what the leader is for.
        description: input.description ?? null,
        model: `${input.model.providerID}/${input.model.id}`,
      })
      rowInserted = true

      // Apply the venue's model to the leader session. The bridge never passes a
      // model per prompt; `session.model` is the single source of truth.
      await oc.switchModel(sessionId, input.model)

      // 9. migration: rename the chosen sessions, then brief the leader
      const migrated = await this.applyMigration(
        input.migrate?.sessions ?? [],
        prefix,
        input.project_path,
        serverUrl,
      )

      if (migrated.length > 0) {
        const list = migrated.map((m) => `- ${m.title}  (session_id: ${m.id})`).join("\n")
        // Fire-and-forget: the briefing is a courtesy, and waiting on the turn
        // would make a slow model roll back an otherwise healthy venue.
        await oc
          .promptAsync(sessionId, {
            messageID: `msg_${crypto.randomUUID().replace(/-/g, "")}`,
            agent: this.agent,
            directory: input.project_path,
            text:
              "This project has previous sessions. Their titles were prefixed so you can spot them.\n" +
              "The titles and ids are below. Do NOT assume you know their content.\n" +
              "If you need one, fetch it via the bridge endpoint " +
              "`GET /ctl/session/<session_id>/messages?limit=N`.\n\n" +
              list,
          })
          .catch((e) => {
            console.error(`[bridge] migration briefing failed for ${leader}: ${String(e)}`)
          })
      }

      return {
        token,
        leader_role: leader,
        session_id: sessionId,
        conversation_url: this.conversationUrl(token),
        migrated,
      }
    } catch (e) {
      // Undo in reverse order of creation. Each step is best-effort: the
      // original error is what the caller needs to see.
      if (rowInserted && token) {
        await this.registry.deleteAgent(token, leader).catch(() => {})
      }
      if (botId !== null) {
        if (token) await this.occ.removeBotFromConversation(botId, token).catch(() => {})
        await this.occ.uninstallBot(botId).catch(() => {})
      }
      if (token) await this.occ.deleteConversation(token).catch(() => {})
      throw e
    }
  }

  /**
   * Rename the chosen sessions and return the resulting titles.
   * Body text is never read here -- one measured session held ~485k chars.
   */
  private async applyMigration(
    sessionIds: string[],
    prefix: string,
    projectPath: string,
    serverUrl: string,
  ): Promise<{ id: string; title: string }[]> {
    if (sessionIds.length === 0) return []
    const oc = this.opencodeFor(serverUrl)
    const sessions = await oc.listSessions(projectPath)
    const out: { id: string; title: string }[] = []
    for (const id of sessionIds) {
      const found = sessions.find((x) => x.id === id)
      if (!found) throw new VenueError(`migration target not found in ${projectPath}: ${id}`)
      const title = migratedSessionTitle(prefix, found.title ?? "")
      await oc.updateSessionTitle(id, title, projectPath)
      out.push({ id, title })
    }
    return out
  }
}

export class VenueError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "VenueError"
  }
}
