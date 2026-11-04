//! Background commands the agent can say it waits on, through the injected
//! Alera MCP server's `chat_background_wait` tool.

use super::*;
use claude_agent_sdk::SystemPrompt;
use std::collections::HashSet;

/// Claude Code defers MCP tools behind ToolSearch, so the agent only finds
/// `chat_background_wait` when the system prompt says when to reach for it.
pub(super) const BACKGROUND_WAIT_INSTRUCTIONS: &str = "### Background work you wait on\n\nTo wait for a background command or Monitor you started (tests, a build), call the Alera MCP tool `chat_background_wait` with its task ID before you end your turn. Do not mark work you leave running, such as a dev server or watcher. Alera MCP tools are deferred: load one with ToolSearch before you call it.";

/// Appends [BACKGROUND_WAIT_INSTRUCTIONS] to whatever system prompt the
/// session already has. A prompt file cannot be extended in place, so it gets
/// the CLI's separate append flag unless the caller already set one.
pub(super) fn append_background_wait_instructions(options: &mut ClaudeAgentOptions) {
    let join = |prompt: &str| {
        if prompt.trim().is_empty() {
            BACKGROUND_WAIT_INSTRUCTIONS.to_owned()
        } else {
            format!("{prompt}\n\n{BACKGROUND_WAIT_INSTRUCTIONS}")
        }
    };
    options.system_prompt = Some(match options.system_prompt.take() {
        None => SystemPrompt::Text(BACKGROUND_WAIT_INSTRUCTIONS.to_owned()),
        Some(SystemPrompt::Text(prompt)) => SystemPrompt::Text(join(&prompt)),
        Some(SystemPrompt::Custom { prompt, snapshot }) => SystemPrompt::Custom {
            prompt: join(&prompt),
            snapshot,
        },
        Some(SystemPrompt::Preset {
            preset,
            append,
            exclude_dynamic_sections,
            snapshot,
        }) => SystemPrompt::Preset {
            preset,
            append: Some(join(append.as_deref().unwrap_or_default())),
            exclude_dynamic_sections,
            snapshot,
        },
        Some(file @ SystemPrompt::File { .. }) => {
            options
                .extra_args
                .entry("append-system-prompt".into())
                .or_insert_with(|| Some(BACKGROUND_WAIT_INSTRUCTIONS.to_owned()));
            file
        }
    });
}

/// Background commands of this session that are still running, by native
/// task id. Sub-agents are not here: their results return to the agent and
/// they are always awaited.
#[derive(Default)]
pub(super) struct BackgroundTasks(HashSet<String>, HashSet<String>);

impl BackgroundTasks {
    pub(super) fn observe(&mut self, kind: &EventKind, task_id: &str, background_command: bool) {
        match kind {
            EventKind::TaskStarted if background_command => {
                self.0.insert(task_id.to_owned());
            }
            EventKind::TaskCompleted => {
                self.0.remove(task_id);
                self.1.remove(task_id);
            }
            _ => {}
        }
    }

    /// Records a sub-agent task (any task but a command) that started, so a
    /// stop can be refused for ids that name nothing running.
    pub(super) fn observe_subagent(&mut self, kind: &EventKind, task_id: &str) {
        if kind == &EventKind::TaskStarted {
            self.1.insert(task_id.to_owned());
        }
    }

    pub(super) fn running_subagent(&self, task_id: &str) -> bool {
        self.1.contains(task_id)
    }

    /// The requested ids that name a running background command, once each
    /// and in request order.
    pub(super) fn matching(&self, task_ids: &[String]) -> Vec<String> {
        let mut matched: Vec<String> = Vec::new();
        for task_id in task_ids {
            if self.0.contains(task_id) && !matched.contains(task_id) {
                matched.push(task_id.clone());
            }
        }
        matched
    }

    pub(super) fn clear(&mut self) {
        self.0.clear();
        self.1.clear();
    }
}

#[cfg(test)]
#[path = "background_wait_tests.rs"]
mod tests;
