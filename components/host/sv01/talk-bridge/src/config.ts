/**
 * Bridge configuration, read from the environment.
 *
 * The systemd unit supplies every value; nothing here has a default that
 * would silently work in the wrong place.
 */

function required(name: string): string {
  const v = process.env[name]
  if (!v || v.length === 0) throw new Error(`missing required env: ${name}`)
  return v
}

function optional(name: string, fallback: string): string {
  const v = process.env[name]
  return v && v.length > 0 ? v : fallback
}

export type Config = {
  /** PostgreSQL connection URL for the talk registry database. */
  dbUrl: string
  /** Port the bridge listens on (loopback only; see the NixOS unit). */
  port: number
  /**
   * Base URL Talk uses to reach this bridge for bot webhooks.
   * Must be reachable FROM the NextCloud process on this host.
   */
  publicUrl: string
  /** NextCloud instance URL, passed to `occ` via --url. */
  nextcloudUrl: string
  /** Default opencode server used when a venue does not specify one. */
  defaultOpencodeUrl: string
  /** NextCloud user id added to every new venue conversation. */
  defaultHumanUser: string
  /** Per-request timeout for `occ` invocations (ms). */
  occTimeoutMs: number
  /** Per-request timeout for opencode HTTP calls (ms). */
  opencodeTimeoutMs: number
  /**
   * Maximum number of delegated role turns spawned from one human message.
   *
   * Delegation is explicit (`talk-delegate`), so a prose @mention no longer
   * triggers a relay; a chain can only grow when an agent deliberately asks
   * another role. Bounding the *total* (rather than a depth) still stops a
   * lead<->specialist loop that forgets to terminate. The counter resets
   * whenever a human message arrives.
   */
  delegateBudget: number
  /**
   * opencode agent to drive role turns with, or null to let each session use
   * its own.
   *
   * Role identity is carried by the prompt, not by an opencode agent, so this
   * is about *capability*, not identity. Leaving it null (the default) means a
   * session keeps whichever agent it was created with / last used -- which is
   * what you want when a role is bound to an existing session: the venue then
   * talks to that session's own agent instead of silently downgrading it to
   * `general` and losing its tool access.
   */
  agent: string | null
}

export function loadConfig(): Config {
  const port = Number(optional("BRIDGE_PORT", "8787"))
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`invalid BRIDGE_PORT: ${optional("BRIDGE_PORT", "")}`)
  }
  return {
    dbUrl: required("TALK_DB_URL"),
    port,
    publicUrl: optional("BRIDGE_PUBLIC_URL", `http://127.0.0.1:${port}`).replace(/\/+$/, ""),
    nextcloudUrl: required("NEXTCLOUD_URL").replace(/\/+$/, ""),
    defaultOpencodeUrl: required("OPENCODE_URL").replace(/\/+$/, ""),
    defaultHumanUser: optional("NEXTCLOUD_HUMAN_USER", "syoch"),
    occTimeoutMs: Number(optional("OCC_TIMEOUT_MS", "120000")),
    opencodeTimeoutMs: Number(optional("OPENCODE_TIMEOUT_MS", "300000")),
    delegateBudget: Number(optional("BRIDGE_DELEGATE_BUDGET", "12")),
    agent: optional("BRIDGE_AGENT", "").trim() || null,
  }
}