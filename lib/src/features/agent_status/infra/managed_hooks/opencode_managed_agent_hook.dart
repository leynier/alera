part of '../managed_agent_hook_installer.dart';

extension _OpenCodeManagedAgentHook on ManagedAgentHookInstallService {
  _ManagedHookArtifact _opencodeArtifact() {
    return _ManagedHookArtifact(
      agentType: .opencode,
      label: 'OpenCode status plugin',
      path: p.join(_opencodeConfigDir(), 'plugins', 'alera-agent-status.js'),
      content: _opencodePluginSource(),
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

String aleraOpenCodeStatusPluginSource() => r'''
// ALERA_AGENT_STATUS_MANAGED_FILE
let warnedBadEndpoint = false;
let cachedEndpointKey = "";
let cachedEndpointValues = null;
let lastStatus = "idle";
let lastSessionId = null;
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
const messageRoleById = new Map();

function readEndpointFile() {
  const path = process.env.ALERA_AGENT_HOOK_ENDPOINT;
  if (!path) return null;
  try {
    const fs = require("fs");
    try {
      const stat = fs.statSync(path);
      const cacheKey = stat.mtimeMs + ":" + stat.size + ":" + stat.ino;
      if (cacheKey === cachedEndpointKey && cachedEndpointValues) {
        return cachedEndpointValues;
      }
      const contents = fs.readFileSync(path, "utf8");
      const out = {};
      for (const line of contents.split(/\r?\n/)) {
        const m = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/);
        if (m) out[m[1]] = m[2].replace(/\r$/, "");
      }
      cachedEndpointKey = cacheKey;
      cachedEndpointValues = out;
      return out;
    } catch (ioErr) {
      cachedEndpointKey = "";
      cachedEndpointValues = null;
      throw ioErr;
    }
  } catch (err) {
    if (err && err.code !== "ENOENT" && !warnedBadEndpoint) {
      warnedBadEndpoint = true;
      console.warn("[alera-opencode-status] failed to parse endpoint file:", err.message);
    }
    return null;
  }
}

function resolveHookCoords() {
  const fileEnv = readEndpointFile() || {};
  return {
    port: fileEnv.ALERA_AGENT_HOOK_PORT || process.env.ALERA_AGENT_HOOK_PORT,
    token: fileEnv.ALERA_AGENT_HOOK_TOKEN || process.env.ALERA_AGENT_HOOK_TOKEN,
    version: fileEnv.ALERA_AGENT_HOOK_VERSION || process.env.ALERA_AGENT_HOOK_VERSION || "",
  };
}

function getStatusType(event) {
  return event?.properties?.status?.type ?? event?.status?.type ?? null;
}

function rememberMessageRole(messageID, role) {
  if (!messageID || !role) return;
  if (messageRoleById.size >= 128) {
    const first = messageRoleById.keys().next().value;
    if (first !== undefined) messageRoleById.delete(first);
  }
  messageRoleById.set(messageID, role);
}

function isStatusEvent(event) {
  return event.type === "permission.asked" ||
    event.type === "question.asked" ||
    event.type === "message.updated" ||
    event.type === "message.part.updated" ||
    event.type === "session.idle" ||
    event.type === "session.error" ||
    event.type === "session.status";
}

async function post(hookEventName, extraProperties) {
  const coords = resolveHookCoords();
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID;
  const workspaceId = process.env.ALERA_WORKSPACE_ID;
  const tabId = process.env.ALERA_TAB_ID;
  if (!coords.port || !coords.token || !terminalSessionId || !workspaceId || !tabId) return;
  const url = `http://127.0.0.1:${coords.port}/hook/opencode`;
  const titleContext = await titleSessionContext(extraProperties);
  const body = JSON.stringify({
    terminalSessionId,
    workspaceId,
    tabId,
    version: coords.version,
    payload: { hook_event_name: hookEventName, ...(extraProperties || {}), ...titleContext },
  });
  try {
    const options = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Alera-Agent-Hook-Token": coords.token,
      },
      body,
    };
    if (typeof AbortSignal !== "undefined" && AbortSignal.timeout) {
      options.signal = AbortSignal.timeout(1000);
    }
    await fetch(url, options);
  } catch {}
}

async function setStatus(next, extraProperties) {
  const sessionId = extraProperties?.sessionId;
  if (lastStatus === next && lastSessionId === sessionId) return;
  lastStatus = next;
  lastSessionId = sessionId;
  await post(next === "busy" ? "SessionBusy" : "SessionIdle", extraProperties);
}

export const AleraOpenCodeStatusPlugin = async (_ctx) => {
  readTitleSession = _ctx?.client?.session?.get
    ? (id) => _ctx.client.session.get({ path: { id } }) : null;
  titleSessionContextById.clear();
  return {
    event: async ({ event }) => {
      if (!event?.type) return;

      if (event.type === "message.updated") {
        const info = event.properties && event.properties.info;
        rememberMessageRole(info && info.id, info && info.role);
      }

      if (!isStatusEvent(event)) {
        return;
      }

      if (event.type === "permission.asked") {
        await post("PermissionRequest", event.properties || {});
        return;
      }

      if (event.type === "question.asked") {
        await post("AskUserQuestion", event.properties || {});
        return;
      }

      if (event.type === "message.updated") {
        return;
      }

      if (event.type === "message.part.updated") {
        const part = event.properties && event.properties.part;
        if (!part || part.type !== "text" || !part.text) return;
        const role = messageRoleById.get(part.messageID);
        if (!role) return;
        await post("MessagePart", { role, text: part.text, sessionId: part.sessionID });
        return;
      }

      if (event.type === "session.idle" || event.type === "session.error") {
        await setStatus("idle", { sessionId: event.properties?.sessionID });
        return;
      }

      if (event.type === "session.status") {
        const statusType = getStatusType(event);
        if (statusType === "busy" || statusType === "retry") {
          await setStatus("busy", { sessionId: event.properties?.sessionID });
          return;
        }
        if (statusType === "idle") {
          await setStatus("idle", { sessionId: event.properties?.sessionID });
        }
      }
    },
  };
};
''';
