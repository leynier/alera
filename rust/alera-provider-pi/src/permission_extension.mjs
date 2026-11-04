const APPROVAL_TIMEOUT_MS = 120_000;
const READ_ONLY_BUILTINS = new Set(["read", "grep", "find", "ls", "tool_search"]);

function isBuiltinRead(pi, name) {
  if (!READ_ONLY_BUILTINS.has(name) || typeof pi.getAllTools !== "function") return false;
  return pi.getAllTools().some((tool) => tool.name === name &&
    tool.sourceInfo?.path === `builtin:${name === "tool_search" ? "tool-search" : name}`);
}

async function confirm(ctx, event, shutdownSignal) {
  const controller = new AbortController();
  const signals = [ctx.signal, shutdownSignal].filter(Boolean);
  let timer;
  let cancel;
  const cancelled = new Promise((resolve) => { cancel = () => resolve(false); });
  const abort = () => { controller.abort(); cancel(); };
  for (const signal of signals) {
    if (signal.aborted) abort();
    signal.addEventListener("abort", abort, { once: true });
  }
  try {
    if (controller.signal.aborted || typeof ctx.ui?.confirm !== "function") return false;
    timer = setTimeout(abort, APPROVAL_TIMEOUT_MS);
    const input = JSON.stringify(event.input ?? {}).slice(0, 2_000);
    const response = Promise.resolve(ctx.ui.confirm(`Allow ${event.toolName}?`, input, {
      signal: controller.signal, timeout: APPROVAL_TIMEOUT_MS,
    })).catch(() => false);
    return await Promise.race([response, cancelled]) === true && !controller.signal.aborted;
  } finally {
    clearTimeout(timer);
    for (const signal of signals) signal.removeEventListener("abort", abort);
    controller.abort();
  }
}

export function registerPermissionGate(pi, shutdownSignal) {
  pi.on("tool_call", async (event, ctx) => {
    try {
      if (!shutdownSignal.aborted && isBuiltinRead(pi, event.toolName)) return;
      if (await confirm(ctx, event, shutdownSignal)) return;
    } catch { /* Missing UI or tool provenance must fail closed. */ }
    return { block: true, reason: `${event.toolName} approval was declined, cancelled, or unavailable.` };
  });
}
