use super::{DurableOutputBatch, OutputBatch, Session};

/// Coalescing PTY output into batches, on two independent tracks.
///
/// The delivery batch is what clients receive and the durable batch is what
/// reaches the history store. They carry the same bytes but drain on their own
/// generations, so a slow writer cannot hold up delivery and a paused client
/// cannot hold up persistence.
impl Session {
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

    pub fn durable_output_batch_due(&self, generation: u64) -> bool {
        self.durable_output_batch_armed && self.durable_output_batch_gen == generation
    }

    pub fn flush_durable_output_batch(&mut self) -> Option<DurableOutputBatch> {
        if self.durable_output_batch.is_empty() {
            self.durable_output_batch_armed = false;
            return None;
        }
        self.durable_output_batch_gen = self.durable_output_batch_gen.wrapping_add(1);
        self.durable_output_batch_armed = false;
        let data = std::mem::take(&mut self.durable_output_batch);
        let sequence = self.durable_output_batch_sequence;
        self.durable_output_batch_sequence = self.durable_output_batch_sequence.wrapping_add(1);
        Some(DurableOutputBatch { data, sequence })
    }
}
