/**
 * Naming rules: <project-slug>-<role-slug>
 *
 * Design rationale (decided, do not change without revisiting):
 *   - Talk bot name is IMMUTABLE (nextcloud-talk has no rename operation)
 *   - A bot is a SERVER-level entity, so the name must be unique across the
 *     whole NextCloud instance
 *   - DB `role` is used in the webhook URL path, so it must be URL-safe
 *   - Therefore: lowercase ASCII + hyphen only (no percent-encoding needed,
 *     still readable by humans, still stable as a machine key)
 *
 * role-slug granularity is RESPONSIBILITY level, not IMPLEMENTATION level:
 *   use `cache`, not `cache-redis`.
 *   Embedding the implementation makes the leader's "reuse or create new?"
 *   decision ambiguous (is `cache-redis` new, or an alias of `cache`?).
 */

export const SLUG_MAX = 40
export const BOT_NAME_MAX = 64
export const SESSION_TITLE_MAX = 200

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/

export function isValidSlug(s: string): boolean {
  return s.length > 0 && s.length <= SLUG_MAX && SLUG_RE.test(s)
}

/**
 * opencode session ids are `ses_` plus an opaque suffix.
 *
 * Kept here rather than duplicated in venue.ts because the same rule guards
 * every endpoint that binds a session.
 */
export function isValidOpencodeSessionId(id: unknown): id is string {
  return typeof id === "string" && /^ses_[A-Za-z0-9]+$/.test(id)
}

export function isValidRole(s: string): boolean {
  return isValidSlug(s)
}

/** Normalize arbitrary text into a URL-safe slug (used for display names). */
export function toSlug(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}

/**
 * Build the full role name.
 * @param projectSlug e.g. "dotfiles"
 * @param roleSlug    e.g. "portal-cache" or "lead"
 * @returns e.g. "dotfiles-portal-cache"
 */
export function roleName(projectSlug: string, roleSlug: string): string {
  if (!isValidSlug(projectSlug)) throw new Error(`invalid project slug: ${projectSlug}`)
  if (!isValidRole(roleSlug)) throw new Error(`invalid role slug: ${roleSlug}`)
  const full = `${projectSlug}-${roleSlug}`
  if (full.length > BOT_NAME_MAX) {
    throw new Error(`role name too long (${full.length} > ${BOT_NAME_MAX}): ${full}`)
  }
  return full
}

/** The leader role name for a project. */
export function leaderRole(projectSlug: string): string {
  return roleName(projectSlug, "lead")
}

/**
 * Title for a migrated (renamed) session.
 * Keeps the original title so nothing is lost by the rename.
 */
export function migratedSessionTitle(prefix: string, originalTitle: string): string {
  const base = (originalTitle ?? "").trim() || "(untitled)"
  const sep = " · "
  const combined = prefix + sep + base
  if (combined.length <= SESSION_TITLE_MAX) return combined
  const room = Math.max(0, SESSION_TITLE_MAX - prefix.length - sep.length)
  return prefix + sep + base.slice(0, room)
}

/** Detect an already-migrated title to avoid renaming twice. */
export function isMigratedTitle(title: string, prefix: string): boolean {
  return (title ?? "").startsWith(prefix)
}

/** Reverse-lookup the project slug from a role name, given the known slugs. */
export function projectSlugOfRole(role: string, knownSlugs: readonly string[]): string | undefined {
  return knownSlugs.find((s) => role === s || role.startsWith(`${s}-`))
}

/** The webhook path for a bot. Path segments must stay URL-safe. */
export function webhookPath(token: string, role: string): string {
  return `/hook/${token}/${role}`
}

/** A model reference as opencode's session API expects it. */
export type ModelRef = { providerID: string; id: string }

/**
 * Parse a `<provider>/<id>` model reference, e.g. `opencode/space-bunny-free`.
 * Returns null if it is not in that shape.
 */
export function parseModel(s: unknown): ModelRef | null {
  if (typeof s !== "string") return null
  const m = s.match(/^([A-Za-z0-9._-]+)\/([A-Za-z0-9._-]+)$/)
  if (!m) return null
  return { providerID: m[1], id: m[2] }
}