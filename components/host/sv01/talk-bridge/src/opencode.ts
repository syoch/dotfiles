/**
 * Thin wrapper over the opencode HTTP API.
 *
 * Only the operations the bridge needs:
 *   - list sessions in a directory      (migration candidates)
 *   - create a session                 (new role)
 *   - rename a session                 (migration marker)
 *   - send a prompt                    (role briefing / migration handoff)
 *   - read a session's text messages   (leader fetching history on demand)
 *   - count a session's size           (migration candidate judgement)
 *
 * Shapes verified against the live server's OpenAPI doc (openapi 3.1.0):
 *   GET  /session?directory=              -> Session[]
 *        Session.time = { created, updated }. There is NO time_created /
 *        time_updated field.
 *   POST /session?directory=  body {title}   -> { id }
 *   PATCH /session/{id}?directory= body {title}
 *   POST /session/{id}/message?directory= body { agent, parts }
 *        -> { info: AssistantMessage, parts: Part[] }
 *        info.error is populated on failure; info.time = { created, completed }.
 *   GET  /session/{id}/message?directory= -> { info, parts }[]
 *        Parts are ALREADY embedded. There is no `/message/{id}/part` endpoint,
 *        so fetching parts per message would 404.
 *
 * Measured note: one session in the dotfiles repo holds ~1.2k text parts /
 * ~485k chars (~120k tokens). Body text is therefore NEVER pushed
 * proactively -- the leader fetches it explicitly when it decides it needs it.
 */

export type SessionSummary = {
  id: string
  title: string
  directory?: string
  agent?: string
  time?: { created?: number; updated?: number }
}

/** Size judgement inputs for a migration candidate. */
export type SessionStats = {
  messages: number
  text_parts: number
  chars: number
}

export type TextMessage = {
  messageId: string
  role: string
  created?: number
  completed?: number
  text: string
}

type RawMessage = {
  info?: {
    id?: string
    role?: string
    error?: { message?: string; name?: string } | null
    time?: { created?: number; completed?: number }
  }
  parts?: ({ type?: string; text?: string })[]
}

export class OpencodeError extends Error {
  constructor(
    readonly endpoint: string,
    readonly status: number,
    readonly body: string,
  ) {
    super(`opencode ${endpoint} -> ${status}: ${body.slice(0, 300)}`)
    this.name = "OpencodeError"
  }
}

export class Opencode {
  constructor(
    private readonly baseUrl: string,
    private readonly timeoutMs: number,
  ) {}

  private async req<T>(
    method: string,
    path: string,
    init?: { body?: unknown; query?: Record<string, string | undefined> },
  ): Promise<T> {
    const url = new URL(this.baseUrl + path)
    for (const [k, v] of Object.entries(init?.query ?? {})) {
      if (v !== undefined) url.searchParams.set(k, v)
    }
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs)
    try {
      const res = await fetch(url, {
        method,
        headers: init?.body ? { "Content-Type": "application/json" } : undefined,
        body: init?.body ? JSON.stringify(init.body) : undefined,
        signal: ctrl.signal,
      })
      const text = await res.text()
      if (!res.ok) throw new OpencodeError(path, res.status, text)
      if (!text) return undefined as T
      return JSON.parse(text) as T
    } finally {
      clearTimeout(timer)
    }
  }

  /** List sessions in a project directory. */
  async listSessions(directory: string): Promise<SessionSummary[]> {
    const rows = await this.req<SessionSummary[]>("GET", "/session", { query: { directory } })
    return Array.isArray(rows) ? rows : []
  }

  /** Create a session. */
  async createSession(directory: string, title: string): Promise<{ id: string }> {
    return await this.req<{ id: string }>("POST", "/session", {
      body: { title },
      query: { directory },
    })
  }

  /** Rename a session. */
  async updateSessionTitle(id: string, title: string, directory?: string): Promise<void> {
    await this.req("PATCH", `/session/${encodeURIComponent(id)}`, {
      body: { title },
      query: { directory },
    })
  }

  /**
   * Switch the model used by subsequent provider turns of a session.
   *
   * This is the runtime model switch (`POST /api/session/{id}/model`, v2 API).
   * The bridge deliberately does not pass a model per prompt: the venue's model
   * is written onto each bound session here, so `session.model` remains the
   * single source of truth and individual sessions stay individually
   * switchable (via the same endpoint or the TUI).
   */
  async switchModel(
    id: string,
    model: { providerID: string; id: string; variant?: string },
  ): Promise<void> {
    await this.req("POST", `/api/session/${encodeURIComponent(id)}/model`, {
      body: { model },
    })
  }

  /**
   * Enqueue a prompt and return immediately (204).
   *
   * opencode already serialises turns per session: a prompt sent while the
   * session is busy is admitted with `delivery: "queue"` and promoted when the
   * running turn finishes. The bridge therefore does NOT need a queue of its
   * own -- doing that only hid opencode's ordering and produced a second,
   * dead-locked layer.
   *
   * `messageID` is supplied by the caller so the reply can be correlated
   * unambiguously: the assistant message that answers this prompt has
   * `parentID === messageID`. Without it, matching by "newest assistant
   * message" is a guess that breaks as soon as turns overlap.
   */
  async promptAsync(
    sessionId: string,
    opts: {
      messageID: string
      agent?: string | null
      text: string
      directory?: string
      model?: { providerID: string; modelID: string }
    },
  ): Promise<void> {
    await this.req<void>("POST", `/session/${encodeURIComponent(sessionId)}/prompt_async`, {
      body: {
        messageID: opts.messageID,
        // MUST be "queue". The default is "steer", which injects the prompt
        // into the turn that is already running: the running turn keeps
        // generating, but its later messages are re-parented onto the injected
        // prompt. The reply to the human then never collects a body -- the
        // bridge waits on a parentID that no longer owns those messages, so the
        // answer is never posted. Measured: a role mentioning a busy role
        // silently destroys that role's in-flight answer.
        delivery: "queue",
        ...(opts.agent ? { agent: opts.agent } : {}),
        parts: [{ type: "text", text: opts.text }],
        ...(opts.model ? { model: opts.model } : {}),
      },
      query: { directory: opts.directory },
    })
  }

  /**
   * Poll until a *new* assistant message completes **with text**, then return it.
   *
   * `prevMessageId` is the newest message before the prompt was enqueued, so
   * anything newer belongs to this turn.
   *
   * Empty replies must be skipped, not returned. opencode routinely emits an
   * intermediate assistant message that completes with zero text parts before
   * the real answer a few seconds later (observed on ~half of all turns here).
   * Accepting the first completed assistant message therefore swallowed the
   * answer on roughly every other turn: `text` came back empty, the caller
   * skipped the post, and nothing appeared in the conversation.
   *
   * An assistant message with `info.error` is still a hard failure and is
   * returned immediately.
   */
  /**
   * Session liveness, keyed by session id: `{ ses_x: { type: "idle" | "busy" | "retry" } }`.
   *
   * `directory` is NOT optional in practice: `GET /session/status` with no
   * filter returns `{}` even while sessions are busy, so a caller that omits it
   * sees every session as "unknown" and never observes `idle`. Verified on the
   * live server -- this silently made every turn time out instead of replying.
   */
  async sessionStatus(directory: string): Promise<Record<string, { type: string }>> {
    const r = await this.req<Record<string, { type: string }>>("GET", "/session/status", {
      query: { directory },
    })
    return r ?? {}
  }

  /** The project directory a session belongs to. Authoritative, unlike a guess. */
  async sessionDirectory(sessionId: string): Promise<string | undefined> {
    const s = await this.req<{ directory?: string }>(
      "GET",
      `/session/${encodeURIComponent(sessionId)}`,
    )
    return s?.directory
  }

  /**
   * Wait for the reply to a specific prompt.
   *
   * Correlation is by `parentID`, never by "the newest assistant message": a
   * turn emits many assistant steps (one per tool call, no text) and several
   * text steps (commentary then the final answer), so positional guessing picks
   * the wrong one and silently drops the answer.
   *
   * The window starts small because our own reply is the newest message the
   * moment it completes, and widens on a miss so a message that raced us is
   * still found.
   */
  /**
   * Subscribe to `GET /event?directory=` and push every text part to listeners.
   *
   * Polling `/session/status` + `/session/<id>/message` costs two requests per
   * second per in-flight turn, and adds up to a full poll interval of latency to
   * every reply. The event stream carries exactly what is needed -- `part`
   * carries `messageID`, so a reply can be matched without fetching messages at
   * all.
   *
   * NOTE: the `directory` query parameter is required. Without it the stream
   * only carries `server.connected` / `server.heartbeat` and no session events
   * at all, which looks identical to "the server has nothing to say".
   */
  async events(
    directory: string,
    onEvent: (e: { type: string; properties: any }) => void,
    signal?: AbortSignal,
  ): Promise<void> {
    const url = new URL(`${this.baseUrl}/event`)
    url.searchParams.set("directory", directory)
    const res = await fetch(url, { signal, headers: { Accept: "text/event-stream" } })
    if (!res.ok || !res.body) {
      throw new OpencodeError("/event", res.status, await res.text().catch(() => ""))
    }
    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buf = ""
    for (;;) {
      const { done, value } = await reader.read()
      if (done) return
      buf += decoder.decode(value, { stream: true })
      let idx: number
      while ((idx = buf.indexOf("\n\n")) >= 0) {
        const chunk = buf.slice(0, idx)
        buf = buf.slice(idx + 2)
        for (const line of chunk.split("\n")) {
          if (!line.startsWith("data: ")) continue
          try {
            onEvent(JSON.parse(line.slice(6)))
          } catch {
            // a malformed frame must not kill the stream
          }
        }
      }
    }
  }

  /**
   * One SSE connection per directory, shared by every waiting turn.
   *
   * `GET /event?directory=` emits `message.updated` / `message.part.updated`.
   * Polling cannot tell a finished turn from an unfinished one on its own:
   * `session/status` is observed stuck in `retry` and never reaching `idle`,
   * so a reply waited for the *next* human message before it posted (measured:
   * 113s). The stream removes that dependency.
   *
   * It is used ONLY as a wake-up signal. The decision still comes from the same
   * code path as before, so the "which text is final" rule cannot drift.
   */
  private watchers = new Map<string, { waiters: (() => void)[]; abort: AbortController; ref: number }>()

  private watch(directory: string): () => void {
    let w = this.watchers.get(directory)
    if (!w) {
      const abort = new AbortController()
      w = { waiters: [], abort, ref: 0 }
      this.watchers.set(directory, w)
      const target = w
      const url = new URL(`${this.baseUrl}/event`)
      url.searchParams.set("directory", directory)
      void (async () => {
        for (;;) {
          try {
            const res = await fetch(url, {
              signal: target.abort.signal,
              headers: { Accept: "text/event-stream" },
            })
            if (!res.ok || !res.body) throw new Error(`status ${res.status}`)
            const reader = res.body.getReader()
            const dec = new TextDecoder()
            let buf = ""
            for (;;) {
              const { done, value } = await reader.read()
              if (done) return
              buf += dec.decode(value, { stream: true })
              let idx: number
              while ((idx = buf.indexOf("\n\n")) >= 0) {
                const chunk = buf.slice(0, idx)
                buf = buf.slice(idx + 2)
                const pending = target.waiters
                target.waiters = []
                for (const r of pending) r()
                void chunk
              }
            }
          } catch {
            if (target.abort.signal.aborted) return
            // The stream is an optimisation only; polling still runs on a timer,
            // so a dropped connection just costs latency, never correctness.
            await Bun.sleep(1000)
          }
        }
      })()
    }
    w.ref++
    return () => {
      const t = this.watchers.get(directory)
      if (!t) return
      t.ref--
      if (t.ref <= 0) {
        t.abort.abort()
        this.watchers.delete(directory)
      }
    }
  }

  /** Resolve on the next event for this directory, or after `ms`. */
  private waitForEvent(directory: string, ms: number): Promise<void> {
    const w = this.watchers.get(directory)
    if (!w) return Bun.sleep(ms)
    return new Promise<void>((resolve) => {
      let done = false
      const finish = () => {
        if (done) return
        done = true
        resolve()
      }
      w.waiters.push(finish)
      setTimeout(finish, ms)
    })
  }

  async awaitTurnReply(
    sessionId: string,
    promptMessageId: string,
    opts: { pollMs: number; maxWaitMs: number; directory?: string },
  ): Promise<{ text?: string; error?: string; timedOut?: boolean }> {
    const deadline = Date.now() + opts.maxWaitMs
    // Wide enough to hold every in-flight turn's steps. A narrow window makes an
    // older turn's messages fall outside it, so that turn widens and resolves
    // LATER than newer turns that happened to be inside -- replies would arrive
    // out of order.
    let limit = 30
    // `sessionStatus` needs a directory filter; without one the live server
    // returns {} and the turn can never be observed as finished.
    let directory = opts.directory
    if (!directory) {
      try {
        directory = await this.sessionDirectory(sessionId)
      } catch {
        directory = undefined
      }
    }
    const release = this.watch(directory ?? "")
    try {
      while (Date.now() < deadline) {
      // Wake on a session event; `pollMs` stays as the ceiling so a dropped
      // stream costs latency and nothing else.
      await this.waitForEvent(directory ?? "", opts.pollMs)

      // Status BEFORE messages: an `idle` seen after them could belong to a
      // turn that completed between the two calls, and we would then return a
      // body that predates its own final step.
      let status: Record<string, { type: string }> = {}
      try {
        status = await this.sessionStatus(directory ?? "")
      } catch {
        status = {}
      }
      const idle = status?.[sessionId]?.type === "idle"

      let msgs: RawMessage[]
      try {
        msgs = await this.req<RawMessage[]>("GET", `/session/${encodeURIComponent(sessionId)}/message`, {
          query: { directory: opts.directory, limit: String(limit) },
        })
      } catch {
        continue // transient; keep waiting until the deadline
      }
      const mine = (msgs ?? []).filter(
        (m) => m.info?.role === "assistant" && m.info?.parentID === promptMessageId,
      )
      if (mine.length > 0) {
        const err = mine.find((m) => m.info?.error)?.info?.error
        if (err) return { error: err.message ?? err.name ?? "unknown error" }
        // Forward order: assigning on every match leaves the NEWEST step's
        // text. Iterating in reverse would overwrite it with the oldest one.
        let lastText = ""
        for (const m of mine) {
          if (!m.info?.time?.completed) continue
          const text = (m.parts ?? [])
            .filter((p) => p.type === "text")
            .map((p) => p.text ?? "")
            .join("")
            .trim()
          if (text) lastText = text
        }
        // Completion, structural only -- no timers.
        //
        // Completion of our newest step is the load-bearing signal. A tool message is created
        // when the tool STARTS and only carries `time.completed` once it
        // returns, so while a long command runs our newest message is
        // incomplete and nothing below can fire. An earlier attempt used a
        // text-stability timer instead and posted running commentary during
        // every long tool call, because a tool produces no text and therefore
        // looked "stable".
        //
        // Our newest step being complete is the whole test. opencode never
        // interleaves turns, so nothing of ours can appear after it.
        //
        // Superseded and `idle` are both unnecessary: once our newest step is
        // complete there is provably nothing of ours left, so a reply cannot be
        // late. `idle` alone was never sufficient anyway -- a session stuck in
        // `retry` never reaches it, which is what held replies for 113s.
        //
        // Rejected: requiring our prompt to be the newest user message
        // discards every reply whenever a queue exists (measured: 9 failures).
        const oursNewest = mine[mine.length - 1]
        const oursComplete = !!oursNewest?.info?.time?.completed
        const list = msgs ?? []
        const newest = list[list.length - 1]
        const superseded =
          !!newest && !(newest.info?.role === "assistant" && newest.info?.parentID === promptMessageId)
        // Both conditions are required. Ours-newest-completed alone fires in the
        // gap between one step finishing and the next being created -- measured
        // at 22s -- and posts running commentary as the answer.
        if (lastText && oursComplete && (superseded || idle)) return { text: lastText }
      } else if (limit < 150) {
        limit = Math.min(150, limit * 2) // our reply may be buried by a racing turn
      }
      }
    } finally {
      release()
    }
    return { timedOut: true }
  }

  /**
   * Send a prompt and return the assistant reply text.
   *
   * Bounded by `timeoutMs`; prefer `promptAsync` + `awaitTurnReply` for anything
   * user-visible, since a turn can legitimately outlive this call.
   */
  async prompt(
    sessionId: string,
    opts: { agent?: string | null; text: string; directory?: string; model?: { providerID: string; modelID: string } },
  ): Promise<{ text: string; error?: string }> {
    const res = await this.req<RawMessage>("POST", `/session/${encodeURIComponent(sessionId)}/message`, {
      body: {
        ...(opts.agent ? { agent: opts.agent } : {}),
        parts: [{ type: "text", text: opts.text }],
        ...(opts.model ? { model: opts.model } : {}),
      },
      query: { directory: opts.directory },
    })
    const text = (res.parts ?? [])
      .filter((p) => p.type === "text")
      .map((p) => p.text ?? "")
      .join("")
    const err = res.info?.error
    return { text, error: err ? (err.message ?? err.name ?? "unknown error") : undefined }
  }

  /**
   * Count a session's text volume. Used to decide whether a session is worth
   * migrating. Costs one full message-list request, so callers should treat it
   * as opt-in rather than run it over every candidate by default.
   */
  async sessionStats(sessionId: string, directory?: string): Promise<SessionStats> {
    const msgs = await this.req<RawMessage[]>(
      "GET",
      `/session/${encodeURIComponent(sessionId)}/message`,
      { query: { directory } },
    )
    let text_parts = 0
    let chars = 0
    for (const m of msgs ?? []) {
      for (const p of m.parts ?? []) {
        if (p.type === "text" && p.text) {
          text_parts++
          chars += p.text.length
        }
      }
    }
    return { messages: (msgs ?? []).length, text_parts, chars }
  }

  /**
   * Read a session's text messages, most recent `limit` first.
   * Used only on explicit leader request.
   * Parts come embedded in the message list, so this is a single request.
   */
  async readTextMessages(
    sessionId: string,
    limit: number,
    directory?: string,
  ): Promise<TextMessage[]> {
    const msgs = await this.req<RawMessage[]>(
      "GET",
      `/session/${encodeURIComponent(sessionId)}/message`,
      { query: { directory } },
    )
    const out: TextMessage[] = []
    for (let i = (msgs ?? []).length - 1; i >= 0 && out.length < limit; i--) {
      const m = msgs[i]
      const text = (m.parts ?? [])
        .filter((p) => p.type === "text" && p.text)
        .map((p) => p.text ?? "")
        .join("")
      if (!text) continue
      out.push({
        messageId: m.info?.id ?? "",
        role: m.info?.role ?? "unknown",
        created: m.info?.time?.created,
        completed: m.info?.time?.completed,
        text,
      })
    }
    return out
  }
}
