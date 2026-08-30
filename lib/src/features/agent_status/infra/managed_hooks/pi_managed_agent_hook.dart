part of '../managed_agent_hook_installer.dart';

extension _PiManagedAgentHook on ManagedAgentHookInstallService {
  _ManagedHookArtifact _piArtifact() {
    return _ManagedHookArtifact(
      agentType: AgentType.pi,
      label: 'Pi status extension',
      path: p.join(_piAgentDir(), 'extensions', 'alera-agent-status.ts'),
      content: _piExtensionSource(),
    );
  }

  String _piAgentDir() {
    final fromEnv = _environment['PI_CODING_AGENT_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return p.join(_homeDirectory, '.pi', 'agent');
  }

  String _piExtensionSource() => aleraPiStatusExtensionSource();
}

String aleraPiStatusExtensionSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
let warnedBadEndpoint = false
let cachedEndpointKey = ''
let cachedEndpointValues = null

function readEndpointFile() {
  const path = process.env.ALERA_AGENT_HOOK_ENDPOINT
  if (!path) return null
  try {
    const fs = require('fs')
    try {
      const stat = fs.statSync(path)
      const cacheKey = stat.mtimeMs + ':' + stat.size + ':' + stat.ino
      if (cacheKey === cachedEndpointKey && cachedEndpointValues) {
        return cachedEndpointValues
      }
      const contents = fs.readFileSync(path, 'utf8')
      const out = {}
      for (const line of contents.split(/\r?\n/)) {
        const m = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/)
        if (m) out[m[1]] = m[2].replace(/\r$/, '')
      }
      cachedEndpointKey = cacheKey
      cachedEndpointValues = out
      return out
    } catch (ioErr) {
      cachedEndpointKey = ''
      cachedEndpointValues = null
      throw ioErr
    }
  } catch (err) {
    if (err && err.code !== 'ENOENT' && !warnedBadEndpoint) {
      warnedBadEndpoint = true
      console.warn('[alera-pi-status] failed to parse endpoint file:', err.message)
    }
    return null
  }
}

function resolveHookCoords() {
  const fileEnv = readEndpointFile() || {}
  return {
    port: fileEnv.ALERA_AGENT_HOOK_PORT || process.env.ALERA_AGENT_HOOK_PORT,
    token: fileEnv.ALERA_AGENT_HOOK_TOKEN || process.env.ALERA_AGENT_HOOK_TOKEN,
    version: fileEnv.ALERA_AGENT_HOOK_VERSION || process.env.ALERA_AGENT_HOOK_VERSION || '',
  }
}

async function post(hookEventName, extra = {}) {
  const coords = resolveHookCoords()
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!coords.port || !coords.token || !terminalSessionId || !workspaceId || !tabId) return
  const url = `http://127.0.0.1:${coords.port}/hook/pi`
  const body = JSON.stringify({
    terminalSessionId,
    workspaceId,
    tabId,
    version: coords.version,
    payload: { hook_event_name: hookEventName, ...extra },
  })
  try {
    const options = {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Alera-Agent-Hook-Token': coords.token,
      },
      body,
    }
    if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) {
      options.signal = AbortSignal.timeout(1000)
    }
    await fetch(url, options)
  } catch {}
}

function extractAssistantText(message) {
  if (!message || typeof message !== 'object') return ''
  const content = message.content
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  let out = ''
  for (const part of content) {
    if (part && typeof part === 'object' && part.type === 'text' && typeof part.text === 'string') {
      out += part.text
    }
  }
  return out
}

export default function (pi) {
  pi.on('session_start', async (_event, ctx) => {
    await post('session_start', { sessionId: ctx?.sessionManager?.getSessionId?.() })
  })

  pi.on('before_agent_start', async (event, ctx) => {
    await post('before_agent_start', { prompt: event.prompt ?? '', sessionId: ctx?.sessionManager?.getSessionId?.() })
  })

  pi.on('agent_start', async () => {
    await post('agent_start')
  })

  pi.on('tool_execution_start', async (event) => {
    await post('tool_execution_start', {
      tool_name: event.toolName,
      tool_input: event.args,
    })
  })

  pi.on('tool_call', async (event) => {
    await post('tool_call', {
      tool_name: event.toolName,
      tool_input: event.input,
    })
  })

  pi.on('tool_execution_end', async (event) => {
    await post('tool_execution_end', {
      tool_name: event.toolName,
    })
  })

  pi.on('message_end', async (event) => {
    if (event.message?.role !== 'assistant') return
    const text = extractAssistantText(event.message)
    if (!text) return
    await post('message_end', { role: 'assistant', text })
  })

  pi.on('agent_end', async () => {
    await post('agent_end')
  })

  pi.on('session_shutdown', async (_event, ctx) => {
    await post('session_shutdown', { sessionId: ctx?.sessionManager?.getSessionId?.() })
  })
}
''';
