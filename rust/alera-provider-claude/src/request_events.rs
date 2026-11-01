//! Runtime requests the SDK callbacks raise: the event that opens one for
//! the runtime, and the runtime's answer that resolves it.

use super::runtime_response::{resolved_payload, response_matches_request};
use super::*;
use alera_provider_protocol::ProviderRefs;

impl ClaudeProvider {
    /// Hands [response] to the callback waiting on its request and queues
    /// the event that resolves the request.
    pub(super) async fn respond_runtime(
        &mut self,
        response: RuntimeResponse,
    ) -> Result<(), ProviderError> {
        let request_id = response.request_id().to_string();
        let (pending, request) = {
            let mut pending_map = self.pending.lock().await;
            let pending = pending_map.get(&request_id).ok_or_else(|| {
                ProviderError::Validation(format!("unknown runtime request {request_id}"))
            })?;
            let request = match pending {
                PendingResponse::Permission { request, .. }
                | PendingResponse::Mcp { request, .. } => request.clone(),
            };
            if !response_matches_request(&request, &response) {
                return Err(ProviderError::Validation(format!(
                    "runtime response does not match request type {:?}",
                    request.kind
                )));
            }
            if let RuntimeResponse::Elicitation {
                content: Some(content),
                ..
            } = &response
            {
                if !content.is_null() && !content.is_object() {
                    return Err(ProviderError::Validation(
                        "MCP elicitation content must be null or an object".into(),
                    ));
                }
            }
            let pending = pending_map.remove(&request_id).ok_or_else(|| {
                ProviderError::Validation(format!("unknown runtime request {request_id}"))
            })?;
            (pending, request)
        };
        let response_for_event = response.clone();
        let native_request_id = match &pending {
            PendingResponse::Permission {
                native_request_id, ..
            }
            | PendingResponse::Mcp {
                native_request_id, ..
            } => native_request_id.clone(),
        };
        let sent = match pending {
            PendingResponse::Permission { sender, .. } | PendingResponse::Mcp { sender, .. } => {
                sender.send(response).is_ok()
            }
        };
        if !sent {
            self.queue_withdrawn(&request, native_request_id);
            return Err(ProviderError::InvalidState(
                "runtime request callback is no longer waiting".into(),
            ));
        }
        let (kind, payload) = resolved_payload(&request, &response_for_event);
        let source = if request.kind == RequestKind::DynamicToolCall {
            MCP_SOURCE
        } else {
            PERMISSION_SOURCE
        };
        let mut event = self.event(
            kind,
            payload.clone(),
            self.raw_from(source, "control_response", payload),
        );
        event.request_id = Some(request.request_id.to_string());
        event.turn_id = request.turn_id.clone();
        event.item_id = request.item_id.clone();
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: native_request_id,
        });
        event.validate()?;
        self.queue(event);
        Ok(())
    }

    /// Withdraws the requests whose callback stopped waiting, because the CLI
    /// cancelled them or the client closed, so their cards close.
    pub(super) async fn queue_withdrawn_requests(&mut self) {
        let withdrawn = {
            let mut pending = self.pending.lock().await;
            let closed = pending
                .iter()
                .filter(|(_, response)| response.is_closed())
                .map(|(id, _)| id.clone())
                .collect::<Vec<_>>();
            closed
                .into_iter()
                .filter_map(|id| pending.remove(&id))
                .collect::<Vec<_>>()
        };
        for response in withdrawn {
            let (PendingResponse::Permission {
                request,
                native_request_id,
                ..
            }
            | PendingResponse::Mcp {
                request,
                native_request_id,
                ..
            }) = response;
            self.queue_withdrawn(&request, native_request_id);
        }
    }

    fn queue_withdrawn(&mut self, request: &RuntimeRequest, native_request_id: Option<String>) {
        let payload = json!({
            "requestType": request.kind,
            "decision": "cancel",
            "withdrawn": true,
        });
        let mut event = self.event(
            EventKind::RequestResolved,
            payload.clone(),
            self.raw_from(PERMISSION_SOURCE, "control_cancel_request", payload),
        );
        event.request_id = Some(request.request_id.to_string());
        event.turn_id = request.turn_id.clone();
        event.item_id = request.item_id.clone();
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: native_request_id,
        });
        self.queue(event);
    }

    /// The event that opens [notice]'s request, or `None` once its callback
    /// stopped waiting.
    pub(super) async fn request_opened_event(
        &mut self,
        notice: RequestNotice,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let request_id = notice.request.request_id.to_string();
        let live = self
            .pending
            .lock()
            .await
            .get(&request_id)
            .is_some_and(|response| !response.is_closed());
        if !live {
            return Ok(None);
        }
        let request = notice.request;
        let (kind, payload) = if request.kind == RequestKind::ToolUserInput {
            (
                EventKind::UserInputRequested,
                json!({
                    "questions": request.questions,
                    "responseMode": "message",
                }),
            )
        } else {
            (EventKind::RequestOpened, request.payload.clone())
        };
        let mut event = self
            .event(
                kind,
                payload,
                self.raw_from(notice.source, "control_request", notice.raw),
            )
            .with_request(request);
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: notice.native_request_id,
        });
        event.validate()?;
        Ok(Some(event))
    }
}
