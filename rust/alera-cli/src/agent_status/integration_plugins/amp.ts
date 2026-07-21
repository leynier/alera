// ALERA_AGENT_STATUS_MANAGED_FILE
const queue = []
let draining = false

function endpointPath() {
  if (process.env.ALERA_AGENT_HOOK_ENDPOINT) return process.env.ALERA_AGENT_HOOK_ENDPOINT
  if (!process.env.ALERA_RUNTIME_DIR) return null
  const suffix = process.platform === 'win32' ? 'endpoint.cmd' : 'endpoint.env'
  return `${process.env.ALERA_RUNTIME_DIR}/agent-hooks/${suffix}`
}

async function post(eventName, payload = {}) {
  const fs = await import('node:fs')
  const path = endpointPath()
  if (path && fs.existsSync(path)) {
    for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
      const match = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/)
      if (match) process.env[match[1]] = match[2].replace(/\r$/, '')
    }
  }
  const port = process.env.ALERA_AGENT_HOOK_PORT
  const token = process.env.ALERA_AGENT_HOOK_TOKEN
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!port || !token || !terminalSessionId || !workspaceId || !tabId) return
  try {
    await fetch(`http://127.0.0.1:${port}/hook/amp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Alera-Agent-Hook-Token': token },
      body: JSON.stringify({ terminalSessionId, workspaceId, tabId, payload: { hook_event_name: eventName, ...payload } }),
      signal: typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(1000) : undefined,
    })
  } catch {}
}

async function drain() {
  if (draining) return
  draining = true
  try {
    while (queue.length) {
      const next = queue.shift()
      await post(next.eventName, next.payload)
    }
  } finally {
    draining = false
  }
}

function enqueue(eventName, payload = {}) {
  if (queue.length >= 50) queue.shift()
  queue.push({ eventName, payload })
  void drain()
}

export default function (amp) {
  amp.on('session.start', (event) => enqueue('session.start', { threadId: event?.thread?.id }))
  amp.on('agent.start', (event) => enqueue('agent.start', { threadId: event?.thread?.id, message: event?.message }))
  amp.on('tool.call', (event) => {
    enqueue('tool.call', { threadId: event?.thread?.id, tool: event?.tool, input: event?.input })
    return { action: 'allow' }
  })
  amp.on('tool.result', (event) => enqueue('tool.result', { threadId: event?.thread?.id, tool: event?.tool, input: event?.input, status: event?.status, error: event?.error, output: event?.output ?? event?.result }))
  amp.on('agent.end', (event) => enqueue('agent.end', { threadId: event?.thread?.id, status: event?.status, messages: event?.messages, message: event?.message }))
}
