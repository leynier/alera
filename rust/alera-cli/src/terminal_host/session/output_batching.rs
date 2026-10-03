use super::{DurableOutputBatch, OutputBatch, Session};

/// Coalescing PTY output into batches, on two independent tracks.
///
/// The delivery batch is what clients receive and the durable batch is what
/// reaches the history store. They carry the same bytes but drain on their own
/// generations, so a slow writer cannot hold up delivery and a paused client
/// cannot hold up persistence.
impl Session {
    pub fn arm_durable_retry_timer(&mut self, generation: u64) -> bool {
        if self.durable_retry_timer.is_some() {
            return false;
        }
        self.durable_retry_timer = Some(generation);
        true
    }

    pub fn consume_durable_retry_timer(&mut self, generation: u64) -> bool {
        if self.durable_retry_timer == Some(generation) {
            self.durable_retry_timer = None;
            return true;
        }
        false
    }

    pub fn should_pause_pty_output(&self, max_durable_bytes: usize) -> bool {
        !self.durable_output_failures.is_empty()
            || self.durable_output_batch.len() >= max_durable_bytes
    }

    pub fn defer_exit(&mut self, exit_code: i32) {
        self.deferred_exit = Some(exit_code);
    }

    pub fn has_deferred_exit(&self) -> bool {
        self.deferred_exit.is_some()
    }

    pub fn take_deferred_exit(&mut self) -> Option<i32> {
        self.deferred_exit.take()
    }

    pub fn hold_pty_ack(&mut self, ack: std::sync::mpsc::SyncSender<()>) {
        if let Some(previous) = self.pending_pty_ack.replace(ack) {
            let _ = previous.send(());
        }
    }

    pub fn take_pty_ack_if_unblocked(
        &mut self,
        max_durable_bytes: usize,
    ) -> Option<std::sync::mpsc::SyncSender<()>> {
        if self.should_pause_pty_output(max_durable_bytes) {
            None
        } else {
            self.pending_pty_ack.take()
        }
    }

    pub fn recent_output_since(&self, cursor: Option<u64>, max_bytes: usize) -> Vec<u8> {
        let (base, end) = self.output_stream_range();
        let available = end.saturating_sub(cursor.unwrap_or(base).max(base));
        self.buffer.tail(available.min(max_bytes as u64) as usize)
    }

    pub fn output_batch_len(&self) -> usize {
        self.output_batch.len()
    }

    pub fn output_stream_range(&self) -> (u64, u64) {
        (
            self.output_stream_bytes
                .saturating_sub(self.buffer.len() as u64),
            self.output_stream_bytes,
        )
    }

    /// Whether the stream has been quiet for `quiet` with nothing waiting to
    /// be delivered. The first chunk after a pause, typically a keystroke
    /// echo, can then go out at once; only a stream that keeps writing pays
    /// the coalescing delay.
    pub fn output_quiet_for(&self, quiet: std::time::Duration) -> bool {
        !self.output_batch_armed && self.last_output_at.elapsed() >= quiet
    }

    pub fn output_batch_due(&self, generation: u64) -> bool {
        self.output_batch_armed && self.output_batch_gen == generation
    }

    pub fn flush_output_batch(&mut self) -> Option<OutputBatch> {
        if self.output_batch.is_empty() {
            self.output_batch_armed = false;
            return None;
        }
        self.output_batch_gen = self.output_batch_gen.wrapping_add(1);
        self.output_batch_armed = false;
        let data = std::mem::take(&mut self.output_batch);
        Some(OutputBatch { data })
    }

    pub fn durable_output_batch_len(&self) -> usize {
        self.durable_output_batch.len()
    }

    pub fn durable_output_failure_count(&self) -> usize {
        self.durable_output_failures.len()
    }

    pub fn durable_output_batch_generation(&self) -> u64 {
        self.durable_output_batch_gen
    }

    pub fn disarm_durable_output_batch_if_empty(&mut self) {
        if self.durable_output_failures.is_empty() && self.durable_output_batch.is_empty() {
            self.durable_output_batch_armed = false;
        }
    }

    pub fn durable_output_batch_due(&self, generation: u64) -> bool {
        self.durable_output_batch_armed && self.durable_output_batch_gen == generation
    }

    pub fn flush_durable_output_batch(&mut self) -> Option<DurableOutputBatch> {
        if let Some(batch) = self.durable_output_failures.pop_front() {
            return Some(batch);
        }
        if self.durable_output_batch.is_empty() {
            self.durable_output_batch_armed = false;
            return None;
        }
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        let take_len = self
            .durable_output_batch
            .len()
            .min(super::DURABLE_OUTPUT_BATCH_MAX_BYTES);
        let data = self.durable_output_batch.drain(..take_len).collect();
        self.durable_output_batch_armed = !self.durable_output_batch.is_empty();
        let sequence = self.durable_output_batch_sequence;
        self.durable_output_batch_sequence = self.durable_output_batch_sequence.wrapping_add(1);
        Some(DurableOutputBatch { data, sequence })
    }

    /// Put a batch back after the history store rejected it. The actor keeps
    /// ownership of accepted bytes until persistence succeeds or the session
    /// reports the failure to its caller.
    pub fn restore_durable_output_batch(&mut self, batch: DurableOutputBatch) -> u64 {
        let position = self
            .durable_output_failures
            .iter()
            .position(|queued| queued.sequence > batch.sequence)
            .unwrap_or(self.durable_output_failures.len());
        self.durable_output_failures.insert(position, batch);
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        self.durable_output_batch_armed = true;
        self.durable_output_batch_gen
    }
}
