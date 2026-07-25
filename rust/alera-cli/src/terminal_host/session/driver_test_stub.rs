use super::*;

impl Session {
    /// In-memory running session without a PTY, for driver/viewport tests:
    /// `resize` tracks dims (no master to apply them to) and no I/O works.
    pub fn driver_test_stub(id: &str, cols: u16, rows: u16) -> Session {
        Session {
            instance_id: next_session_instance_id(),
            id: id.to_string(),
            workspace_id: "workspace".to_string(),
            tab_id: format!("tab-{id}"),
            working_directory: ".".to_string(),
            clients: HashSet::new(),
            driver: SessionDriver::Idle,
            desktop_dims: None,
            current_dims: (cols, rows),
            output_paused_clients: HashSet::new(),
            output_resync_pending_clients: HashSet::new(),
            buffer: ScrollbackBuffer::new(1024, &[]),
            running: true,
            exit_code: None,
            ended_at: None,
            shell_pid: None,
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
            output_stream_bytes: 0,
            title_tracker: TerminalTitleTracker::default(),
        }
    }
}
