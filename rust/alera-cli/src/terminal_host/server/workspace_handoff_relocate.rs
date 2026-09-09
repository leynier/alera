//! Best-effort cwd change and agent notify after hand off / hand on.
//!
//! A dead PTY, missing writer, or agent TUI that cannot take a shell `cd`
//! must not fail the git handoff. Those sessions are skipped and logged.

use std::time::Duration;

use crate::terminal_host::orchestration::agent_prompt_injection as prompt_injection;
use crate::terminal_host::orchestration::message_delivery::{
    skips_auto_enter, DEFERRED_ENTER_DELAY_MS,
};
use crate::terminal_host::session::PtyWriteCompletion;

#[cfg(windows)]
use super::terminal_launch_defaults::cmd_quote;
#[cfg(not(windows))]
use super::terminal_launch_defaults::sh_quote;
use super::ServerActor;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum WorkspaceHandoffDirection {
    HandOff,
    HandOn,
}

impl WorkspaceHandoffDirection {
    fn as_label(self) -> &'static str {
        match self {
            Self::HandOff => "hand off",
            Self::HandOn => "hand on",
        }
    }
}

pub(super) fn handoff_notify_message(
    direction: WorkspaceHandoffDirection,
    from: &str,
    to: &str,
) -> String {
    format!("{} happened: {from} → {to}", direction.as_label())
}

pub(super) fn handoff_chdir_bytes(path: &str) -> Vec<u8> {
    #[cfg(windows)]
    {
        format!("cd /d {}\r", cmd_quote(path)).into_bytes()
    }
    #[cfg(not(windows))]
    {
        format!("cd {} || true\r", sh_quote(path)).into_bytes()
    }
}

fn canonical_path(path: &str) -> String {
    let target = std::path::Path::new(path);
    if let Ok(resolved) = std::fs::canonicalize(target) {
        return resolved
            .to_string_lossy()
            .trim_end_matches(['/', '\\'])
            .to_string();
    }
    path.trim_end_matches(['/', '\\']).to_string()
}

pub(super) fn path_is_same_or_within(path: &str, root: &str) -> bool {
    let path = canonical_path(path);
    let root = canonical_path(root);
    if path.eq_ignore_ascii_case(&root) {
        return true;
    }
    let prefix_slash = format!("{root}/");
    let prefix_backslash = format!("{root}\\");
    path.starts_with(&prefix_slash) || path.starts_with(&prefix_backslash)
}

impl ServerActor {
    pub(super) fn relocate_sessions_after_handoff(
        &mut self,
        direction: WorkspaceHandoffDirection,
        source_workspace_id: &str,
        source_path: &str,
        dest_path: &str,
    ) {
        if source_path == dest_path || dest_path.trim().is_empty() {
            return;
        }
        let message = handoff_notify_message(direction, source_path, dest_path);
        let session_ids: Vec<String> = self
            .sessions
            .iter()
            .filter(|(_, session)| {
                session.workspace_id == source_workspace_id
                    || path_is_same_or_within(&session.working_directory, source_path)
            })
            .map(|(session_id, _)| session_id.clone())
            .collect();
        for session_id in session_ids {
            self.relocate_one_session(&session_id, dest_path, &message);
        }
    }

    fn relocate_one_session(&mut self, session_id: &str, dest_path: &str, message: &str) {
        let has_agent = self.agent_presence.has(session_id);
        let injection_ready = self.agent_presence.is_injection_ready(session_id);
        let skip_enter =
            skips_auto_enter(self.agent_presence.agent_type(session_id)) || !injection_ready;
        if has_agent {
            self.notify_handoff_agent(session_id, dest_path, message, skip_enter);
        } else {
            self.chdir_handoff_session(session_id, dest_path);
        }
    }

    fn chdir_handoff_session(&mut self, session_id: &str, dest_path: &str) {
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        if !session.running() {
            tracing::info!(
                session_id,
                "skipping handoff chdir: terminal is not running"
            );
            return;
        }
        let bytes = handoff_chdir_bytes(dest_path);
        if let Err(error) = session.queue_write(PtyWriteCompletion::BestEffort, &bytes) {
            tracing::warn!(
                session_id,
                error = error.wire_message(),
                "skipping handoff chdir: could not write to the terminal"
            );
            return;
        }
        session.working_directory = dest_path.to_string();
    }

    fn notify_handoff_agent(
        &mut self,
        session_id: &str,
        dest_path: &str,
        message: &str,
        skip_enter: bool,
    ) {
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        if !session.running() {
            tracing::info!(
                session_id,
                "skipping handoff agent notify: terminal is not running"
            );
            return;
        }
        let paste = prompt_injection::build_agent_prompt_paste_bytes(message);
        let queued = if skip_enter {
            session.queue_write(PtyWriteCompletion::BestEffort, &paste)
        } else {
            session.queue_write_deferred(
                PtyWriteCompletion::BestEffort,
                &paste,
                Duration::from_millis(DEFERRED_ENTER_DELAY_MS),
                prompt_injection::AGENT_PROMPT_SUBMIT,
            )
        };
        if let Err(error) = queued {
            tracing::warn!(
                session_id,
                error = error.wire_message(),
                "skipping handoff agent notify: could not write to the terminal"
            );
            return;
        }
        session.working_directory = dest_path.to_string();
    }

    pub(super) fn relocate_sessions_after_hand_on(
        &mut self,
        source_workspace_id: &str,
        source_path: &str,
        dest_path: &str,
    ) {
        self.relocate_sessions_after_handoff(
            WorkspaceHandoffDirection::HandOn,
            source_workspace_id,
            source_path,
            dest_path,
        );
    }
}

#[cfg(test)]
#[path = "workspace_handoff_relocate_tests.rs"]
mod tests;
#[cfg(test)]
#[path = "workspace_handoff_relocate_timing_tests.rs"]
mod timing_tests;
