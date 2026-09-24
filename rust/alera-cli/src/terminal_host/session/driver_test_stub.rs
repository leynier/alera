use super::*;

use std::sync::mpsc::{sync_channel, Receiver};

use super::input_queue::PtyWrite;

/// Bytes queued for a test session that has no real PTY writer.
pub struct TestQueuedWrite {
    pub bytes: Vec<u8>,
    pub deferred_bytes: Option<Vec<u8>>,
}

impl Session {
    /// In-memory running session without a PTY, for driver/viewport tests:
    /// `resize` tracks dims (no master to apply them to) and no I/O works.
    pub fn driver_test_stub(id: &str, cols: u16, rows: u16) -> Session {
        Session {
            #[cfg(unix)]
            child_reaper: Arc::default(),
            instance_id: next_session_instance_id(),
            initial_agent_prompt_delivered: false,
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
            delivered_output_cursors: HashMap::new(),
            buffer: ScrollbackBuffer::new(1024, &[]),
            running: true,
            exit_code: None,
            ended_at: None,
            shell: None,
            master: None,
            input_tx: None,
            killer: None,
            #[cfg(windows)]
            process_job: None,
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

    /// Attach a drainable input queue so tests can assert host-originated writes
    /// without spawning a PTY writer thread.
    pub fn attach_test_input(&mut self) -> Receiver<TestQueuedWrite> {
        let (tx, rx) = sync_channel(64);
        self.input_tx = Some(tx);
        let (probe_tx, probe_rx) = sync_channel(64);
        std::thread::spawn(move || {
            while let Ok(write) = rx.recv() {
                let PtyWrite {
                    bytes, deferred, ..
                } = write;
                let deferred_bytes = deferred.map(|deferred| deferred.bytes);
                if probe_tx
                    .send(TestQueuedWrite {
                        bytes,
                        deferred_bytes,
                    })
                    .is_err()
                {
                    break;
                }
            }
        });
        probe_rx
    }

    pub fn mark_exited_for_test(&mut self) {
        self.running = false;
        self.input_tx = None;
        self.shell = None;
    }
}
