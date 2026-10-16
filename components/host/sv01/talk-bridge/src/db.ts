/**
 * Registry access for the bridge.
 *
 * Single table by design: `talk_bot` and `talk_session` were merged, and the
 * project mapping table was dropped because the leader already knows its own
 * project (it lives inside that project directory).
 *
 *   token       Talk conversation token (the venue identifier)
 *   role        persistent role identifier, also the webhook path segment
 *   secret      HMAC secret for webhook verification (plaintext by necessity:
 *               bots are created at runtime, so SOPS/declarative secrets
 *               cannot cover them)
 *   server_url  opencode server hosting the session
 *   session_id  opencode session, reused across the project's lifetime
 */

import { SQL } from "bun"

export type TalkAgent = {
  token: string
  role: string
  secret: string
  server_url: string
  session_id: string
  /** Role scope shown to the lead/roster so delegation can be routed. */
  description: string | null
  /**
   * Model as `<provider>/<id>`, or null.
   *
   * The leader's model is the venue's model; roles added later inherit it.
   * The bridge does NOT pass a model per prompt -- the value is written onto
   * each bound opencode session, so `session.model` stays the source of truth.
   */
  model: string | null
  created_at: Date
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS talk_agent (
  token       text NOT NULL,
  role        text NOT NULL,
  secret      text NOT NULL,
  server_url  text NOT NULL,
  session_id  text NOT NULL,
  description text,
  model       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (token, role)
);
CREATE INDEX IF NOT EXISTS talk_agent_role_idx ON talk_agent (role);
ALTER TABLE talk_agent ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE talk_agent ADD COLUMN IF NOT EXISTS model text;
`

export class Registry {
  private readonly sql: SQL

  constructor(url: string) {
    // The bridge owns this database, so a small pool is enough. No onconnect
    // hook: Bun.sql passes a connection object, not a queryable function.
    this.sql = new SQL({ url, max: 4 })
  }

  /** Create the table if it does not exist. Safe to call on every start. */
  async ensureSchema(): Promise<void> {
    await this.sql.unsafe(SCHEMA)
  }

  async close(): Promise<void> {
    await this.sql.close({ timeout: 5 })
  }

  async insertAgent(a: Omit<TalkAgent, "created_at">): Promise<void> {
    await this.sql`
      INSERT INTO talk_agent (token, role, secret, server_url, session_id, description, model)
      VALUES (${a.token}, ${a.role}, ${a.secret}, ${a.server_url}, ${a.session_id}, ${a.description ?? null}, ${a.model ?? null})
    `
  }

  async getAgent(token: string, role: string): Promise<TalkAgent | null> {
    const rows = await this.sql<TalkAgent[]>`
      SELECT token, role, secret, server_url, session_id, description, model, created_at
      FROM talk_agent
      WHERE token = ${token} AND role = ${role}
    `
    return rows[0] ?? null
  }

  async listAgentsByToken(token: string): Promise<TalkAgent[]> {
    return await this.sql<TalkAgent[]>`
      SELECT token, role, secret, server_url, session_id, description, model, created_at
      FROM talk_agent
      WHERE token = ${token}
      ORDER BY created_at ASC
    `
  }

  async listRolesByPrefix(prefix: string): Promise<TalkAgent[]> {
    return await this.sql<TalkAgent[]>`
      SELECT token, role, secret, server_url, session_id, description, model, created_at
      FROM talk_agent
      WHERE role = ${prefix} OR role LIKE ${prefix + "-%"}
      ORDER BY created_at ASC
    `
  }

  async listVenues(): Promise<{ token: string; roles: string[]; created_at: Date }[]> {
    return await this.sql`
      SELECT token, array_agg(role ORDER BY created_at ASC) AS roles,
             min(created_at) AS created_at
      FROM talk_agent
      GROUP BY token
      ORDER BY min(created_at) ASC
    `
  }

  async deleteAgentsByToken(token: string): Promise<number> {
    const rows = await this.sql`
      DELETE FROM talk_agent WHERE token = ${token} RETURNING role
    `
    return rows.length
  }

  async deleteAgent(token: string, role: string): Promise<boolean> {
    const rows = await this.sql`
      DELETE FROM talk_agent WHERE token = ${token} AND role = ${role} RETURNING role
    `
    return rows.length > 0
  }

  /** Update the session id for an existing row (used when adopting a session). */
  /**
   * Reverse lookup: which venue does this opencode session speak for?
   *
   * More than one venue could in principle bind the same session; the oldest
   * row wins so the answer is stable.
   */
  async findAgentBySessionId(sessionId: string): Promise<TalkAgent | null> {
    const rows = await this.sql<TalkAgent[]>`
      SELECT token, role, secret, server_url, session_id, description, model, created_at
      FROM talk_agent
      WHERE session_id = ${sessionId}
      ORDER BY created_at ASC
      LIMIT 1
    `
    return rows[0] ?? null
  }

  async setSessionId(token: string, role: string, sessionId: string): Promise<boolean> {
    const rows = await this.sql`
      UPDATE talk_agent SET session_id = ${sessionId}, updated_at = now()
      WHERE token = ${token} AND role = ${role}
      RETURNING role
    `
    return rows.length > 0
  }

  /**
   * Set the model for every role of a venue.
   *
   * The leader's model is the venue's model and roles inherit it, so a project
   * model change rewrites all rows. Returns the updated rows so the caller can
   * switch each bound session's model to match.
   */
  async setModelForToken(token: string, model: string): Promise<TalkAgent[]> {
    return await this.sql<TalkAgent[]>`
      UPDATE talk_agent SET model = ${model}, updated_at = now()
      WHERE token = ${token}
      RETURNING token, role, secret, server_url, session_id, description, model, created_at
    `
  }
}

/**
 * Roles whose venue is mid-creation.
 *
 * `talk:bot:setup` makes Talk probe the webhook before the registry row can
 * exist. Answering 404 there raises the bot's error_count, and a bot with
 * errors stops receiving webhooks -- the venue then looks healthy in
 * `talk:bot:list` but is permanently deaf.
 */
export const pendingVenues = new Set<string>()
