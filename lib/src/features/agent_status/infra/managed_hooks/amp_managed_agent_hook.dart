part of '../managed_agent_hook_installer.dart';

extension _AmpManagedAgentHook on ManagedAgentHookInstallService {
  _ManagedHookArtifact _ampArtifact() {
    return _ManagedHookArtifact(
      agentType: AgentType.amp,
      label: 'Amp status plugin',
      path: p.join(_ampConfigDir(), 'plugins', 'alera-agent-status.ts'),
      content: _ampPluginSource(),
    );
  }

  String _ampConfigDir() {
    final fromEnv = _environment['AMP_CONFIG_DIR']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (_platform == ManagedAgentHookPlatform.windows) {
      final userProfile = _environment['USERPROFILE']?.trim();
      if (userProfile != null && userProfile.isNotEmpty) {
        return p.join(userProfile, '.config', 'amp');
      }
    }
    return p.join(_homeDirectory, '.config', 'amp');
  }

  String _ampPluginSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
let warnedBadEndpoint = false
let cachedEndpointKey = ''
let cachedEndpointValues: Record<string, string> | null = null

function readEndpointFile(): Record<string, string> | null {
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
      const out: Record<string, string> = {}
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
  } catch (err: any) {
    if (err && err.code !== 'ENOENT' && !warnedBadEndpoint) {
      warnedBadEndpoint = true
      console.warn('[alera-amp-status] failed to parse endpoint file:', err.message)
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

function sanitize(value: unknown, depth = 0): unknown {
  if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value
  }
  if (value === undefined || typeof value === 'function' || typeof value === 'symbol') {
    return undefined
  }
  if (depth >= 4) {
    return String(value)
  }
  if (Array.isArray(value)) {
    return value.slice(0, 24).map((item) => sanitize(item, depth + 1)).filter((item) => item !== undefined)
  }
  if (typeof value === 'object') {
    const out: Record<string, unknown> = {}
    for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
      const sanitized = sanitize(nested, depth + 1)
      if (sanitized !== undefined) {
        out[key] = sanitized
      }
    }
    return out
  }
  return String(value)
}

async function post(hookEventName: string, extra: Record<string, unknown> = {}) {
  const coords = resolveHookCoords()
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID
  const workspaceId = process.env.ALERA_WORKSPACE_ID
  const tabId = process.env.ALERA_TAB_ID
  if (!coords.port || !coords.token || !terminalSessionId || !workspaceId || !tabId) return
  const url = `http://127.0.0.1:${coords.port}/hook/amp`
  const payload = sanitize(extra) as Record<string, unknown>
  const body = JSON.stringify({
    terminalSessionId,
    workspaceId,
    tabId,
    version: coords.version,
    payload: { hook_event_name: hookEventName, ...payload },
  })
  try {
    const options: RequestInit = {
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

export default function (amp: any) {
  amp.on('session.start', async (event: any) => {
    await post('session.start', event || {})
  })

  amp.on('agent.start', async (event: any) => {
    await post('agent.start', {
      message: event?.message ?? '',
      thread: event?.thread,
    })
  })

  amp.on('tool.call', async (event: any) => {
    await post('tool.call', {
      tool: event?.tool,
      input: event?.input,
    })
    return { action: 'allow' }
  })

  amp.on('tool.result', async (event: any) => {
    await post('tool.result', {
      tool: event?.tool,
      status: event?.status,
      result: event?.result ?? event?.output,
    })
  })

  amp.on('agent.end', async (event: any) => {
    await post('agent.end', {
      status: event?.status,
      messages: event?.messages,
      message: event?.message,
    })
  })
}
''';
}
