use crate::terminal_host::session::PtyWriteCompletion;

use super::{ServerActor, ServerCommand};

const STARTUP_INPUT_DELAY_MS: u64 = 120;
const STARTUP_SUBMIT_DELAY_MS: u64 = 500;

impl ServerActor {
    pub(super) fn schedule_terminal_startup_input(
        &self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_INPUT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupInput {
                session_id,
                session_instance_id,
                interactive_shell,
                command,
            });
        });
    }

    pub(super) fn handle_terminal_startup_input(
        &mut self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        let uses_paste = crate::terminal_host::orchestration::agent_prompt_injection::should_use_bracketed_paste_for_startup(&command)
            && crate::terminal_host::orchestration::agent_prompt_injection::shell_supports_bracketed_paste(&interactive_shell);
        let bytes = if uses_paste {
            crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(&command)
        } else {
            crate::terminal_host::orchestration::agent_prompt_injection::build_plain_startup_command_bytes(&command)
        };
        let completion = if uses_paste {
            PtyWriteCompletion::StartupPaste {
                session_instance_id,
            }
        } else {
            PtyWriteCompletion::StartupPlain {
                session_instance_id,
            }
        };
        if let Err(error) = session.queue_write(completion, &bytes) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }

    pub(super) fn schedule_terminal_startup_submit(
        &self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_SUBMIT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupSubmit {
                session_id,
                session_instance_id,
            });
        });
    }

    pub(super) fn handle_terminal_startup_submit(
        &mut self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        if let Err(error) = session.queue_write(
            PtyWriteCompletion::StartupSubmit {
                session_instance_id,
            },
            crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
        ) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }
}
