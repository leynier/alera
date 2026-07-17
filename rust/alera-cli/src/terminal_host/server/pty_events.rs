use super::*;

impl ServerActor {
    pub(super) async fn handle_pty_event(&mut self, session_id: String, pty_event: PtyEvent) {
        match pty_event {
            PtyEvent::Output(data) => self.handle_pty_output(session_id, data).await,
            PtyEvent::Error(message) => {
                self.flush_all_output(&session_id);
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    let payload = session.error_payload(&message);
                    let clients: Vec<u64> = session.clients.iter().copied().collect();
                    self.broadcast(&clients, event("error", payload));
                }
            }
            PtyEvent::InputWritten { completion, error } => {
                self.handle_pty_input_written(session_id, completion, error)
                    .await;
            }
            PtyEvent::Exit(code) => self.handle_session_exit(session_id, code).await,
        }
    }

    async fn handle_pty_output(&mut self, session_id: String, data: Vec<u8>) {
        let state = self.sessions.get_mut(&session_id).map(|session| {
            let (output_generation, durable_generation) = session.append_output(&data);
            (
                output_generation,
                session.output_batch_len(),
                durable_generation,
                session.durable_output_batch_len(),
                session.arm_checkpoint(),
            )
        });
        let Some((output_generation, output_len, durable_generation, durable_len, checkpoint)) =
            state
        else {
            return;
        };
        self.record_orchestration_output_activity(&session_id).await;
        if let Some(generation) = output_generation {
            self.spawn_output_batch_timer(session_id.clone(), generation);
        }
        if let Some(generation) = durable_generation {
            self.spawn_durable_output_batch_timer(session_id.clone(), generation);
        }
        if output_len >= OUTPUT_BATCH_MAX_BYTES {
            self.flush_output_batch(&session_id);
        }
        if durable_len >= OUTPUT_BATCH_MAX_BYTES {
            self.flush_durable_output_batch(&session_id);
        }
        if let Some(generation) = checkpoint {
            self.spawn_checkpoint_timer(session_id, generation);
        }
    }

    async fn record_orchestration_output_activity(&mut self, session_id: &str) {
        if self
            .orchestration_activity_last_recorded
            .get(session_id)
            .is_some_and(|last| last.elapsed() < ORCHESTRATION_ACTIVITY_WRITE_INTERVAL)
        {
            return;
        }
        let dispatch = match self
            .runtime_store
            .active_orchestration_dispatch_for_handle(session_id)
            .await
        {
            Ok(dispatch) => dispatch,
            Err(_) => return,
        };
        self.orchestration_activity_last_recorded
            .insert(session_id.to_string(), Instant::now());
        let Some(dispatch) = dispatch else {
            return;
        };
        let _ = self
            .runtime_store
            .record_orchestration_activity(&dispatch.id)
            .await;
    }

    async fn handle_pty_input_written(
        &mut self,
        session_id: String,
        completion: PtyWriteCompletion,
        error: Option<String>,
    ) {
        match completion {
            PtyWriteCompletion::ClientRequest {
                client_id,
                request_id,
            } => match error {
                Some(message) => self.client_write(
                    client_id,
                    crate::terminal_host::protocol::error_response(
                        request_id,
                        &HostError::state(message),
                    ),
                ),
                None => {
                    self.client_write(
                        client_id,
                        crate::terminal_host::protocol::ok_response(request_id, json!({})),
                    );
                    self.retry_backpressured_delivery_if_idle(&session_id).await;
                }
            },
            PtyWriteCompletion::OrchestrationPaste {
                session_instance_id,
                message_ids,
                force_submit,
            } => {
                if let Some(message) = error {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    self.broadcast_terminal_error(&session_id, message);
                    return;
                }
                if self.sessions.get(&session_id).map(Session::instance_id)
                    != Some(session_instance_id)
                {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    return;
                }
                if !force_submit && skips_auto_enter(self.agent_presence.agent_type(&session_id)) {
                    if !message_ids.is_empty() {
                        let delivered = self
                            .runtime_store
                            .mark_orchestration_messages_delivered(&message_ids)
                            .await
                            .is_ok();
                        self.orchestration_delivery_in_flight.remove(&session_id);
                        if delivered && self.agent_presence.is_injection_ready(&session_id) {
                            self.deliver_pending_messages(&session_id).await;
                        }
                    }
                    return;
                }
                self.schedule_orchestration_enter(
                    session_id,
                    session_instance_id,
                    message_ids,
                    force_submit,
                );
            }
            PtyWriteCompletion::OrchestrationEnter {
                session_instance_id,
                message_ids,
            } => {
                let current = self.sessions.get(&session_id).map(Session::instance_id);
                if error.is_some() || current != Some(session_instance_id) {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                    if let Some(message) = error {
                        self.broadcast_terminal_error(&session_id, message);
                    }
                    return;
                }
                let message_backed = !message_ids.is_empty();
                let delivered = !message_backed
                    || self
                        .runtime_store
                        .mark_orchestration_messages_delivered(&message_ids)
                        .await
                        .is_ok();
                if message_backed {
                    self.orchestration_delivery_in_flight.remove(&session_id);
                }
                if delivered
                    && self.agent_presence.is_injection_ready(&session_id)
                    && (message_backed
                        || self
                            .orchestration_delivery_backpressured
                            .contains(&session_id))
                {
                    self.deliver_pending_messages(&session_id).await;
                }
            }
        }
    }

    pub(super) async fn handle_session_exit(&mut self, session_id: String, exit_code: i32) {
        let reason = format!("terminal exited with code {exit_code}");
        self.cleanup_orchestration_for_closed_session(&session_id, &reason)
            .await;
        self.flush_all_output(&session_id);
        let broadcast = self.sessions.get_mut(&session_id).and_then(|session| {
            let payload = session.handle_exit(exit_code)?;
            let clients: Vec<u64> = session.clients.iter().copied().collect();
            Some((event("exit", payload), clients))
        });
        if let Some((frame, clients)) = broadcast {
            self.broadcast(&clients, frame);
            self.immediate_checkpoint(&session_id).await;
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn cleanup_orchestration_for_closed_session(
        &mut self,
        session_id: &str,
        reason: &str,
    ) {
        self.agent_presence.remove(session_id);
        self.orchestration_activity_last_recorded.remove(session_id);
        self.orchestration_delivery_in_flight.remove(session_id);
        self.orchestration_delivery_backpressured.remove(session_id);
        self.fail_active_dispatch_for_closed_session(session_id, reason)
            .await;
    }

    async fn fail_active_dispatch_for_closed_session(&self, session_id: &str, reason: &str) {
        let dispatch = match self
            .runtime_store
            .active_orchestration_dispatch_for_handle(session_id)
            .await
        {
            Ok(dispatch) => dispatch,
            Err(error) => {
                eprintln!(
                    "failed to inspect active orchestration dispatch for exited terminal {session_id}: {error}"
                );
                return;
            }
        };
        let Some(dispatch) = dispatch else {
            return;
        };
        if let Err(error) = self
            .runtime_store
            .fail_orchestration_dispatch(&dispatch.id, reason)
            .await
        {
            eprintln!(
                "failed to mark orchestration dispatch {} failed after terminal close: {error}",
                dispatch.id
            );
        }
    }

    pub(super) fn handle_output_batch_tick(&mut self, session_id: String, generation: u64) {
        if self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.output_batch_due(generation))
        {
            self.flush_output_batch(&session_id);
        }
    }

    pub(super) fn handle_durable_output_batch_tick(&mut self, session_id: String, generation: u64) {
        if self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.durable_output_batch_due(generation))
        {
            self.flush_durable_output_batch(&session_id);
        }
    }

    fn flush_output_batch(&mut self, session_id: &str) {
        let broadcast = self.sessions.get_mut(session_id).and_then(|session| {
            let batch = session.flush_output_batch()?;
            Some((event("output", batch.payload), session.output_clients()))
        });
        if let Some((frame, clients)) = broadcast {
            for client_id in clients {
                self.send_terminal_output(session_id, client_id, frame.clone());
            }
        }
    }

    fn send_terminal_output(&mut self, session_id: &str, client_id: u64, frame: Value) {
        let result = self
            .clients
            .get(&client_id)
            .map(|client| client.handle.out.try_send(frame));
        match result {
            Some(Ok(())) => {}
            Some(Err(TrySendError::Full(_))) => {
                let newly_backpressured = self
                    .sessions
                    .get_mut(session_id)
                    .is_some_and(|session| session.mark_output_backpressured(client_id));
                if newly_backpressured {
                    self.spawn_output_resync_timer(session_id.to_string(), client_id);
                }
            }
            Some(Err(TrySendError::Closed(_))) | None => {
                self.disconnect_client_soon(client_id);
            }
        }
    }

    pub(super) fn handle_output_resync_tick(&mut self, session_id: String, client_id: u64) {
        if !self
            .sessions
            .get(&session_id)
            .is_some_and(|session| session.output_resync_pending(client_id))
        {
            return;
        }
        let frame = event("outputResyncRequired", json!({ "sessionId": session_id }));
        let result = self
            .clients
            .get(&client_id)
            .map(|client| client.handle.out.try_send(frame));
        match result {
            Some(Ok(())) => {
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.mark_output_resync_sent(client_id);
                }
            }
            Some(Err(TrySendError::Full(_))) => {
                self.spawn_output_resync_timer(session_id, client_id);
            }
            Some(Err(TrySendError::Closed(_))) | None => {
                if let Some(session) = self.sessions.get_mut(&session_id) {
                    session.mark_output_resync_sent(client_id);
                }
                self.disconnect_client_soon(client_id);
            }
        }
    }

    fn flush_durable_output_batch(&mut self, session_id: &str) {
        let batch = self
            .sessions
            .get_mut(session_id)
            .and_then(Session::flush_durable_output_batch);
        if let Some(batch) = batch {
            self.persist_output_batch(session_id.to_string(), batch.sequence, batch.data);
        }
    }

    pub(super) fn flush_all_output(&mut self, session_id: &str) {
        self.flush_output_batch(session_id);
        self.flush_durable_output_batch(session_id);
    }

    pub(super) async fn handle_checkpoint_tick(&mut self, session_id: String, generation: u64) {
        let store = self.store.clone();
        let due = self
            .sessions
            .get_mut(&session_id)
            .is_some_and(|session| session.checkpoint_due(generation));
        if due {
            self.flush_durable_output_batch(&session_id);
            self.await_output_writes(&session_id).await;
            if let Some(session) = self.sessions.get_mut(&session_id) {
                let _ = session.write_checkpoint(&store, None).await;
            }
            let _ = store
                .trim_session(&session_id, self.config.scrollback_bytes as usize)
                .await;
        }
    }

    pub(super) async fn immediate_checkpoint(&mut self, session_id: &str) {
        let store = self.store.clone();
        self.flush_durable_output_batch(session_id);
        self.await_output_writes(session_id).await;
        if let Some(session) = self.sessions.get_mut(session_id) {
            session.invalidate_checkpoint();
            let _ = session.write_checkpoint(&store, None).await;
            let _ = store
                .trim_session(session_id, self.config.scrollback_bytes as usize)
                .await;
        }
    }

    fn persist_output_batch(&mut self, session_id: String, sequence: i64, data: Vec<u8>) {
        let store = self.store.clone();
        let task_session_id = session_id.clone();
        let handle = tokio::spawn(async move {
            let _ = store.append_output(&task_session_id, sequence, &data).await;
        });
        let pending = self.pending_output_writes.entry(session_id).or_default();
        pending.retain(|existing| !existing.is_finished());
        pending.push(handle);
    }

    pub(super) async fn await_output_writes(&mut self, session_id: &str) {
        let Some(handles) = self.pending_output_writes.remove(session_id) else {
            return;
        };
        if tokio::time::timeout(
            OUTPUT_PERSISTENCE_BARRIER_TIMEOUT,
            futures_util::future::join_all(handles),
        )
        .await
        .is_err()
        {
            eprintln!(
                "terminal output persistence barrier timed out for session {session_id}; continuing without blocking the host actor"
            );
        }
    }
}
