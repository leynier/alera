// RPC mode has no trust prompt, so Pi skips an untrusted folder's protected
// resources without saying so. As in T3 Code, each Pi session's first turn
// says why. Session replacement reruns the extension factory, which resets the
// check. An explicit `--no-approve` is deliberate and stays quiet, and a Pi
// without `isProjectTrusted` has no trust gate to explain.
export function registerProjectTrustNotice(pi, argv = process.argv) {
  let checked = false;
  pi.on("before_agent_start", (_event, ctx) => {
    if (checked) return;
    checked = true;
    if (typeof ctx?.isProjectTrusted !== "function" || ctx.isProjectTrusted()) return;
    if (argv.some((arg) => arg === "--no-approve" || arg === "-na")) return;
    ctx.ui?.notify?.(
      `Pi did not load project settings, extensions, skills, prompts, MCP servers or system prompt files for ${ctx.cwd} because the folder is not trusted. To load them, run the configured Pi executable there with the same PI_CODING_AGENT_DIR (if set), trust the folder or its parent with /trust, then start a new chat in that same workspace. To trust every project, add --approve to Pi's launch arguments; to keep them off without this notice, add --no-approve.`,
      "warning",
    );
  });
}
