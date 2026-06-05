import { tool } from "@opencode-ai/plugin"
import { $, file, randomUUIDv7 } from "bun"
import { readdir } from "fs/promises"

const TASK_ROOT = "/tmp/tmux-tasks"
const CHAR_ASPECT_RATIO = 2

type PanelInfo = {
  id: string
  top: number
  left: number
  width: number
  height: number
  pid: number
}

type SplitWindowOptions = {
  target: string
  direction: "h" | "v"
}

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`
}

function splitDirection(panel: PanelInfo): "h" | "v" {
  if (panel.width > panel.height * CHAR_ASPECT_RATIO) return "h"
  return "v"
}

async function getPanels(): Promise<PanelInfo[]> {
  const lines = (await $`tmux list-panes -F "#{pane_id} #{pane_top} #{pane_left} #{pane_width} #{pane_height} #{pane_pid}"`.text()).trim().split("\n")
  return lines.map(line => {
    const [id, top, left, width, height, pid] = line.split(" ")
    return {
      id: id ?? "-",
      top: parseInt(top ?? "0"),
      left: parseInt(left ?? "0"),
      width: parseInt(width ?? "0"),
      height: parseInt(height ?? "0"),
      pid: parseInt(pid ?? "0"),
    }
  })
}

function getPanelToSplit(panels: PanelInfo[]): SplitWindowOptions | null {
  if (panels.length === 0) return null
  if (panels.length === 1) {
    return { target: panels[0].id, direction: splitDirection(panels[0]) }
  }
  const taskPanels = panels.filter(p => p.top !== 0 || p.left !== 0)
  const source = taskPanels.length > 0 ? taskPanels : panels
  const largest = source.toSorted((a, b) => (b.width * b.height) - (a.width * a.height))[0]
  return { target: largest.id, direction: splitDirection(largest) }
}

async function spawnPanel(command: string): Promise<string | null> {
  const panels = await getPanels()
  const options = getPanelToSplit(panels)
  if (!options) {
    console.error("No panel found to split.")
    return null
  }
  const directionFlag = options.direction === "h" ? "-h" : "-v"
  const result = await $`tmux split-window -P -F "#{pane_id}" -d ${directionFlag} -t ${options.target} ${command}`.text()
  const id = result.trim()
  return id.startsWith("%") ? id : null
}

async function killPanel(paneId: string): Promise<boolean> {
  if (!paneId.startsWith("%")) return false
  try {
    await $`tmux kill-pane -t ${paneId}`.quiet()
    return true
  } catch {
    return false
  }
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
    const nameQuoted = shellQuote(this.name)

    await Bun.write(script, `#!/bin/bash
exec > >(tee -a "${logfile}") 2>&1
echo "=== Task started: ${nameQuoted} at $(date) ==="
touch "${running_marker}"
${this.command}
status=$?
echo "=== Task completed: ${nameQuoted} at $(date) (exit=$status) ==="
rm -f "${running_marker}"
exit $status
`)
    await $`chmod +x ${script}`.catch(() => {})

    const cmd = `bash ${shellQuote(script)}`
    const paneId = await spawnPanel(cmd)
    if (!paneId) {
      await file(script).delete().catch(() => {})
      throw new Error(`Failed to create tmux pane for task: ${this.taskId} (${this.name})`)
    }
    this.paneId = paneId
    this.startedAt = Date.now()
    await this.saveToFile()
  }

  async isRunning(): Promise<boolean> {
    return await file(`${TASK_ROOT}/${this.taskId}.running`).exists()
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

  async status(): Promise<"running" | "completed" | "killed" | "unknown"> {
    if (await this.isRunning()) return "running"
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
    const match = fileName.match(/^(.+)\.(json|log|sh|running)$/)
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
  description: "Start a background task in a new tmux pane",
  args: {
    name: tool.schema.string().describe("Task name (human-readable identifier)"),
    command: tool.schema.string().describe("Command to execute"),
  },
  async execute(args, context) {
    const { name, command } = args
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
