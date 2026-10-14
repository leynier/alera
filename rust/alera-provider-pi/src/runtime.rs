use crate::{
    provider::{PendingCall, PendingUiRequest, PiProvider},
    rpc,
};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderRefs, ProviderSession, RequestId,
    SessionStatus, TurnInput, UserInputAnswers, UserInputQuestion,
};
use serde_json::{json, Map, Value};

impl<T: JsonTransport> PiProvider<T> {
    pub(crate) fn ensure_open(&self) -> Result<(), ProviderError> {
        if self.closed {
            Err(ProviderError::Closed)
        } else {
            Ok(())
        }
    }

    pub(crate) fn next_request_id(&mut self) -> RequestId {
        let id = self.next_request_id;
        self.next_request_id += 1;
        RequestId::String(format!("alera-pi-{id}"))
    }

    pub(crate) fn next_turn(&mut self) -> String {
        self.next_turn_id += 1;
        format!("turn:pi:{}", self.next_turn_id)
    }

    pub(crate) fn queue_message(&mut self, message: Value) -> Result<(), ProviderError> {
        if self.queued_messages.len() >= self.config.max_queued_events {
            return Err(ProviderError::Protocol(
                "Pi provider event queue is full".into(),
            ));
        }
        self.queued_messages.push_back(message);
        Ok(())
    }

    pub(crate) async fn call(
        &mut self,
        command: &str,
        params: Value,
    ) -> Result<Value, ProviderError> {
        let id = self.next_request_id();
        self.pending_calls.insert(
            id.clone(),
            PendingCall {
                command: command.into(),
            },
        );
        self.pending_order.push_back(id.clone());
        self.transport
            .send(rpc::request(&id, command, params))
            .await
            .map_err(|error| {
                self.remove_pending_call(&id);
                ProviderError::from(error)
            })?;
        loop {
            let received = match tokio::time::timeout(
                self.config.request_timeout,
                self.transport.recv(),
            )
            .await
            {
                Ok(Ok(received)) => received,
                Ok(Err(error)) => {
                    self.remove_pending_call(&id);
                    return Err(error.into());
                }
                Err(_) => {
                    self.remove_pending_call(&id);
                    return Err(ProviderError::Timeout {
                        operation: format!("Pi {command}"),
                    });
                }
            };
            let Some(message) = received else {
                self.remove_pending_call(&id);
                return Err(ProviderError::Closed);
            };
            if !rpc::is_response(&message) {
                if let Err(error) = self.queue_message(message) {
                    self.remove_pending_call(&id);
                    return Err(error);
                }
                continue;
            }
            let response_id = message.get("id").map(rpc::request_id).transpose()?;
            if response_id.as_ref() == Some(&id) {
                self.remove_pending_call(&id);
                return rpc::response_success(&message);
            }
            let was_pending = self.pending_calls.contains_key(&id);
            self.consume_response(&message)?;
            if response_id.is_none() && was_pending && !self.pending_calls.contains_key(&id) {
                return rpc::response_success(&message);
            }
        }
    }

    pub(crate) fn consume_response(&mut self, message: &Value) -> Result<(), ProviderError> {
        if message.get("command").and_then(Value::as_str) == Some("prompt")
            && message.get("success").and_then(Value::as_bool) == Some(false)
        {
            self.prompt_failure = Some(message.clone());
            return Ok(());
        }
        let Some(raw_id) = message.get("id") else {
            let Some(command) = message.get("command").and_then(Value::as_str) else {
                return Ok(());
            };
            let matching_id = self
                .pending_order
                .iter()
                .find(|id| {
                    self.pending_calls
                        .get(*id)
                        .is_some_and(|call| call.command == command)
                })
                .cloned();
            let Some(id) = matching_id else {
                return Ok(());
            };
            let Some(call) = self.remove_pending_call(&id) else {
                return Ok(());
            };
            validate_response_for_call(message, &call)?;
            return Ok(());
        };
        let id = rpc::request_id(raw_id)?;
        if let Some(call) = self.remove_pending_call(&id) {
            validate_response_for_call(message, &call)?;
        }
        Ok(())
    }

    pub(crate) fn remove_pending_call(&mut self, id: &RequestId) -> Option<PendingCall> {
        let call = self.pending_calls.remove(id);
        if call.is_some() {
            if let Some(index) = self.pending_order.iter().position(|pending| pending == id) {
                self.pending_order.remove(index);
            }
        }
        call
    }

    pub(crate) fn event(
        &self,
        kind: EventKind,
        payload: Value,
        request_id: &RequestId,
        method: &str,
        raw: Value,
    ) -> ProviderEvent {
        let thread_id = self
            .session
            .as_ref()
            .map(|session| session.thread_id.clone())
            .unwrap_or_else(|| "pi-pending-thread".into());
        let turn_id = self
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone());
        let mut event = ProviderEvent::new(
            self.kind(),
            self.config.instance_id.clone(),
            thread_id,
            kind,
            payload,
            Some(alera_provider_protocol::RawEvent {
                source: "pi.rpc".into(),
                method: Some(method.into()),
                message_type: Some(method.into()),
                payload: raw,
            }),
        );
        event.turn_id = turn_id.clone();
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: Some(request_id.to_string()),
        });
        event
    }

    pub(crate) fn queue_lifecycle_events(&mut self, session: &ProviderSession, command: &str) {
        let mut started = ProviderEvent::new(
            self.kind(),
            self.config.instance_id.clone(),
            session.thread_id.clone(),
            EventKind::SessionStarted,
            json!({ "message": "Pi session started" }),
            Some(alera_provider_protocol::RawEvent {
                source: "pi.rpc".into(),
                method: Some(command.into()),
                message_type: Some("session".into()),
                payload: self.native_state.clone(),
            }),
        );
        started.provider_refs = Some(ProviderRefs::default());
        let mut thread = ProviderEvent::new(
            self.kind(),
            self.config.instance_id.clone(),
            session.thread_id.clone(),
            EventKind::ThreadStarted,
            json!({ "providerThreadId": session.native_thread_id }),
            Some(alera_provider_protocol::RawEvent {
                source: "pi.rpc".into(),
                method: Some("get_state".into()),
                message_type: Some("thread".into()),
                payload: self.native_state.clone(),
            }),
        );
        thread.provider_refs = Some(ProviderRefs::default());
        self.queued_events.extend([started, thread]);
    }

    pub(crate) async fn set_model(&mut self, model: &str) -> Result<(), ProviderError> {
        let (provider, model_id) = model.split_once('/').ok_or_else(|| {
            ProviderError::Validation("Pi model must use provider/model format".into())
        })?;
        if provider.trim().is_empty() || model_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "Pi model must use provider/model format".into(),
            ));
        }
        self.call(
            "set_model",
            json!({ "provider": provider, "modelId": model_id }),
        )
        .await?;
        Ok(())
    }

    pub(crate) fn mark_terminal(&mut self, _interrupted: bool) {
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Ready;
            session.active_turn_id = None;
        }
        self.interrupt_requested = false;
        self.assistant_failure = None;
    }

    pub(crate) async fn expire_ui_requests(
        &mut self,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let now = std::time::Instant::now();
        let expired = self
            .pending_ui
            .iter()
            .filter_map(|(id, pending)| {
                pending
                    .expires_at
                    .filter(|deadline| *deadline <= now)
                    .map(|_| id.clone())
            })
            .collect::<Vec<_>>();
        let mut first = None;
        for id in expired {
            let event = self
                .complete_ui_request(&id, json!({ "cancelled": true }))
                .await?;
            if first.is_none() {
                first = Some(event);
            } else {
                self.queued_events.push_back(event);
            }
        }
        Ok(first)
    }

    pub(crate) async fn complete_ui_request(
        &mut self,
        id: &RequestId,
        payload: Value,
    ) -> Result<ProviderEvent, ProviderError> {
        let pending =
            self.pending_ui.get(id).cloned().ok_or_else(|| {
                ProviderError::InvalidState("unknown Pi runtime request id".into())
            })?;
        let Value::Object(response_fields) = payload.clone() else {
            return Err(ProviderError::Protocol(
                "Pi extension UI response must be an object".into(),
            ));
        };
        let mut fields = vec![("id".into(), rpc::request_id_value(&pending.native_id))];
        fields.extend(response_fields);
        let mut raw_response = Map::new();
        raw_response.insert("type".into(), Value::String("extension_ui_response".into()));
        raw_response.insert("id".into(), rpc::request_id_value(&pending.native_id));
        if let Value::Object(fields) = payload.clone() {
            raw_response.extend(fields);
        }
        self.transport
            .send(rpc::fire_and_forget("extension_ui_response", fields))
            .await?;
        self.pending_ui.remove(id);
        if let Some(session) = self.session.as_mut() {
            if session.active_turn_id.is_some() {
                session.status = SessionStatus::Running;
            }
        }
        let mut resolved = self.event(
            EventKind::RequestResolved,
            json!({
                "requestType": pending.request.kind,
                "decision": payload,
            }),
            &pending.native_id,
            "extension_ui_response",
            Value::Object(raw_response),
        );
        resolved.request_id = Some(id.to_string());
        resolved.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: Some(id.to_string()),
        });
        resolved.validate()?;
        Ok(resolved)
    }

    pub(crate) fn pending_ui_insert(
        &mut self,
        id: RequestId,
        pending: PendingUiRequest,
    ) -> Result<(), ProviderError> {
        if self.pending_ui.contains_key(&id) {
            return Err(ProviderError::InvalidState(
                "Pi extension request id is already pending".into(),
            ));
        }
        self.pending_ui.insert(id, pending);
        if let Some(session) = self.session.as_mut() {
            if session.active_turn_id.is_some() {
                session.status = SessionStatus::Waiting;
            }
        }
        Ok(())
    }

    pub(crate) fn active_turn_id(&self) -> Option<String> {
        self.session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone())
    }
}

pub(crate) fn native_thread_id(state: &Value) -> Option<String> {
    state
        .get("sessionFile")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn state_is_idle(state: &Value) -> bool {
    state.get("isStreaming").and_then(Value::as_bool) != Some(true)
        && state.get("isCompacting").and_then(Value::as_bool) != Some(true)
        && state
            .get("pendingMessageCount")
            .and_then(Value::as_u64)
            .unwrap_or(0)
            == 0
}

pub(crate) fn state_model(state: &Value) -> Option<String> {
    let model = state.get("model")?;
    let provider = model
        .get("provider")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())?;
    let id = model
        .get("id")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())?;
    Some(format!("{provider}/{id}"))
}

pub(crate) fn user_input_payload(
    answers: &UserInputAnswers,
    questions: &[UserInputQuestion],
) -> Result<Value, ProviderError> {
    let answer = questions
        .first()
        .and_then(|question| answers.get(&question.id));
    match answer {
        Some(Value::String(value)) => Ok(json!({ "value": value })),
        Some(_) => Err(ProviderError::Validation(
            "Pi user-input answers must be strings".into(),
        )),
        None => Ok(json!({ "cancelled": true })),
    }
}

fn validate_response_for_call(message: &Value, call: &PendingCall) -> Result<(), ProviderError> {
    let Some(success) = message.get("success").and_then(Value::as_bool) else {
        return Err(ProviderError::Protocol(
            "Pi RPC response has no boolean success field".into(),
        ));
    };
    if !success && call.command != "prompt" {
        return Err(ProviderError::Protocol(
            message
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("Pi RPC command failed")
                .into(),
        ));
    }
    Ok(())
}

pub(crate) fn image_inputs(input: &TurnInput) -> Result<Vec<Value>, ProviderError> {
    let mut images = Vec::new();
    for attachment in &input.attachments {
        match attachment {
            alera_provider_protocol::Attachment::Image { url } if url.starts_with("data:") => {
                let (header, data) = url.split_once(',').ok_or_else(|| {
                    ProviderError::Validation("Pi data image attachment is malformed".into())
                })?;
                let mime = header
                    .strip_prefix("data:")
                    .and_then(|value| value.strip_suffix(";base64"))
                    .ok_or_else(|| {
                        ProviderError::Unsupported(
                            "Pi image attachments must be base64 data URLs".into(),
                        )
                    })?;
                images.push(json!({ "type": "image", "data": data, "mimeType": mime }));
            }
            alera_provider_protocol::Attachment::Image { .. } => {
                return Err(ProviderError::Unsupported(
                    "Pi cannot fetch remote image URLs through the RPC adapter".into(),
                ));
            }
            alera_provider_protocol::Attachment::LocalImage { .. }
            | alera_provider_protocol::Attachment::File { .. } => {
                return Err(ProviderError::Unsupported(
                    "Pi file attachments require host-side materialization".into(),
                ));
            }
        }
    }
    Ok(images)
}
