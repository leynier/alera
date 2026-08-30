// ALERA_AGENT_STATUS_MANAGED_FILE
// OpenCode v2 plugin (Plugin.define style / default export with setup).
// Posts to /hook/opencode2 so v1 and v2 stay independent while sharing
// the same normalized event names used by Alera presence.
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

function endpointPath() {
  if (process.env.ALERA_AGENT_HOOK_ENDPOINT) return process.env.ALERA_AGENT_HOOK_ENDPOINT;
  if (!process.env.ALERA_RUNTIME_DIR) return null;
  const suffix = process.platform === "win32" ? "endpoint.cmd" : "endpoint.env";
  return `${process.env.ALERA_RUNTIME_DIR}/agent-hooks/${suffix}`;
}

async function loadEndpointEnv() {
  const fs = await import("node:fs");
  const path = endpointPath();
  if (path && fs.existsSync(path)) {
    for (const line of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
      const match = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/);
      if (match) process.env[match[1]] = match[2].replace(/\r$/, "");
    }
  }
}

async function post(eventName, payload = {}) {
  await loadEndpointEnv();
  const { ALERA_AGENT_HOOK_PORT: port, ALERA_AGENT_HOOK_TOKEN: token } = process.env;
  const terminalSessionId = process.env.ALERA_TERMINAL_SESSION_ID;
  const workspaceId = process.env.ALERA_WORKSPACE_ID;
  const tabId = process.env.ALERA_TAB_ID;
  if (!port || !token || !terminalSessionId || !workspaceId || !tabId) return;
  const titleContext = await titleSessionContext(payload);
  try {
    await fetch(`http://127.0.0.1:${port}/hook/opencode2`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Alera-Agent-Hook-Token": token,
      },
      body: JSON.stringify({
        terminalSessionId,
        workspaceId,
        tabId,
        payload: { hook_event_name: eventName, ...payload, ...titleContext },
      }),
      signal:
        typeof AbortSignal !== "undefined" && AbortSignal.timeout
          ? AbortSignal.timeout(1000)
          : undefined,
    });
  } catch {}
}

async function setStatus(status, sessionId) {
  if (lastStatus === status && lastSessionId === sessionId) return;
  lastStatus = status;
  lastSessionId = sessionId;
  await post(status === "busy" ? "SessionBusy" : "SessionIdle", { sessionId });
}

function statusType(event) {
  return event?.data?.status?.type ?? event?.status?.type ?? null;
}

function textFromInputAdmitted(event) {
  const text = event?.data?.input?.data?.text;
  return typeof text === "string" && text.trim() ? text : null;
}

function textFromSessionTextEnded(event) {
  const text = event?.data?.text ?? event?.data?.part?.text;
  return typeof text === "string" && text.trim() ? text : null;
}

async function handleEvent(event) {
  if (!event?.type) return;
  const sessionId = event.sessionID ?? event.sessionId ?? event.data?.sessionID ?? event.data?.sessionId;

  if (event.type === "permission.asked") {
    await post("PermissionRequest", event.data || {});
    return;
  }
  if (event.type === "question.asked") {
    await post("AskUserQuestion", event.data || {});
    return;
  }
  if (event.type === "session.input.admitted") {
    const text = textFromInputAdmitted(event);
    if (text) await post("MessagePart", { role: "user", text, sessionId });
    await setStatus("busy", sessionId);
    return;
  }
  if (event.type === "session.text.ended") {
    const text = textFromSessionTextEnded(event);
    if (text) await post("MessagePart", { role: "assistant", text, sessionId });
    return;
  }
  // session.idle is deprecated in v2 but still emitted during the transition.
  if (event.type === "session.idle" || event.type === "session.error") {
    await setStatus("idle", sessionId);
    return;
  }
  if (event.type === "session.status") {
    const status = statusType(event);
    if (status === "busy" || status === "retry") {
      await setStatus("busy", sessionId);
      return;
    }
    if (status === "idle") {
      await setStatus("idle", sessionId);
    }
  }
}

async function setup(ctx) {
  readTitleSession = ctx?.session?.get
    ? (sessionID) => ctx.session.get({ sessionID }) : null;
  titleSessionContextById.clear();
  const stream = ctx?.event?.subscribe?.();
  if (!stream || typeof stream[Symbol.asyncIterator] !== "function") return;
  for await (const event of stream) {
    try {
      await handleEvent(event);
    } catch {}
  }
}

// Accept both Plugin.define output and a plain { id, setup } object.
export default {
  id: "alera-agent-status",
  setup,
};
