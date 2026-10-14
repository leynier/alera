use crate::{
    config::AcpFlavor,
    runtime_response::{
        acp_error, grok_permission_response, permission_response, user_input_response,
        xai_user_input_response,
    },
    transport::raw,
    AcpProvider,
};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderRefs, RequestKind, RuntimeResponse,
};
use serde_json::json;

impl<T: JsonTransport> AcpProvider<T> {
    pub(crate) async fn respond_native(
        &mut self,
        response: RuntimeResponse,
    ) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let key = response.request_id().to_string();
        let pending =
            self.pending_requests.get(&key).cloned().ok_or_else(|| {
                ProviderError::InvalidState("unknown ACP runtime request id".into())
            })?;
        let wire = match response {
            RuntimeResponse::Approval { decision, .. } => {
                if pending.method != "session/request_permission" {
                    return Err(ProviderError::Validation(
                        "approval response does not match ACP request".into(),
                    ));
                }
                if self.config.flavor == AcpFlavor::Grok {
                    grok_permission_response(&pending.params, decision)?
                } else {
                    permission_response(&pending.params, decision)?
                }
            }
            RuntimeResponse::Elicitation {
                action, content, ..
            } => {
                if pending.method != "elicitation/create"
                    && pending.method != "session/elicitation"
                    && pending.method != "_session/elicitation"
                {
                    return Err(ProviderError::Validation(
                        "elicitation response does not match ACP request".into(),
                    ));
                }
                let action = match action {
                    alera_provider_protocol::ElicitationAction::Accept => "accept",
                    alera_provider_protocol::ElicitationAction::Decline => "decline",
                    alera_provider_protocol::ElicitationAction::Cancel => "cancel",
                };
                json!({"action":action,"content":content})
            }
            RuntimeResponse::UserInput { answers, .. } => {
                if pending.kind != RequestKind::ToolUserInput {
                    return Err(ProviderError::Validation(
                        "user-input response does not match ACP request".into(),
                    ));
                }
                if self.config.flavor == AcpFlavor::Grok && pending.method.contains("ask_user") {
                    xai_user_input_response(&pending.params, answers)?
                } else {
                    user_input_response(answers)
                }
            }
            RuntimeResponse::Native { result, .. } => {
                if pending.kind != RequestKind::DynamicToolCall {
                    return Err(ProviderError::Validation(
                        "native response does not match ACP request".into(),
                    ));
                }
                result
            }
        };
        self.client
            .respond(&pending.rpc_id, Ok(wire))
            .await
            .map_err(acp_error)?;
        self.pending_requests.remove(&key);
        let session = self.session.clone().ok_or_else(|| {
            ProviderError::InvalidState("ACP runtime request has no active session".into())
        })?;
        let mut event = ProviderEvent::new(
            self.kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id,
            EventKind::RequestResolved,
            json!({"requestType":pending.kind,"decision":"resolved"}),
            Some(raw(&pending.method, pending.raw)),
        );
        event.request_id = Some(pending.logical_id);
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: session.active_turn_id,
            provider_item_id: None,
            provider_request_id: Some(pending.rpc_id.to_string()),
        });
        event.validate()?;
        self.queue_event(event)
    }
}
