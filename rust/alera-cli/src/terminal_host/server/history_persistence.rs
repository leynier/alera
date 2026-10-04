use super::*;
use crate::terminal_host::session::{DurableOutputBatch, DURABLE_OUTPUT_BATCH_MAX_BYTES};

#[cfg(test)]
#[path = "history_persistence_tests.rs"]
mod history_persistence_tests;

impl ServerActor {
    pub(super) async fn handle_durable_output_batch_tick(
        &mut self,
        session_id: String,
        generation: u64,
    ) {
        let generation = self
            .sessions
            .get_mut(&session_id)
            .map_or(generation, |session| {
                if session.consume_durable_retry_timer(generation) {
                    session.durable_output_batch_generation()
                } else {
                    generation
                }
            });
        let session_due = self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.durable_output_batch_due(generation));
        let writer_due = self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.durable_output_batch_generation() == generation)
            && self
                .history_writers
                .get(&session_id)
                .is_some_and(|writer| writer.pending_len() > 0);
        if session_due || writer_due {
            self.flush_durable_output_batch(&session_id).await;
        }
        self.run_deferred_exit_if_settled(&session_id).await;
        if self
            .sessions
            .get(&session_id)
            .is_some_and(Session::termination_requested)
        {
            self.terminate_sessions(vec![session_id]).await;
        }
    }

    pub(super) async fn flush_durable_output_batch(&mut self, session_id: &str) {
        if !self.sessions.contains_key(session_id) {
            if !self.history_writers.contains_key(session_id) {
                return;
            }
            tracing::error!(
                session_id,
                "history flush requested for a missing session; retaining the writer"
            );
            return;
        }
        if self
            .sessions
            .get(session_id)
            .is_some_and(Session::checkpoint_output_blocked)
        {
            // A checkpoint worker has already taken the metadata barrier. Keep
            // admitted PTY bytes in the session's bounded live batch until the
            // worker completes, so history order stays ahead of the snapshot.
            self.schedule_history_retry(session_id);
            return;
        }
        self.collect_history_writer_completions(session_id);
        if let Some(writer) = self.history_writers.get(session_id) {
            if writer.failed() {
                if writer.pending_len() > 0 {
                    self.schedule_history_retry(session_id);
                    return;
                }
                self.retire_history_writer(session_id);
            }
        }
        let batch = self
            .sessions
            .get_mut(session_id)
            .and_then(Session::flush_durable_output_batch);
        let Some(batch) = batch else {
            let generation = self
                .sessions
                .get(session_id)
                .map(Session::durable_output_batch_generation);
            if let Some(generation) = generation {
                if self
                    .history_writers
                    .get(session_id)
                    .is_some_and(|writer| writer.pending_len() > 0)
                {
                    self.spawn_durable_output_batch_timer(session_id.to_string(), generation);
                }
            }
            self.release_pty_ack_if_unblocked(session_id);
            return;
        };
        let store = self.store.clone();
        let inbox = self.inbox.clone();
        let writer = self
            .history_writers
            .entry(session_id.to_string())
            .or_insert_with(|| {
                history_writer::OrderedHistoryWriter::new(store, session_id.to_string(), inbox)
            });
        if let Err(failure) = writer.try_enqueue(session_id, batch) {
            let queue_full = failure.error.to_string() == "history writer queue is full";
            tracing::error!(
                session_id,
                error = %failure.error,
                queue_full,
                "terminal history write did not accept the output batch; retaining it"
            );
            self.restore_failed_history_batch(
                session_id,
                failure.batch,
                if queue_full {
                    "writer queue is full"
                } else {
                    "enqueue failed"
                },
            );
            return;
        }
        let writer_pending = writer.pending_len() > 0;
        let next_generation = self.sessions.get_mut(session_id).and_then(|session| {
            if session.durable_output_failure_count() == 0
                && session.durable_output_batch_len() == 0
            {
                session.disarm_durable_output_batch_if_empty();
                writer_pending.then_some(session.durable_output_batch_generation())
            } else {
                Some(session.durable_output_batch_generation())
            }
        });
        if let Some(generation) = next_generation {
            self.spawn_durable_output_batch_timer(session_id.to_string(), generation);
        }
        self.release_pty_ack_if_unblocked(session_id);
    }

    pub(super) async fn handle_history_writer_ready(&mut self, session_id: &str) {
        self.collect_history_writer_completions(session_id);
        self.release_pty_ack_if_unblocked(session_id);
        self.run_deferred_exit_if_settled(session_id).await;
    }

    pub(super) fn collect_history_writer_completions(&mut self, session_id: &str) {
        if !self.sessions.contains_key(session_id) {
            tracing::error!(
                session_id,
                "history writer completion arrived after its session disappeared; retaining the writer"
            );
            return;
        }
        let failures = self
            .history_writers
            .get_mut(session_id)
            .map(|writer| writer.poll_completed())
            .unwrap_or_default();
        for failure in failures {
            tracing::error!(
                session_id,
                error = %failure.error,
                "terminal history writer failed; retaining the accepted output batch"
            );
            self.restore_failed_history_batch(session_id, failure.batch, "completion failed");
        }
    }

    fn retire_history_writer(&mut self, session_id: &str) {
        let Some(mut writer) = self.history_writers.remove(session_id) else {
            return;
        };
        if writer.pending_len() == 0 {
            writer.stop_when_idle();
        } else {
            self.history_writers.insert(session_id.to_string(), writer);
        }
    }

    pub(super) fn schedule_history_retry(&mut self, session_id: &str) {
        if let Some(generation) = self
            .sessions
            .get(session_id)
            .map(Session::durable_output_batch_generation)
        {
            self.spawn_durable_output_batch_timer(session_id.to_string(), generation);
        }
    }

    pub(super) async fn handle_checkpoint_job_finished(
        &mut self,
        session_id: &str,
        job: tokio::task::Id,
    ) {
        let result = match self.sessions.get_mut(session_id) {
            Some(session) => session.join_checkpoint_job(job).await,
            None => None,
        };
        if let Some(result) = result {
            self.finish_checkpoint_completion(session_id, result);
        }
        self.run_deferred_exit_if_settled(session_id).await;
    }

    async fn collect_checkpoint_completion(&mut self, session_id: &str) {
        let result = if let Some(session) = self.sessions.get_mut(session_id) {
            session.poll_checkpoint_job().await
        } else {
            None
        };
        if let Some(result) = result {
            self.finish_checkpoint_completion(session_id, result);
        }
    }

    fn finish_checkpoint_completion(&mut self, session_id: &str, result: Result<(), String>) {
        let success = result.is_ok();
        if let Err(error) = result {
            tracing::error!(session_id, error, "terminal checkpoint worker failed");
        }
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.finish_checkpoint_job(success);
            if !success {
                session.rearm_checkpoint();
            }
        }
        if success {
            self.release_pty_ack_if_unblocked(session_id);
        } else {
            self.schedule_checkpoint_retry(session_id);
        }
    }

    pub(super) fn release_pty_ack_if_unblocked(&mut self, session_id: &str) {
        let unblocked = self.sessions.get(session_id).is_some_and(|session| {
            !session.history_barrier_held()
                && !session.checkpoint_output_blocked()
                && !session.should_pause_pty_output(DURABLE_OUTPUT_BATCH_MAX_BYTES)
        });
        if !unblocked {
            return;
        }
        self.inbox.resume_pty_session(session_id);
        let ack = self
            .sessions
            .get_mut(session_id)
            .and_then(|session| session.take_pty_ack_if_unblocked(DURABLE_OUTPUT_BATCH_MAX_BYTES));
        if let Some(ack) = ack {
            let _ = ack.send(());
        }
    }

    fn restore_failed_history_batch(
        &mut self,
        session_id: &str,
        batch: DurableOutputBatch,
        reason: &str,
    ) {
        tracing::warn!(
            session_id,
            sequence = batch.sequence,
            reason,
            "terminal history persistence is blocked; session remains retained for retry"
        );
        self.inbox.pause_pty_session(session_id);
        if let Some(session) = self.sessions.get_mut(session_id) {
            let generation = session.restore_durable_output_batch(batch);
            self.spawn_durable_output_batch_timer(session_id.to_string(), generation);
        }
    }

    pub(super) async fn flush_all_output(&mut self, session_id: &str) {
        self.flush_output_batch(session_id);
        self.flush_durable_output_batch(session_id).await;
    }

    pub(super) fn hold_history_barrier(&mut self, session_id: &str) {
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.hold_history_barrier();
            self.inbox.pause_pty_session(session_id);
        }
    }

    pub(super) async fn handle_checkpoint_tick(&mut self, session_id: String, generation: u64) {
        let generation = self
            .sessions
            .get_mut(&session_id)
            .map_or(generation, |session| {
                if session.consume_checkpoint_retry_timer(generation) {
                    session.checkpoint_generation()
                } else {
                    generation
                }
            });
        self.collect_checkpoint_completion(&session_id).await;
        let due = self
            .sessions
            .get_mut(&session_id)
            .is_some_and(|session| session.checkpoint_due(generation));
        if self
            .sessions
            .get(&session_id)
            .is_some_and(Session::checkpoint_job_active)
        {
            if due {
                let generation = self
                    .sessions
                    .get_mut(&session_id)
                    .map(Session::rearm_checkpoint);
                if let Some(generation) = generation {
                    self.spawn_checkpoint_timer(session_id, generation);
                }
            } else {
                self.schedule_checkpoint_retry(&session_id);
            }
            return;
        }
        if !due {
            return;
        }
        self.flush_durable_output_batch(&session_id).await;
        if !self.await_output_writes(&session_id).await {
            self.schedule_checkpoint_retry(&session_id);
            return;
        }
        self.spawn_checkpoint_job(&session_id);
    }

    pub(super) async fn immediate_checkpoint(&mut self, session_id: &str) {
        self.flush_durable_output_batch(session_id).await;
        if !self.await_output_writes(session_id).await {
            self.schedule_checkpoint_retry(session_id);
            return;
        }
        let active = self
            .sessions
            .get(session_id)
            .is_some_and(Session::checkpoint_job_active);
        if active {
            let generation = self.sessions.get_mut(session_id).map(|session| {
                session.invalidate_checkpoint();
                session.rearm_checkpoint()
            });
            if let Some(generation) = generation {
                self.spawn_checkpoint_timer(session_id.to_string(), generation);
            }
            return;
        }
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.invalidate_checkpoint();
        }
        self.spawn_checkpoint_job(session_id);
    }

    fn schedule_checkpoint_retry(&mut self, session_id: &str) {
        if let Some(generation) = self
            .sessions
            .get_mut(session_id)
            .map(Session::rearm_checkpoint)
        {
            self.spawn_checkpoint_timer(session_id.to_string(), generation);
        }
    }

    fn spawn_checkpoint_job(&mut self, session_id: &str) {
        if self
            .sessions
            .get(session_id)
            .is_some_and(Session::checkpoint_job_active)
        {
            self.schedule_checkpoint_retry(session_id);
            return;
        }
        // Freeze new PTY admission while this snapshot and trim run. History
        // is flushed before this point, so the worker observes a stable
        // metadata/output order and the actor remains free for controls.
        self.inbox.pause_pty_session(session_id);
        let Some((checkpoint, max_bytes, generation)) =
            self.sessions.get(session_id).map(|session| {
                (
                    session.checkpoint_snapshot(),
                    self.config.scrollback_bytes as usize,
                    session.checkpoint_generation(),
                )
            })
        else {
            return;
        };
        let store = self.store.clone();
        let inbox = self.inbox.clone();
        let session_id_owned = session_id.to_string();
        let job = tokio::spawn(async move {
            let result = async {
                store
                    .upsert(checkpoint)
                    .await
                    .map_err(|error| format!("checkpoint write failed: {error}"))?;
                store
                    .trim_session(&session_id_owned, max_bytes)
                    .await
                    .map_err(|error| format!("checkpoint trim failed: {error}"))
            }
            .await;
            // PTY admission stays paused until the actor collects this job.
            // The checkpoint timer remains the fallback if this wake is lost.
            let _ = inbox
                .send_wait(ServerCommand::CheckpointJobFinished {
                    session_id: session_id_owned,
                    job: tokio::task::id(),
                })
                .await;
            result
        });
        let accepted = self
            .sessions
            .get_mut(session_id)
            .is_some_and(|session| session.begin_checkpoint_job(job));
        if accepted {
            self.spawn_checkpoint_timer(session_id.to_string(), generation);
        }
    }

    /// Drain accepted writes. A failed writer stays in the map so the owning
    /// session cannot be removed as if its history had been persisted.
    pub(super) async fn await_output_writes(&mut self, session_id: &str) -> bool {
        if !self.sessions.contains_key(session_id) {
            if !self.history_writers.contains_key(session_id) {
                return true;
            }
            tracing::error!(
                session_id,
                "history drain requested for a missing session; retaining the writer"
            );
            return false;
        }
        self.collect_checkpoint_completion(session_id).await;
        self.collect_history_writer_completions(session_id);
        let writer_pending = self
            .history_writers
            .get(session_id)
            .is_some_and(|writer| writer.pending_len() > 0);
        if writer_pending {
            self.inbox.pause_pty_session(session_id);
            self.schedule_history_retry(session_id);
            return false;
        }
        self.retire_history_writer(session_id);
        let pending_session_output = self.sessions.get(session_id).is_some_and(|session| {
            session.durable_output_failure_count() > 0
                || session.durable_output_batch_len() > 0
                || session.checkpoint_output_blocked()
        });
        if pending_session_output {
            self.inbox.pause_pty_session(session_id);
            false
        } else {
            self.release_pty_ack_if_unblocked(session_id);
            true
        }
    }
}
