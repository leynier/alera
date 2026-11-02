//! What an agent chat is told about Alera orchestration when its `alera`
//! chat tools are attached. Each provider gets the same rules with its own
//! native sub-agent named; Claude also learns how to load the deferred
//! tools. The runtime delivers the sections per provider (see
//! `agent_chat_runtime::production_instructions`).

/// The most one section may take: Claude receives them on its argv.
pub(crate) const INSTRUCTION_SECTION_MAX_BYTES: usize = 4_000;

const RULES: &str = "Alera orchestration, with the chat tools of the alera MCP server:
- Ordinary coding needs no Alera tools. Tools may load late: try a name once before you call it absent.
- Use a native sub-agent{native} for work on your own provider, with your settings, that finishes this turn. Use chat_delegate for anything else, including another provider's model. Run a workflow only when the user asks.
- Call chat_capabilities once before your first chat_delegate, and again only after an error or a provider change the user named. Settings go in agent.options.
- If a provider or model is unavailable, say so. Never switch to another one unasked, and never fall back to native sub-agents or the CLI instead.
- Pick one target: newWorkspace for a fresh checkout, workspace for an existing one, or chat to continue a chat. Never build a child's checkout in the shell or in the task. The whole brief goes in task.
- Every review or re-check is a new chat_delegate that carries the brief, the findings and the objections, never a chat_send to the earlier reviewer. Fix small review findings yourself.
- After an async chat_delegate, follow next and end your turn: the task wakes this chat with its result. Do not poll it with chat_task_status, chat_task_wait loops, sleep, watchers, Monitor or ScheduleWakeup.
- Stop delegates you replace or no longer need with chat_task_cancel, never chat_interrupt. When told to run fewer, cancel the extras and start no replacement.
- A delegated child's question comes to this chat as a message: read it with chat_requests and answer it with chat_respond, or ask the user when the answer is not yours to give.
- Given a chat id, chat_read it before you answer about it. Mention a chat by pasting its link from a chat or task result as is.
- Without the chat tools, run alera chat from the shell; ALERA_CHAT_CREDENTIAL_FILE is set.
- As a delegated child, do the work yourself and start no chat_delegate unless your task says to.";

const SECRETS_AND_PULL_REQUESTS: &str = "Secrets and pull requests, with the same alera chat tools:
- A secret: call request_secret yourself, with delivery file (recommended) for a shell command, or ref for alera chat secret read --ref. Never ask for one in chat or invent one; only a person answers it.
- Link each PR you create, take over, or push to: link_pull_request, full URL, as your next call. Skip PRs you only read or review. If linking fails, say so.
- Call watch_pull_request when asked to monitor or babysit a PR, or when work you were asked to do still waits on its checks or reviews. Push first, then watch and end your turn. Delegated children never watch. After PR work, a child's last line is: PR <full URL>, head <SHA>, checks and reviews <state>.
- For PR waits, no sleep, loops, gh --watch, Monitor or ScheduleWakeup. Before handback, call unwatch_pull_request on any PR you watch.";

const CLAUDE_TOOLS: &str = "The alera chat tools are deferred. Load them before the first call with ToolSearch select:mcp__alera__chat_capabilities,mcp__alera__chat_delegate,mcp__alera__chat_task_status,mcp__alera__chat_task_cancel,mcp__alera__chat_requests,mcp__alera__chat_respond,mcp__alera__chat_read,mcp__alera__request_secret,mcp__alera__link_pull_request,mcp__alera__watch_pull_request,mcp__alera__unwatch_pull_request.";

/// The instruction sections for a chat of `provider`.
pub(crate) fn orchestration_instruction_sections(provider: &str) -> Vec<String> {
    let native = match provider {
        "claudeAgent" => " (Agent with run_in_background:false)",
        "codex" => " (spawn_agent, then wait for it)",
        _ => "",
    };
    let mut sections = vec![
        RULES.replace("{native}", native),
        SECRETS_AND_PULL_REQUESTS.to_owned(),
    ];
    if provider == "claudeAgent" {
        sections.push(CLAUDE_TOOLS.to_owned());
    }
    debug_assert!(sections
        .iter()
        .all(|section| section.len() <= INSTRUCTION_SECTION_MAX_BYTES));
    sections
}

#[cfg(test)]
#[path = "instructions_tests.rs"]
mod tests;
