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
    await fetch(`http://127.0.0.1:${port}/hook/pi`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Alera-Agent-Hook-Token': token },
      body: JSON.stringify({ terminalSessionId, workspaceId, tabId, payload: { hook_event_name: eventName, ...payload } }),
      signal: typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(1000) : undefined,
    })
  } catch {}
}

function assistantText(message) {
  if (typeof message?.content === 'string') return message.content
  if (!Array.isArray(message?.content)) return ''
  return message.content.filter((part) => part?.type === 'text').map((part) => part.text ?? '').join('')
}

export default function (pi) {
  pi.on('before_agent_start', (event) => post('before_agent_start', { prompt: event?.prompt ?? '' }))
  pi.on('agent_start', () => post('agent_start'))
  pi.on('tool_execution_start', (event) => post('tool_execution_start', { tool_name: event?.toolName, tool_input: event?.args }))
  pi.on('tool_call', (event) => post('tool_call', { tool_name: event?.toolName, tool_input: event?.input }))
  pi.on('tool_execution_end', (event) => post('tool_execution_end', { tool_name: event?.toolName }))
  pi.on('message_end', (event) => {
    const text = event?.message?.role === 'assistant' ? assistantText(event.message) : ''
    if (text) return post('message_end', { role: 'assistant', text })
  })
  pi.on('agent_end', () => post('agent_end'))
  pi.on('session_shutdown', () => post('session_shutdown'))
}
