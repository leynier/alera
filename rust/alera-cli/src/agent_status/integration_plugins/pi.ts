// ALERA_AGENT_STATUS_MANAGED_FILE
function endpointPath() {
  if (process.env.ALERA_AGENT_HOOK_ENDPOINT) return process.env.ALERA_AGENT_HOOK_ENDPOINT
  if (!process.env.ALERA_RUNTIME_DIR) return null
  const suffix = process.platform === 'win32' ? 'endpoint.cmd' : 'endpoint.env'
  return `${process.env.ALERA_RUNTIME_DIR}/agent-hooks/${suffix}`
}

async function post(eventName, payload = {}) {
  const fs = await import('node:fs')
  const path = endpointPath()
  try {
    if (path && fs.existsSync(path)) {
      for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
        const match = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/)
        if (match) process.env[match[1]] = match[2].replace(/\r$/, '')
      }
    }
  } catch {}
  const port = process.env.ALERA_AGENT_HOOK_PORT
  const token = process.env.ALERA_AGENT_HOOK_TOKEN
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!port || !token || !terminalSessionId || !workspaceId || !tabId) return
  try {
    await fetch(`http://127.0.0.1:${port}/hook/pi`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Alera-Agent-Hook-Token': token },
      body: JSON.stringify({ terminalSessionId, workspaceId, tabId, payload: { hook_event_name: eventName, ...payload } }),
      signal: typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(1000) : undefined,
    })
  } catch {}
}

// Pi awaits every handler in turn, so a handler that waited on the network
// would stall the agent. Posts go through one queue that keeps their order.
const queue = []
let draining = false

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

function assistantText(message) {
  if (typeof message?.content === 'string') return message.content
  if (!Array.isArray(message?.content)) return ''
  return message.content.filter((part) => part?.type === 'text').map((part) => part.text ?? '').join('')
}

export default function (pi) {
  pi.on('session_start', (_event, ctx) => enqueue('session_start', { sessionId: ctx?.sessionManager?.getSessionId?.() }))
  pi.on('before_agent_start', (event, ctx) => enqueue('before_agent_start', { prompt: event?.prompt ?? '', sessionId: ctx?.sessionManager?.getSessionId?.() }))
  pi.on('agent_start', () => enqueue('agent_start'))
  pi.on('tool_execution_start', (event) => enqueue('tool_execution_start', { tool_name: event?.toolName, tool_input: event?.args }))
  pi.on('tool_execution_end', (event) => enqueue('tool_execution_end', { tool_name: event?.toolName }))
  pi.on('message_end', (event) => {
    const text = event?.message?.role === 'assistant' ? assistantText(event.message) : ''
    if (text) enqueue('message_end', { role: 'assistant', text })
  })
  // Retries, compaction and queued prompts can follow `agent_end`;
  // `agent_settled` (newer Pi) is the final signal, aborts and errors included.
  pi.on('agent_end', () => enqueue('agent_end'))
  pi.on('agent_settled', () => enqueue('agent_settled'))
  pi.on('ui_prompt_start', () => enqueue('ui_prompt_start'))
  pi.on('ui_prompt_end', () => enqueue('ui_prompt_end'))
  pi.on('session_shutdown', (_event, ctx) => enqueue('session_shutdown', { sessionId: ctx?.sessionManager?.getSessionId?.() }))
}
