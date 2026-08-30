// ALERA_AGENT_STATUS_MANAGED_FILE
let lastStatus = 'idle'
let lastSessionId = null
let readTitleSession = null;
const titleSessionContextById = new Map();

async function titleSessionContext(payload) {
  const id = payload?.sessionId ?? payload?.sessionID;
  if (!id || !readTitleSession) return { agentTitleIgnore: true };
  if (titleSessionContextById.has(id)) return titleSessionContextById.get(id);
  let timer;
  try {
    const result = await Promise.race([
      readTitleSession(id),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("session lookup timeout")), 250);
      }),
    ]);
    const info = result?.data ?? result;
    if (info?.id !== id) return { agentTitleIgnore: true };
    const context = info.parentID ? { parent_session_id: info.parentID } : {};
    if (titleSessionContextById.size >= 128) {
      titleSessionContextById.delete(titleSessionContextById.keys().next().value);
    }
    titleSessionContextById.set(id, context);
    return context;
  } catch {
    // Presence still flows when ancestry is unknown, but titles must not guess.
    return { agentTitleIgnore: true };
  } finally {
    clearTimeout(timer);
  }
}
const messageRoles = new Map()

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
  const { ALERA_AGENT_HOOK_PORT: port, ALERA_AGENT_HOOK_TOKEN: token } = process.env
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!port || !token || !terminalSessionId || !workspaceId || !tabId) return
  const titleContext = await titleSessionContext(payload);
  try {
    await fetch(`http://127.0.0.1:${port}/hook/opencode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Alera-Agent-Hook-Token': token },
      body: JSON.stringify({ terminalSessionId, workspaceId, tabId, payload: { hook_event_name: eventName, ...payload, ...titleContext } }),
      signal: typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(1000) : undefined,
    })
  } catch {}
}

async function setStatus(status, sessionId) {
  if (lastStatus === status && lastSessionId === sessionId) return
  lastStatus = status
  lastSessionId = sessionId
  await post(status === 'busy' ? 'SessionBusy' : 'SessionIdle', { sessionId })
}

export const AleraOpenCodeStatusPlugin = async (ctx) => {
  readTitleSession = ctx?.client?.session?.get
    ? (id) => ctx.client.session.get({ path: { id } }) : null;
  titleSessionContextById.clear();
  return ({
  event: async ({ event }) => {
    if (event?.type === 'permission.asked') return post('PermissionRequest', event.properties)
    if (event?.type === 'question.asked') return post('AskUserQuestion', event.properties)
    if (event?.type === 'message.updated') {
      const info = event.properties?.info
      if (info?.id && info?.role) messageRoles.set(info.id, info.role)
      return
    }
    if (event?.type === 'message.part.updated') {
      const part = event.properties?.part
      const role = part?.messageID ? messageRoles.get(part.messageID) : null
      if (part?.type === 'text' && part?.text && role) await post('MessagePart', { role, text: part.text, sessionId: part.sessionID })
      return
    }
    if (event?.type === 'session.idle' || event?.type === 'session.error') return setStatus('idle', event.properties?.sessionID)
    if (event?.type === 'session.status') {
      const status = event.properties?.status?.type ?? event.status?.type
      if (status === 'busy' || status === 'retry') return setStatus('busy', event.properties?.sessionID)
      if (status === 'idle') return setStatus('idle', event.properties?.sessionID)
    }
  },
});
}
