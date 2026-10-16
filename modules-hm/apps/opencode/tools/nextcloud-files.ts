import { tool } from "@opencode-ai/plugin"
import { DatabaseSync } from "node:sqlite"

// Browses this role's files and manages NextCloud share links.
//
// Listing goes through WebDAV, not the Files OCS API: on NC 35
// /ocs/v2.php/apps/files/api/v1/root answers 404, while a PROPFIND against
// /remote.php/dav/files/<uid>/ returns 207. PROPFIND returns 207 even on
// partial success, so a non-2xx is the only real failure signal.
//
// Default export, so the tool name is the filename: `nextcloud-files`.

const DB = process.env.OPENCODE_DB ?? "/home/syoch/.local/share/opencode/opencode.db"
const CLOUD = process.env.NEXTCLOUD_URL ?? "https://nextcloud.syoch.org"
/** Group-shared folder every venue publishes into. One per venue, owned by the lead. */
const SHARED_ROOT = "/shared"

type Bind = { talk_token: string; uid: string; secret: string }

type Share = {
  id: string
  url?: string
  name?: string
  path?: string
  share_type?: number
  permissions?: number
  token?: string
  note?: string
  /** Set for user/group shares; the group or user name. */
  share_with?: string
  share_with_displayname?: string
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

/**
 * Project group for this session, from its working directory.
 *
 * Same rule the receiver uses (basename, lowercased), so the share lands on the
 * group the rest of the venue already belongs to: procon, kumo, dotfiles, ...
 */
function projectGroup(sessionID: string): string | undefined {
  const db = new DatabaseSync(DB, { readOnly: true })
  try {
    const row = db
      .prepare("SELECT directory FROM session WHERE id = ?")
      .get(sessionID) as { directory?: string } | undefined
    const dir = row?.directory
    if (!dir) return undefined
    return dir.replace(/\/+$/, "").split("/").pop()?.toLowerCase()
  } finally {
    db.close()
  }
}

/** True when this session is the venue lead, i.e. the one allowed to create /shared. */
function isLeader(sessionID: string): boolean {
  const db = new DatabaseSync(DB, { readOnly: true })
  try {
    const row = db
      .prepare("SELECT is_leader FROM talk_bind WHERE session_id = ?")
      .get(sessionID) as { is_leader?: number } | undefined
    return !!row?.is_leader
  } finally {
    db.close()
  }
}

function authHeader(bind: Bind): string {
  return "Basic " + Buffer.from(`${bind.uid}:${bind.secret}`).toString("base64")
}

/** Normalise to a leading slash and reject traversal before touching the DAV path. */
function safePath(p: string): string {
  const parts = p.split("/").filter((s) => s && s !== ".")
  if (parts.includes("..")) throw new Error("path must not contain '..'")
  return "/" + parts.join("/")
}

async function propfind(path: string, bind: Bind): Promise<{ name: string; dir: boolean }[]> {
  const res = await fetch(`${CLOUD}/remote.php/dav/files/${bind.uid}${encodeURI(path)}`, {
    method: "PROPFIND",
    headers: {
      Authorization: authHeader(bind),
      Depth: "1",
      "Content-Type": "application/xml",
      "User-Agent": "Mozilla/5.0",
    },
    body: `<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>`,
  })
  if (res.status < 200 || res.status >= 300) {
    throw new Error(`PROPFIND HTTP ${res.status} ${(await res.text()).slice(0, 200)}`)
  }
  const xml = await res.text()
  const out: { name: string; dir: boolean }[] = []
  for (const chunk of xml.split("<d:response>").slice(1)) {
    const href = chunk.match(/<d:href>([^<]*)<\/d:href>/)?.[1]
    if (!href) continue
    const name = decodeURIComponent(href.replace(/\/$/, "").split("/").pop() ?? "")
    const dir = /<d:collection\s*\/>/.test(chunk)
    out.push({ name, dir })
  }
  // The first entry is the directory itself.
  return out.slice(1)
}

async function shares(path: string, bind: Bind): Promise<Share[]> {
  const q = new URLSearchParams({ path, reshares: "true", format: "json" })
  const res = await fetch(`${CLOUD}/ocs/v2.php/apps/files_sharing/api/v1/shares?${q}`, {
    headers: {
      "OCS-APIRequest": "true",
      Authorization: authHeader(bind),
      Accept: "application/json",
      "User-Agent": "Mozilla/5.0",
    },
  })
  if (!res.ok) throw new Error(`shares HTTP ${res.status} ${(await res.text()).slice(0, 200)}`)
  const body = (await res.json()) as { ocs: { data: Share[] } }
  return body.ocs.data ?? []
}

/** PUT the file, creating any missing parent collections first. */
async function put(path: string, body: string, bind: Bind): Promise<void> {
  const parts = path.split("/").filter(Boolean)
  const base = `${CLOUD}/remote.php/dav/files/${bind.uid}`
  let acc = ""
  for (const dir of parts.slice(0, -1)) {
    acc += `/${encodeURIComponent(dir)}`
    const res = await fetch(base + acc, {
      method: "MKCOL",
      headers: { Authorization: authHeader(bind), "User-Agent": "Mozilla/5.0" },
    })
    // 201 = created, 405 = already there. Anything else is a real failure.
    if (![201, 405].includes(res.status)) {
      throw new Error(`MKCOL ${acc} HTTP ${res.status} ${(await res.text()).slice(0, 120)}`)
    }
  }
  const target = `${base}${acc}/${encodeURIComponent(parts[parts.length - 1])}`
  const res = await fetch(target, {
    method: "PUT",
    headers: {
      Authorization: authHeader(bind),
      "Content-Type": "text/markdown; charset=utf-8",
      "User-Agent": "Mozilla/5.0",
    },
    body,
  })
  // 201 = created, 204 = overwritten. Both are success; the operation is
  // idempotent, so re-publishing a report does not create a duplicate.
  if (![201, 204].includes(res.status)) {
    throw new Error(`PUT HTTP ${res.status} ${(await res.text()).slice(0, 160)}`)
  }
}

/** Numeric id, needed for the /f/<id> link that only works when logged in. */
async function fileId(path: string, bind: Bind): Promise<number | undefined> {
  const res = await fetch(`${CLOUD}/remote.php/dav/files/${bind.uid}${encodeURI(path)}`, {
    method: "PROPFIND",
    headers: {
      Authorization: authHeader(bind),
      Depth: "0",
      "Content-Type": "application/xml",
      "User-Agent": "Mozilla/5.0",
    },
    body: `<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><oc:fileid/></d:prop></d:propfind>`,
  })
  if (!res.ok) return undefined
  const m = (await res.text()).match(/<oc:fileid>(\d+)<\/oc:fileid>/)
  return m ? Number(m[1]) : undefined
}

/**
 * Share with a NextCloud group (shareType 1) or a user (shareType 0).
 *
 * Note these carry no `url`: a group/user share is not a link. The reference
 * to hand out is the /f/<fileid> link, which resolves only for a signed-in user
 * who already has access.
 */
async function shareWith(
  path: string,
  bind: Bind,
  shareType: 0 | 1,
  withWhom: string,
  permissions: number,
  note: string,
) {
  const res = await fetch(`${CLOUD}/ocs/v2.php/apps/files_sharing/api/v1/shares`, {
    method: "POST",
    headers: {
      "OCS-APIRequest": "true",
      Authorization: authHeader(bind),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
      "User-Agent": "Mozilla/5.0",
    },
    body: new URLSearchParams({
      path,
      shareType: String(shareType),
      shareWith: withWhom,
      permissions: String(permissions),
      ...(note ? { note } : {}),
    }).toString(),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`share HTTP ${res.status} ${text.slice(0, 200)}`)
  const meta = (JSON.parse(text) as { ocs: { meta: { statuscode: number }; data: Share } }).ocs
  if (meta.meta.statuscode !== 200) {
    throw new Error(`share refused: statuscode ${meta.meta.statuscode}`)
  }
  return meta.data
}

/**
 * Whether a collection exists, judged by the PROPFIND status.
 *
 * Not by entry count: an existing but empty folder answers with a single
 * <d:response> for itself, and propfind() drops that, so "0 entries" means both
 * "missing" and "present but empty". Treating the second case as missing makes
 * every publish re-run the bootstrap, and each run adds another group share.
 * 404 is the only reliable "not there yet" signal.
 */
async function folderExists(path: string, bind: Bind): Promise<boolean> {
  const res = await fetch(`${CLOUD}/remote.php/dav/files/${bind.uid}${path}`, {
    method: "PROPFIND",
    headers: {
      Authorization: authHeader(bind),
      Depth: "0",
      "Content-Type": "application/xml",
      "User-Agent": "Mozilla/5.0",
    },
    body: `<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>`,
  })
  if (res.status === 404) return false
  if (res.status < 200 || res.status >= 300) {
    throw new Error(`PROPFIND ${path} HTTP ${res.status}`)
  }
  return true
}

/**
 * Make sure the group-shared folder exists and is writable by the group.
 *
 * The lead owns it. That is a deliberate choice: the folder lives in the lead's
 * account, which keeps one owner per venue instead of a separate share-only
 * account, at the cost of the folder being tied to the lead's lifetime.
 *
 * Idempotent: an existing folder is only re-shared if it is not already shared
 * with this group, so calling it on every publish is cheap and safe.
 */
async function ensureSharedFolder(
  bind: Bind,
  group: string | undefined,
  leader: boolean,
): Promise<{ ok: true; created: boolean } | { ok: false; reason: string }> {
  if (!group) {
    return {
      ok: false,
      reason:
        "could not derive a project group for this session, so there is nobody to share with.",
    }
  }
  const base = `${CLOUD}/remote.php/dav/files/${bind.uid}`
  if (!(await folderExists(SHARED_ROOT, bind))) {
    if (!leader) {
      return {
        ok: false,
        reason:
          `${SHARED_ROOT}/ does not exist in this account. Only the venue lead creates it; ` +
          `ask the lead to publish once first.`,
      }
    }
    const res = await fetch(base + SHARED_ROOT, {
      method: "MKCOL",
      headers: { Authorization: authHeader(bind), "User-Agent": "Mozilla/5.0" },
    })
    if (![201, 405].includes(res.status)) {
      throw new Error(`MKCOL ${SHARED_ROOT} HTTP ${res.status}`)
    }
    // 31 = read|update|create|delete|share, so members can publish themselves.
    await shareWith(SHARED_ROOT, bind, 1, group, 31, "venue shared folder")
    return { ok: true, created: true }
  }

  // Folder exists: make sure the group can still write to it.
  const current = await shares(SHARED_ROOT, bind)
  const hasGroup = current.some((s) => s.share_type === 1 && s.share_with === group)
  if (!hasGroup) {
    if (!leader) {
      return {
        ok: false,
        reason: `${SHARED_ROOT}/ exists but is not shared with "${group}". Ask the lead to fix it.`,
      }
    }
    await shareWith(SHARED_ROOT, bind, 1, group, 31, "venue shared folder")
    return { ok: true, created: true }
  }
  return { ok: true, created: false }
}

export default tool({
  description:
    "Publish a long report as a file in this venue's group-shared folder, and " +
    "return a link. Use it instead of pasting long text into Talk. The folder is " +
    "/shared and every member of the project group can read and write it. Also " +
    "list files in this account, or list existing share links.",
  args: {
    action: tool.schema
      .enum(["ls", "shares", "publish"])
      .describe(
        "ls = list a directory; shares = list links on a path; " +
        "publish = write a file into the group-shared folder.",
      ),
    path: tool
      .schema.string()
      .optional()
      .describe("Defaults to '/shared/<title>.md' for publish."),
    content: tool.schema
      .string()
      .optional()
      .describe("For publish: the file body (markdown)."),
    title: tool.schema
      .string()
      .optional()
      .describe("For publish: filename to derive from, e.g. '2026-10-14-status'."),
    note: tool.schema.string().optional().describe("Optional note attached to a share."),
  },
  async execute(args, ctx) {
    const bind = binding(ctx.sessionID)
    if (!bind) {
      return "nextcloud_files: this session has no talk_bind row, so it has no " +
        "NextCloud identity to use."
    }

    try {
      if (args.action === "publish") {
        const body = args.content ?? ""
        if (!body.trim()) {
          return "nextcloud_files: publish needs 'content'."
        }
        const group = projectGroup(ctx.sessionID)
        const name =
          (args.title ?? "")
            .trim()
            .replace(/[^\w.-]+/g, "-")
            .replace(/^-+|-+$/g, "")
            .toLowerCase() || `report-${new Date().toISOString().slice(0, 10)}`
        const file = name.endsWith(".md") ? name : `${name}.md`
        const path = safePath(args.path || `${SHARED_ROOT}/${file}`)

        // Put it in the group-shared folder rather than sharing each file.
        // Per-file shares mount flat in the recipient's root, so a report
        // published that way shows up as /report.md and loses its folder
        // structure. A folder share keeps one predictable path for everyone.
        let note = ""
        try {
          const boot = await ensureSharedFolder(bind, group, isLeader(ctx.sessionID))
          if (!boot.ok) return `nextcloud_files: ${boot.reason}`
          if (boot.created) note = `created ${SHARED_ROOT}/ and shared it with "${group}"`
        } catch (e) {
          return `nextcloud_files: shared folder unavailable (${e instanceof Error ? e.message : e})`
        }

        await put(path, body, bind)

        const fid = await fileId(path, bind)
        const link = fid
          ? `${CLOUD}/f/${fid}  (opens only for a signed-in member of "${group}")`
          : undefined
        return [
          `published ${path}`,
          `  ${body.length} chars${note ? `, ${note}` : ""}`,
          `  readable by every member of group "${group}" at ${SHARED_ROOT}/`,
          link ? `  link: ${link}` : `  no fileid returned; members open ${path} from their Files app`,
        ].join("\n")
      }

      if (!args.path) return `nextcloud_files: action='${args.action}' needs path.`
      const path = safePath(args.path)

      if (args.action === "ls") {
        const entries = await propfind(path, bind)
        if (!entries.length) return `nextcloud_files: ${path} is empty.`
        const dirs = entries.filter((e) => e.dir).map((e) => e.name + "/")
        const files = entries.filter((e) => !e.dir).map((e) => e.name)
        const lines: string[] = [`${path} (${bind.uid}):`]
        if (dirs.length) lines.push(`  dirs:  ${dirs.join(", ")}`)
        if (files.length) lines.push(`  files: ${files.join(", ")}`)
        if (!dirs.length && !files.length) lines.push("  (nothing visible to this role)")
        return lines.join("\n")
      }

      if (args.action === "shares") {
        const found = await shares(path, bind)
        if (!found.length) return `nextcloud_files: no shares on ${path}.`
        return found
          .map(
            (s) =>
              `- share ${s.id} ${s.share_type === 3 ? "(public link)" : `(type ${s.share_type})`} ` +
              `${s.url ?? ""} perms=${s.permissions ?? "?"}${s.note ? ` note="${s.note}"` : ""}`,
          )
          .join("\n")
      }

      // publish handles its own sharing via the group-shared folder, so the only
      // remaining action here is 'shares'; anything else is a caller mistake.
      return `nextcloud_files: unknown action '${args.action}'.`
    } catch (e) {
      return `nextcloud_files: failed (${e instanceof Error ? e.message : e})`
    }
  },
})
