part of '../managed_agent_hook_installer.dart';

extension _OpenCodeManagedAgentHook on ManagedAgentHookInstallService {
  _ManagedHookArtifact _opencodeArtifact() {
    final plugins = p.join(_opencodeConfigDir(), 'plugins');
    return _ManagedHookArtifact(
      agentType: .opencode,
      label: 'OpenCode status plugin',
      path: p.join(plugins, 'alera-agent-status.js'),
      content: _opencodePluginSource(),
      // The separate OpenCode 2 plugin of older versions, which OpenCode 2
      // would load beside this one under the same id.
      retiredPaths: <String>[p.join(plugins, 'alera-agent-status-v2.js')],
    );
  }

  String _opencodeConfigDir() {
    final fromEnv = _environment['OPENCODE_CONFIG_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (_platform == ManagedAgentHookPlatform.windows) {
      final appData = _environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'opencode');
      }
    }
    return p.join(_homeDirectory, '.config', 'opencode');
  }

  String _opencodePluginSource() => aleraOpenCodeStatusPluginSource();
}

/// The OpenCode status plugin, shared by OpenCode v1 and OpenCode 2. It must
/// match `rust/alera-cli/src/agent_status/integration_plugins/opencode.js`,
/// which the runtime installs; a unit test compares the two.
String aleraOpenCodeStatusPluginSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
// One plugin for OpenCode v1 and OpenCode 2, which both install as `opencode`.
// v1 (1.3.4 and later) calls `server` on a default export that has an `id`;
// OpenCode 2 calls `setup` and has no v1 compatibility layer. Each loader
// ignores the other's entry point, so the same file serves both.
let lastStatus = 'idle'
let lastSessionId = null
let readTitleSession = null
const titleSessionContextById = new Map()
const messageRoles = new Map()

async function titleSessionContext(payload) {
  const id = payload?.sessionId ?? payload?.sessionID
  if (!id || !readTitleSession) return { agentTitleIgnore: true }
  if (titleSessionContextById.has(id)) return titleSessionContextById.get(id)
  let timer
  try {
    const result = await Promise.race([
      readTitleSession(id),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('session lookup timeout')), 250)
      }),
    ])
    const info = result?.data ?? result
    if (info?.id !== id) return { agentTitleIgnore: true }
    const context = info.parentID ? { parent_session_id: info.parentID } : {}
    if (titleSessionContextById.size >= 128) {
      titleSessionContextById.delete(titleSessionContextById.keys().next().value)
    }
    titleSessionContextById.set(id, context)
    return context
  } catch {
    // Presence still flows when ancestry is unknown, but titles must not guess.
    return { agentTitleIgnore: true }
  } finally {
    clearTimeout(timer)
  }
}

// Inside tmux, screen or zellij the tab's PTY shows the multiplexer client,
// so the host must not judge this agent by that PTY's processes or output.
function terminalMultiplexer() {
  if (process.env.TMUX) return 'tmux'
  if (process.env.STY) return 'screen'
  if (process.env.ZELLIJ) return 'zellij'
  return undefined
}

function endpointPath() {
  if (process.env.ALERA_AGENT_HOOK_ENDPOINT) return process.env.ALERA_AGENT_HOOK_ENDPOINT
  if (!process.env.ALERA_RUNTIME_DIR) return null
  const suffix = process.platform === 'win32' ? 'endpoint.cmd' : 'endpoint.env'
  return `${process.env.ALERA_RUNTIME_DIR}/agent-hooks/${suffix}`
}

async function loadEndpointEnv() {
  const fs = await import('node:fs')
  const path = endpointPath()
  if (path && fs.existsSync(path)) {
    for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
      const match = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/)
      if (match) process.env[match[1]] = match[2].replace(/\r$/, '')
    }
  }
}

async function post(eventName, payload = {}) {
  await loadEndpointEnv()
  const { ALERA_AGENT_HOOK_PORT: port, ALERA_AGENT_HOOK_TOKEN: token } = process.env
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!port || !token || !terminalSessionId || !workspaceId || !tabId) return
  const titleContext = await titleSessionContext(payload)
  try {
    await fetch(`http://127.0.0.1:${port}/hook/opencode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Alera-Agent-Hook-Token': token },
      body: JSON.stringify({ terminalSessionId, workspaceId, tabId, multiplexer: terminalMultiplexer(), payload: { hook_event_name: eventName, ...payload, ...titleContext } }),
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

// OpenCode v1: events arrive through the `event` hook with `properties`.
async function handleV1Event(event) {
  if (event?.type === 'permission.asked' || event?.type === 'question.asked') {
    // The session stays busy through the prompt, so no new `busy` arrives
    // once it is answered; forget the last status so the reply can send one.
    lastStatus = 'waiting'
    return post(event.type === 'permission.asked' ? 'PermissionRequest' : 'AskUserQuestion', event.properties)
  }
  if (event?.type === 'permission.replied' || event?.type === 'question.replied' || event?.type === 'question.rejected') {
    return setStatus('busy', event.properties?.sessionID ?? lastSessionId)
  }
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
}

async function server(ctx) {
  readTitleSession = ctx?.client?.session?.get
    ? (id) => ctx.client.session.get({ path: { id } }) : null
  titleSessionContextById.clear()
  return { event: async ({ event }) => handleV1Event(event) }
}

function nonBlankText(value) {
  return typeof value === 'string' && value.trim() ? value : null
}

// OpenCode 2: events arrive on a subscribed stream with `data`.
async function handleV2Event(event) {
  if (!event?.type) return
  const sessionId = event.sessionID ?? event.sessionId ?? event.data?.sessionID ?? event.data?.sessionId
  switch (event.type) {
    case 'permission.asked':
      lastStatus = 'waiting'
      return post('PermissionRequest', event.data || {})
    // Betas name the question prompt `question.asked` or `form.created`.
    case 'question.asked':
    case 'form.created':
      lastStatus = 'waiting'
      return post('AskUserQuestion', event.data || {})
    // The session stays busy through a prompt, so no new `busy` follows it.
    case 'permission.replied':
    case 'permission.rejected':
    case 'question.replied':
    case 'question.rejected':
    case 'form.replied':
    case 'form.cancelled':
      return setStatus('busy', sessionId ?? lastSessionId)
    case 'session.execution.started':
      return setStatus('busy', sessionId)
    case 'session.execution.succeeded':
      return setStatus('idle', sessionId)
    case 'session.execution.failed':
    case 'session.execution.interrupted':
      lastStatus = 'idle'
      lastSessionId = sessionId
      return post('SessionIdle', {
        sessionId,
        status: event.type === 'session.execution.failed' ? 'error' : 'cancelled',
      })
    case 'session.input.admitted': {
      const text = nonBlankText(event.data?.input?.data?.text)
      if (text) await post('MessagePart', { role: 'user', text, sessionId })
      return setStatus('busy', sessionId)
    }
    case 'session.text.ended': {
      const text = nonBlankText(event.data?.text ?? event.data?.part?.text)
      if (text) await post('MessagePart', { role: 'assistant', text, sessionId })
      return
    }
    // session.idle is deprecated in v2 but still emitted during the transition.
    case 'session.idle':
    case 'session.error':
      return setStatus('idle', sessionId)
    case 'session.status': {
      const status = event.data?.status?.type ?? event.status?.type ?? null
      if (status === 'busy' || status === 'retry') return setStatus('busy', sessionId)
      if (status === 'idle') return setStatus('idle', sessionId)
    }
  }
}

async function consume(stream) {
  for await (const event of stream) {
    try {
      await handleV2Event(event)
    } catch {}
  }
}

// The background service (`serve --service`) is shared by every terminal and
// carries the environment of whichever one started it, so events there cannot
// be attributed to a tab. Alera launches OpenCode 2 with `--standalone`, whose
// private server (`serve --stdio`) inherits the tab's own environment.
function runsInSharedService() {
  return process.argv.includes('--service')
}

// setup must return: OpenCode awaits it while loading plugins. The stream is
// consumed in the background, and the returned function is OpenCode's cleanup.
function setup(ctx) {
  readTitleSession = ctx?.session?.get
    ? (sessionID) => ctx.session.get({ sessionID }) : null
  titleSessionContextById.clear()
  if (runsInSharedService()) return undefined
  const controller = typeof AbortController === 'function' ? new AbortController() : null
  const stream = ctx?.event?.subscribe?.(controller ? { signal: controller.signal } : undefined)
  if (!stream || typeof stream[Symbol.asyncIterator] !== 'function') return undefined
  void consume(stream).catch(() => {})
  return () => controller?.abort()
}

export default {
  id: 'alera-agent-status',
  server,
  setup,
}
''';
