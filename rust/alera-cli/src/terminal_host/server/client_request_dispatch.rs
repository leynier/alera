use super::*;

impl ServerActor {
    /// Parse and dispatch one client line, then write the response. Malformed
    /// messages without a request id drop the connection because there is no
    /// response target.
    pub(in crate::terminal_host::server) async fn handle_line(
        &mut self,
        client_id: u64,
        line: String,
    ) {
        let mut restart_after_response = false;
        let mut shutdown_after_response = false;
        let decoded: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            // jsonDecode threw: no request id is available, so drop the client.
            Err(_) => {
                self.dispose_client(client_id).await;
                return;
            }
        };
        let Some(obj) = decoded.as_object() else {
            self.dispose_client(client_id).await;
            return;
        };
        let request_id = obj.get("id").and_then(Value::as_i64);
        if let Some(id) = request_id {
            if self.pending_history_requests.contains_key(&(client_id, id)) {
                // A timer already owns this request; do not multiply retries.
                return;
            }
        }
        let outcome: HostResult<Value> = match extract_request(obj) {
            Ok((request_type, payload)) => {
                restart_after_response = request_type == "host.restart";
                shutdown_after_response = request_type == "host.shutdown";
                if let Some(id) = request_id {
                    if (self.mutation_queue.has_runtime_mutations()
                        && conflicts_with_runtime_mutation(&request_type))
                        || (self.has_blocking_managed_workspace_jobs()
                            && (conflicts_with_runtime_mutation(&request_type)
                                || super::super::runtime_mutation_barrier::is_serialized_runtime_mutation(
                                    &request_type,
                                )))
                    {
                        self.client_write(
                            client_id,
                            error_response(
                                id,
                                &HostError::state(
                                    "A runtime mutation is in progress. Wait for it to finish and retry.",
                                ),
                            ),
                        );
                        return;
                    }
                    match self
                        .try_start_deferred_request(client_id, id, &request_type, &payload)
                        .await
                    {
                        Ok(true) => return,
                        Ok(false) => {}
                        Err(error) => {
                            if self.defer_pending_history_error(
                                &error,
                                client_id,
                                id,
                                &payload,
                                line.clone(),
                            ) {
                                return;
                            }
                            self.release_payload_history_barrier(&payload);
                            if let Some(id) = request_id {
                                self.client_write(client_id, error_response(id, &error));
                            } else {
                                self.dispose_client(client_id).await;
                            }
                            return;
                        }
                    }
                    if request_type.starts_with("inbox.") {
                        let result = self
                            .handle_inbox_request(client_id, id, &request_type, &payload)
                            .await;
                        self.broadcast_inbox_change().await;
                        match result {
                            Ok(None) => {}
                            Ok(Some(value)) => self.client_write(client_id, ok_response(id, value)),
                            Err(error) => self.client_write(client_id, error_response(id, &error)),
                        }
                        return;
                    }
                    if request_type.starts_with("orchestration.") {
                        let result = self
                            .handle_orchestration_request(client_id, id, &request_type, &payload)
                            .await;
                        self.broadcast_orchestration_board_change().await;
                        self.broadcast_inbox_change().await;
                        match result {
                            // A parked waiter answers later (wake or timeout).
                            Ok(None) => return,
                            Ok(Some(value)) => {
                                self.client_write(client_id, ok_response(id, value));
                            }
                            Err(error) => {
                                if self.defer_pending_history_error(
                                    &error,
                                    client_id,
                                    id,
                                    &payload,
                                    line.clone(),
                                ) {
                                    return;
                                }
                                self.release_payload_history_barrier(&payload);
                                self.client_write(client_id, error_response(id, &error));
                            }
                        }
                        return;
                    }
                }
                self.handle_request(client_id, &request_type, &payload)
                    .await
            }
            Err(error) => Err(error),
        };
        if matches!(&outcome, Err(HostError::State(message)) if message == "Terminal history could not be persisted; the session remains open for retry.")
        {
            if let Some(id) = request_id {
                let session_id = obj
                    .get("payload")
                    .and_then(|value| value.get("sessionId"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string();
                if self.defer_history_request(client_id, id, session_id, line) {
                    return;
                }
            }
        }
        if let Some(id) = request_id {
            self.finish_history_request(client_id, id);
        }
        if let Some(payload) = obj.get("payload") {
            self.release_payload_history_barrier(payload);
        }
        match outcome {
            Ok(payload) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, ok_response(id, payload));
                    if restart_after_response {
                        self.restart_runtime_after_client_write(client_id);
                    }
                    if shutdown_after_response {
                        self.shutdown_runtime_after_client_write(client_id);
                    }
                } else if shutdown_after_response {
                    // There is no response to order against for a malformed
                    // request without an id, so preserve the legacy shutdown
                    // behavior for that case.
                    let _ = self.inbox.send(ServerCommand::RequestedShutdown);
                }
            }
            Err(error) => {
                if let Some(id) = request_id {
                    self.client_write(client_id, error_response(id, &error));
                } else {
                    self.dispose_client(client_id).await;
                }
            }
        }
    }
}
