use super::*;

impl Session {
    /// Rebuild a non-running session from a persisted checkpoint, or `None` if
    /// there is no usable checkpoint.
    pub async fn restore_exited(
        session_id: String,
        workspace_id: String,
        tab_id: String,
        store: &TerminalHostHistoryStore,
        max_bytes: usize,
    ) -> Option<Session> {
        let checkpoint = match store.read(&session_id, max_bytes).await {
            Ok(Some(checkpoint)) => checkpoint,
            _ => return None,
        };
        let (exit_code, ended_at) = if checkpoint.ended_at.is_none() {
            (Some(-1), None)
        } else {
            (Some(checkpoint.exit_code.unwrap_or(0)), checkpoint.ended_at)
        };
        let mut title_tracker = TerminalTitleTracker::default();
        title_tracker.feed(&checkpoint.buffer);
        Some(Session {
            instance_id: next_session_instance_id(),
            id: session_id,
            workspace_id,
            tab_id,
            working_directory: checkpoint.working_directory,
            clients: HashSet::new(),
            driver: SessionDriver::Idle,
            desktop_dims: None,
            current_dims: (80, 24),
            output_paused_clients: HashSet::new(),
            output_resync_pending_clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(max_bytes, &checkpoint.buffer),
            running: false,
            exit_code,
            ended_at,
            shell: None,
            master: None,
            input_tx: None,
            killer: None,
            terminated: false,
            checkpoint_gen: 0,
            checkpoint_armed: false,
            output_batch: Vec::new(),
            output_batch_gen: 0,
            output_batch_armed: false,
            durable_output_batch: Vec::new(),
            durable_output_batch_gen: 0,
            durable_output_batch_armed: false,
            durable_output_batch_sequence: 0,
            output_stream_bytes: checkpoint
                .output_stream_bytes
                .max(checkpoint.buffer.len() as u64),
            title_tracker,
        })
    }
}
