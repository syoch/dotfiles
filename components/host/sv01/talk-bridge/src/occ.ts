/**
 * Wrapper around the `nextcloud-occ` CLI shipped by the NixOS NextCloud
 * module (`environment.systemPackages`), which is already configured with the
 * right php, config dir and webroot for this instance.
 *
 * Every invocation passes `--url` so `occ` never needs to guess the host.
 *
 * Command surface verified against nextcloud/spreed **v25.0.0** (the version
 * shipped with the NextCloud 35 package this host runs):
 *   talk:room:create <name> [--description X] [--user U]... [--listable N] [--public]
 *        -> prints "Room token: <token>" + "Room successfully created."
 *           `public` is VALUE_NONE, so the DEFAULT is already TYPE_GROUP (2).
 *   talk:room:add <token> [--user U]...        (token is positional!)
 *   talk:room:delete <token>
 *   talk:bot:install <name> <secret> <url> [description] --feature F...
 *        -> NO --output option and prints no id. Install then resolve the id
 *           via `talk:bot:list`.
 *   talk:bot:setup <bot-id> <token>...
 *   talk:bot:remove <bot-id> <token>...
 *   talk:bot:uninstall [id] | --url <url>
 *   talk:bot:list [token] [--output json]     (writeTableInOutputFormat)
 *
 * Two constraints that are easy to get wrong and fatal at runtime:
 *
 * 1. FEATURE "event" is MUTUALLY EXCLUSIVE with webhook/response/reaction in
 *    v25 (Bot/Install.php rejects the combination with exit code 1). "event"
 *    is for bots implemented as in-server Nextcloud apps; this bridge is an
 *    external HTTP service, so it must use webhook+response+reaction.
 *
 * 2. Outgoing bot requests are signed with
 *    HMAC-SHA256(secret, random + message) -- NOT random alone -- and the
 *    random seed must be at least 32 bytes.
 *    (ChecksumVerificationService::validateRequest)
 *
 * Bot secret limits: 40..128 characters.
 */

export type OccResult = { code: number; stdout: string; stderr: string }

/**
 * Bot feature flags.
 *
 * `event` is deliberately absent: in Talk v25 `talk:bot:install` rejects it
 * combined with webhook/response/reaction ("They are mutual exclusive",
 * exit code 1). `event` exists for bots implemented as in-server Nextcloud
 * apps; an external HTTP bridge needs the other three.
 */
export const BOT_FEATURES = ["webhook", "response", "reaction"] as const

/**
 * Whether `--url` may be appended to a command.
 *
 * Never, in practice. Verified on the real NextCloud 35:
 *   - `OC\Core\Command\Base::configure()` only declares `--output`, never
 *     `--url`.
 *   - `talk:room:create` does not even call `parent::configure()`, so it has
 *     neither `--url` nor `--output`.
 *
 * Symfony rejects undeclared options outright, so appending `--url` breaks
 * every command it is added to. The nixpkgs `nextcloud-occ` wrapper already
 * points at the right instance by setting NEXTCLOUD_CONFIG_DIR and cd'ing
 * into the webroot, so no command needs it.
 *
 * Kept as a set (rather than deleted) because the CLI does accept `--url` on a
 * few unrelated commands, should one ever be needed here.
 */
const OCC_COMMANDS_WITH_URL = new Set<string>()

export class OccError extends Error {
  constructor(
    readonly args: string[],
    readonly result: OccResult,
  ) {
    super(`occ ${args.join(" ")} failed (exit ${result.code}): ${result.stderr.trim() || result.stdout.trim()}`)
    this.name = "OccError"
  }
}

export class Occ {
  constructor(
    private readonly bin: string,
    private readonly url: string,
    private readonly timeoutMs: number,
  ) {}

  private async run(args: string[]): Promise<OccResult> {
    // Never append --url: no NextCloud 35 occ command declares it (see
    // OCC_COMMANDS_WITH_URL). Symfony hard-fails on undeclared options.
    const full = OCC_COMMANDS_WITH_URL.has(args[0]) ? [...args, "--url", this.url] : [...args]
    const proc = Bun.spawn([this.bin, ...full], {
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env },
    })
    // `proc.exited` resolves to the exit code only; stdout/stderr must be
    // drained from the streams. Race the whole drain so a hung occ is killed.
    let timer: ReturnType<typeof setTimeout> | undefined
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        proc.kill()
        reject(new Error(`occ timeout after ${this.timeoutMs}ms: ${full.join(" ")}`))
      }, this.timeoutMs)
    })
    const drain = Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]).then(([stdout, stderr, code]) => ({ code, stdout, stderr }))
    try {
      return await Promise.race([drain, timeout])
    } finally {
      if (timer) clearTimeout(timer)
    }
  }

  /** Run occ and throw on non-zero exit. */
  async ok(args: string[]): Promise<string> {
    const r = await this.run(args)
    if (r.code !== 0) throw new OccError(args, r)
    return r.stdout
  }

  /** Run occ and return the raw result, including on non-zero exit. */
  async tryRun(args: string[]): Promise<OccResult> {
    return await this.run(args)
  }

  /** Run occ with --output=json and parse stdout. */
  async json<T>(args: string[]): Promise<T> {
    const out = await this.ok([...args, "--output", "json"])
    const trimmed = out.trim()
    if (!trimmed) throw new Error(`occ ${args.join(" ")} returned empty output`)
    return JSON.parse(trimmed) as T
  }

  // ---- conversations ----

  /**
   * Create a private group conversation (roomType 2, invite-only, not
   * listable) and return its token. The human is invited here rather than in a
   * second call so Talk can roll the room back itself if the invite fails.
   *
   * Confirmed against NextCloud 35: `talk:room:create` does not call
   * `parent::configure()`, so it accepts neither `--url` nor `--output`.
   */
  async createConversation(name: string, users: string[], description?: string): Promise<{ token: string }> {
    const args = ["talk:room:create", name]
    if (description) args.push("--description", description)
    for (const u of users) args.push("--user", u)
    // LISTABLE_NONE: the venue is not discoverable in the room list.
    args.push("--listable", "0")
    const out = await this.ok(args)
    // occ prints "Room token: <token>". Do not guess with a loose regex: a
    // description or error text could contain an 8+ char lowercase word.
    const m = out.match(/^Room token:\s*(\S+)\s*$/m)
    if (!m) throw new Error(`could not parse token from talk:room:create output: ${JSON.stringify(out)}`)
    return { token: m[1] }
  }

  async addUserToConversation(token: string, user: string): Promise<void> {
    // `token` is a positional argument; `--user` is the option.
    await this.ok(["talk:room:add", token, "--user", user])
  }

  async deleteConversation(token: string): Promise<void> {
    await this.ok(["talk:room:delete", token])
  }

  // ---- bots ----

  /**
   * Install a bot and return its numeric id.
   *
   * Verified against NextCloud 35 / Talk v25: there is no `--output` option,
   * but the id IS printed as a second line:
   *
   *   Bot installed
   *   ID: 1
   *
   * so it is parsed from stdout. The listing is still consulted as a fallback,
   * matched on the webhook url (a unique column) rather than on the name.
   */
  async installBot(name: string, secret: string, webhookUrl: string, description?: string): Promise<number> {
    if (secret.length < 40 || secret.length > 128) {
      throw new Error(`bot secret must be 40..128 characters (got ${secret.length})`)
    }
    const args = [
      "talk:bot:install",
      name,
      secret,
      webhookUrl,
      description ?? "opencode role agent",
    ]
    for (const f of BOT_FEATURES) args.push("--feature", f)
    const r = await this.run(args)
    if (r.code === 1) {
      throw new Error(
        `talk:bot:install rejected (exit 1): ${r.stderr.trim() || r.stdout.trim()}`,
      )
    }
    if (r.code === 2) throw new Error(`a bot with webhook url ${webhookUrl} is already installed`)
    if (r.code === 3) throw new Error(`a bot with the same secret is already installed (name=${name})`)
    if (r.code !== 0) throw new OccError(args, r)

    const printed = r.stdout.match(/^ID:\s*(\d+)\s*$/m)
    if (printed) return Number(printed[1])

    // -v keeps `url` in the listing; without it the url column is stripped.
    const bots = await this.json<{ id: number; name: string; url?: string }[]>(["talk:bot:list", "-v"])
    const found = bots.find((b) => b.url === webhookUrl)
    if (!found) {
      throw new Error(`bot ${name} installed but not found in talk:bot:list (url=${webhookUrl})`)
    }
    return found.id
  }

  async setupBot(botId: number, token: string): Promise<void> {
    await this.ok(["talk:bot:setup", String(botId), token])
  }

  async removeBotFromConversation(botId: number, token: string): Promise<void> {
    await this.ok(["talk:bot:remove", String(botId), token])
  }

  async uninstallBot(botId: number): Promise<void> {
    await this.ok(["talk:bot:uninstall", String(botId)])
  }

  /** Uninstall by webhook url. Preferred: the url is the unique column. */
  async uninstallBotByUrl(webhookUrl: string): Promise<void> {
    await this.ok(["talk:bot:uninstall", "--url", webhookUrl])
  }

  async listBots(): Promise<{ id: number; name: string }[]> {
    return await this.json<{ id: number; name: string }[]>(["talk:bot:list"])
  }

  // ---- messages ----

  /**
   * Post a message as a bot.
   *
   * The signature is HMAC-SHA256(secret, random + message) and the random seed
   * must be >= 32 bytes; signing the random alone is rejected with 401.
   */
  async sendBotMessage(token: string, secret: string, message: string, random?: string): Promise<void> {
    // 64 hex chars, matching the seed length Talk itself generates.
    const rnd = random ?? crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "")
    const signature = await hmacSha256Hex(secret, rnd + message)
    const res = await fetch(
      `${this.url}/ocs/v2.php/apps/spreed/api/v1/bot/${encodeURIComponent(token)}/message`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "OCS-APIRequest": "true",
          "X-Nextcloud-Talk-Bot-Random": rnd,
          "X-Nextcloud-Talk-Bot-Signature": signature,
        },
        body: JSON.stringify({ message }),
      },
    )
    if (!res.ok) {
      throw new Error(`bot message failed: ${res.status} ${await res.text().catch(() => "")}`)
    }
  }

  async appEnable(app: string): Promise<void> {
    await this.ok(["app:enable", app])
  }
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message))
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}
