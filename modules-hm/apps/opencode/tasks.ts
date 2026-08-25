import { tool } from "@opencode-ai/plugin"
import { $, file, randomUUIDv7 } from "bun"
import { readdir } from "fs/promises"
import { join } from "path"
import { existsSync } from "fs"

const TASK_ROOT = "/tmp/tmux-tasks"
// Dedicated tmux session for agent tasks: one window per task. The user's
// own sessions/windows are never touched.
const OC_TMUX_SESSION = "oc-tasks"

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`
}

async function hasOcSession(): Promise<boolean> {
  try {
    await $`tmux has-session -t ${OC_TMUX_SESSION}`.quiet()
    return true
  } catch {
    return false
  }
}

// Launches the command as a new window inside the dedicated oc-tasks
// session and returns the pane id (%N). Creating a session implicitly
// creates its first window, hence the two command shapes. Retries once:
// killing the last task's window tears the session down asynchronously,
// so has-session can race a subsequent start.
async function launchWindow(command: string, name: string): Promise<string> {
  let lastError = ""
  for (let attempt = 0; attempt < 2; attempt++) {
    const create = (await hasOcSession())
      ? $`tmux new-window -d -P -F '#{pane_id}' -t ${OC_TMUX_SESSION} -n ${name} ${command}`
      : $`tmux new-session -d -P -F '#{pane_id}' -s ${OC_TMUX_SESSION} -n ${name} ${command}`
    const result = await create.text().catch((e: any) => {
      lastError = e?.stderr?.toString() ?? e?.message ?? String(e)
      return ""
    })
    const id = result.trim()
    if (id.startsWith("%")) return id
    if (!lastError) lastError = `tmux returned ${JSON.stringify(result)}`
    await Bun.sleep(150)
  }
  throw new Error(`tmux window creation failed: ${lastError}`)
}

function killPanel(paneId: string): Promise<boolean> {
  if (!paneId.startsWith("%")) return Promise.resolve(false)
  return $`tmux kill-pane -t ${paneId}`.quiet()
    .then(() => true)
    .catch(() => false)
}

// True when the pane is still alive in the tmux server.
function paneExists(paneId: string | null): Promise<boolean> {
  if (!paneId?.startsWith("%")) return Promise.resolve(false)
  return $`tmux display-message -p -t ${paneId} '#{pane_id}'`
    .text()
    .then((out) => out.trim() === paneId)
    .catch(() => false)
}

class TaskInfo {
  paneId: string | null = null
  startedAt: number | null = null

  constructor(
    public taskId: string,
    public sessionId: string,
    public command: string,
    public name: string,
  ) {}

  async kill() {
    if (this.paneId) {
      await killPanel(this.paneId)
    }
    await Promise.all([
      file(`${TASK_ROOT}/${this.taskId}.running`).delete().catch(() => {}),
      file(`${TASK_ROOT}/${this.taskId}.log`).delete().catch(() => {}),
      file(`${TASK_ROOT}/${this.taskId}.sh`).delete().catch(() => {}),
      file(`${TASK_ROOT}/${this.taskId}.json`).delete().catch(() => {}),
      file(`${TASK_ROOT}/${this.taskId}.exit`).delete().catch(() => {}),
    ])
  }

  async getLog(opts: { tail?: number; offset?: number; limit?: number } = {}): Promise<string | null> {
    const logFile = file(`${TASK_ROOT}/${this.taskId}.log`)
    if (!await logFile.exists()) return null
    if (opts.tail !== undefined) {
      return (await $`tail -n ${opts.tail} ${logFile}`.text()).trimEnd()
    }
    const text = await logFile.text()
    if (opts.offset === undefined && opts.limit === undefined) return text
    const lines = text.split("\n")
    const start = opts.offset ?? 0
    const end = opts.limit !== undefined ? start + opts.limit : lines.length
    return lines.slice(start, end).join("\n")
  }

  async saveToFile() {
    await Bun.write(`${TASK_ROOT}/${this.taskId}.json`, JSON.stringify({
      taskId: this.taskId,
      sessionId: this.sessionId,
      command: this.command,
      name: this.name,
      paneId: this.paneId,
      startedAt: this.startedAt,
    }))
  }

  async launch() {
    const script = `${TASK_ROOT}/${this.taskId}.sh`
    const logfile = `${TASK_ROOT}/${this.taskId}.log`
    const running_marker = `${TASK_ROOT}/${this.taskId}.running`
    const exitfile = `${TASK_ROOT}/${this.taskId}.exit`
    const nameQuoted = shellQuote(this.name)

    // The command block runs piped through tee so the pipeline completes
    // only after tee has fully drained the output — the marker is then
    // removed strictly after every log line hit the file. The exit code
    // travels via a side file because $? inside the pipeline belongs to tee.
    await Bun.write(script, `#!/bin/bash
{
echo "=== Task started: ${nameQuoted} at $(date) ==="
touch "${running_marker}"
${this.command}
s=$?
echo "=== Task completed: ${nameQuoted} at $(date) (exit=$s) ==="
printf '%s' "$s" > "${exitfile}"
} 2>&1 | tee -a "${logfile}"
rm -f "${running_marker}"
exit "$(cat "${exitfile}" 2>/dev/null || echo 1)"
`)
    await $`chmod +x ${script}`.catch(() => {})

    const cmd = `bash ${shellQuote(script)}`
    const paneId = await launchWindow(cmd, this.name)
    this.paneId = paneId
    this.startedAt = Date.now()
    await this.saveToFile()
  }

  async isRunning(): Promise<boolean> {
    // Pane-alive covers the startup gap before the wrapper script touches
    // the marker (a kill issued immediately after start must still see it
    // as running), and the normal running phase afterwards.
    if (await this.isPaneAlive()) return true
    return await file(`${TASK_ROOT}/${this.taskId}.running`).exists()
  }

  private async isPaneAlive(): Promise<boolean> {
    return await paneExists(this.paneId)
  }

  async waitForFinish(timeoutSeconds: number = 60): Promise<boolean> {
    if (!await this.isRunning()) return true
    const start = Date.now()
    const pollIntervalMs = 200
    while (Date.now() - start < timeoutSeconds * 1000) {
      if (!await this.isRunning()) return true
      await Bun.sleep(pollIntervalMs)
    }
    return false
  }

  async status(): Promise<"running" | "completed" | "terminated" | "killed" | "unknown"> {
    const [alive, marker] = await Promise.all([
      this.isPaneAlive(),
      file(`${TASK_ROOT}/${this.taskId}.running`).exists(),
    ])
    if (alive) return "running"
    if (marker) {
      // Stale marker: the window was closed externally while the task ran,
      // so the wrapper's cleanup lines never executed.
      await file(`${TASK_ROOT}/${this.taskId}.running`).delete().catch(() => {})
      return "terminated"
    }
    if (!await file(`${TASK_ROOT}/${this.taskId}.log`).exists()) return "unknown"
    if (!await file(`${TASK_ROOT}/${this.taskId}.json`).exists()) return "killed"
    return "completed"
  }

  static async loadFromFile(taskId: string): Promise<TaskInfo | null> {
    try {
      const data = await file(`${TASK_ROOT}/${taskId}.json`).json()
      const task = new TaskInfo(data.taskId, data.sessionId, data.command, data.name)
      task.paneId = data.paneId ?? null
      task.startedAt = data.startedAt ?? null
      return task
    } catch {
      return null
    }
  }

  static createTask(sessionId: string, command: string, name: string): TaskInfo {
    const taskId = randomUUIDv7()
    const task = new TaskInfo(taskId, sessionId, command, name)
    task.saveToFile()
    return task
  }
}

async function listTasks(contextId: string): Promise<TaskInfo[]> {
  const files = await readdir(TASK_ROOT)
  const tasks: TaskInfo[] = []
  for (const fileName of files) {
    const match = fileName.match(/^(.+)\.json$/)
    if (match) {
      const task = await TaskInfo.loadFromFile(match[1])
      if (task && task.sessionId === contextId) {
        tasks.push(task)
      }
    }
  }
  return tasks
}

async function cleanupTaskFiles(contextId?: string): Promise<{ removed: string[]; kept: number }> {
  const files = await readdir(TASK_ROOT)
  const removed: string[] = []
  let kept = 0
  for (const fileName of files) {
    const match = fileName.match(/^(.+)\.(json|log|sh|running|exit)$/)
    if (!match) continue
    const task = await TaskInfo.loadFromFile(match[1])
    if (contextId && task && task.sessionId !== contextId) { kept++; continue }
    if (task && await task.isRunning()) { kept++; continue }
    await file(`${TASK_ROOT}/${fileName}`).delete().catch(() => {})
    removed.push(fileName)
  }
  return { removed, kept }
}

export const start = tool({
  description: "Start a background task in a new window of the dedicated oc-tasks tmux session",
  args: {
    name: tool.schema.string().describe("Task name (human-readable identifier)"),
    command: tool.schema
      .string()
      .optional()
      .describe("Command to execute. Omit to run the project service definition .agents/services/<name>.sh"),
  },
  async execute(args, context) {
    const { name } = args
    let command = args.command
    if (!command?.trim()) {
      const root = context.worktree || context.directory || process.cwd()
      const defPath = join(root, ".agents", "services", `${name}.sh`)
      if (!existsSync(defPath)) {
        return JSON.stringify({
          status: "error",
          message: `command is required, or provide a service definition at .agents/services/${name}.sh (not found: ${defPath})`,
        })
      }
      command = `bash ${shellQuote(defPath)}`
    }
    const task = TaskInfo.createTask(context.sessionID, command, name)
    try {
      await task.launch()
    } catch (e: any) {
      await task.kill()
      return JSON.stringify({ status: "error", message: e?.message ?? String(e) })
    }
    return JSON.stringify({
      status: "started",
      taskId: task.taskId,
      paneId: task.paneId,
    })
  },
})

export const wait = tool({
  description: "Wait for a task to complete by polling the running marker",
  args: {
    taskId: tool.schema.string().describe("Task ID to wait for"),
    timeout: tool.schema.number().optional().describe("Timeout in seconds (default: 60)"),
  },
  async execute(args) {
    const { taskId, timeout = 60 } = args
    const task = await TaskInfo.loadFromFile(taskId)
    if (!task) {
      return JSON.stringify({ status: "error", message: `Task not found: ${taskId}` })
    }
    const success = await task.waitForFinish(timeout)
    if (success) {
      return JSON.stringify({ status: "completed", taskId })
    } else {
      return JSON.stringify({ status: "timeout", taskId, message: `Task did not complete within ${timeout} seconds` })
    }
  },
})

export const log = tool({
  description: "Get log file contents for a task",
  args: {
    taskId: tool.schema.string().describe("Task ID"),
    tail: tool.schema.number().optional().describe("Return only the last N lines"),
    offset: tool.schema.number().optional().describe("Skip first N lines (0-indexed)"),
    limit: tool.schema.number().optional().describe("Return at most N lines from offset"),
  },
  async execute(args) {
    const { taskId, tail, offset, limit } = args
    const task = await TaskInfo.loadFromFile(taskId)
    if (!task) {
      return JSON.stringify({ status: "error", message: `Task not found: ${taskId}` })
    }
    const log = await task.getLog({ tail, offset, limit })
    if (log === null) {
      return JSON.stringify({ status: "error", message: `Log file not found for task: ${taskId}` })
    }
    return JSON.stringify({ status: "ok", taskId, log })
  },
})

export const kill = tool({
  description: "Kill a running task by closing its tmux pane and removing all task files",
  args: {
    taskId: tool.schema.string().describe("Task ID to kill"),
  },
  async execute(args) {
    const { taskId } = args
    const task = await TaskInfo.loadFromFile(taskId)
    if (!task) {
      return JSON.stringify({ status: "error", message: `Task not found: ${taskId}` })
    }
    const wasRunning = await task.isRunning()
    await task.kill()
    return JSON.stringify({
      status: "killed",
      taskId,
      wasRunning,
    })
  },
})

export const list = tool({
  description: "List tasks for the current session with status, command, and timing",
  args: {},
  async execute(args, context) {
    const tasks = await listTasks(context.sessionID)
    const items = await Promise.all(tasks.map(async t => ({
      taskId: t.taskId,
      name: t.name,
      status: await t.status(),
      command: t.command,
      startedAt: t.startedAt,
    })))
    return JSON.stringify({ status: "ok", tasks: items })
  },
})

export const cleanup = tool({
  description: "Remove task files for completed tasks in the current session",
  args: {},
  async execute(args, context) {
    const result = await cleanupTaskFiles(context.sessionID)
    return JSON.stringify({
      status: "ok",
      removedCount: result.removed.length,
      keptCount: result.kept,
      removed: result.removed,
    })
  },
})
