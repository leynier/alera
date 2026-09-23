use super::{prompt_injection, HostError, HostResult, PtyWriteCompletion, ServerActor};

impl ServerActor {
    pub(super) fn queue_orchestration_paste(
        &mut self,
        session_id: &str,
        prompt: &str,
        message_ids: Vec<String>,
        force_submit: bool,
    ) -> HostResult<()> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or_else(|| HostError::state(format!("terminal {session_id} vanished")))?;
        let session_instance_id = session.instance_id();
        let paste = prompt_injection::build_agent_prompt_paste_bytes(prompt);
        session.queue_write(
            PtyWriteCompletion::OrchestrationPaste {
                session_instance_id,
                message_ids,
                force_submit,
            },
            &paste,
        )
    }

    pub(super) fn queue_orchestration_control(
        &mut self,
        session_id: &str,
        bytes: &[u8],
    ) -> HostResult<()> {
        let session = self
            .sessions
            .get_mut(session_id)
            .filter(|session| session.running())
            .ok_or_else(|| HostError::state(format!("terminal is not running: {session_id}")))?;
        let session_instance_id = session.instance_id();
        session.queue_write(
            PtyWriteCompletion::OrchestrationEnter {
                session_instance_id,
                message_ids: Vec::new(),
            },
            bytes,
        )
    }
}
