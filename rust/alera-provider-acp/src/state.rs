use crate::mapping::MappedIncoming;
use crate::prompt_lifecycle::TurnFrame;
use crate::transport::{raw, PendingRequest};
use crate::AcpProvider;
use agent_client_protocol::AcpProtocolGeneration;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderRefs, SessionStatus,
};

impl<T: JsonTransport> AcpProvider<T> {
    pub(crate) fn protocol_generation(&self) -> AcpProtocolGeneration {
        self.client
            .initialized()
            .map_or(AcpProtocolGeneration::V1, |initialized| {
                initialized.generation
            })
    }

    pub(crate) fn ensure_open(&self) -> Result<(), ProviderError> {
        if self.closed {
            Err(ProviderError::Closed)
        } else {
            Ok(())
        }
    }

    pub(crate) fn queue_event(&mut self, event: ProviderEvent) -> Result<(), ProviderError> {
        if self.queued_events.len() >= self.config.max_queued_events.max(1) {
            return Err(ProviderError::InvalidState(
                "ACP provider event queue is full".into(),
            ));
        }
        event.validate()?;
        self.queued_events.push_back(event);
        Ok(())
    }

    pub(crate) fn apply_mapped_state(&mut self, mapped: &MappedIncoming, frame: TurnFrame) {
        let awaits_idle = self.protocol_generation() == AcpProtocolGeneration::V2;
        self.prompt_lifecycle
            .observe(frame, &mapped.event, awaits_idle);
        if mapped.event.kind == EventKind::TurnCompleted {
            if let Some(session) = self.session.as_mut() {
                session.active_turn_id = None;
                session.status = SessionStatus::Ready;
            }
            self.prompt_id = None;
            self.prompt_meta_id = None;
        }
    }

    /// Whether the session can take `mode`: a config option with that id or
    /// category, or ACP v1's `setMode` capability. Models go through
    /// [`AcpProvider::model_inventory`].
    pub(crate) fn supports_config_option(&self, id: &str) -> bool {
        if self.session_config_options.iter().any(|option| {
            option.get("id").and_then(|value| value.as_str()) == Some(id)
                || option.get("category").and_then(|value| value.as_str()) == Some(id)
        }) {
            return true;
        }
        let Some(initialized) = self.client.initialized() else {
            return false;
        };
        id == "mode"
            && initialized.generation == AcpProtocolGeneration::V1
            && (initialized
                .capabilities
                .supports(&["sessionCapabilities", "setMode"])
                || initialized.capabilities.supports(&["setMode"]))
    }

    pub(crate) fn queue_request_resolved(
        &mut self,
        pending: &PendingRequest,
    ) -> Result<(), ProviderError> {
        let session = self.session.as_ref().ok_or_else(|| {
            ProviderError::InvalidState("ACP request has no active session".into())
        })?;
        let mut event = ProviderEvent::new(
            self.kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::RequestResolved,
            serde_json::json!({"requestType":pending.kind,"decision":"cancelled"}),
            Some(raw(&pending.method, pending.raw.clone())),
        );
        event.request_id = Some(pending.logical_id.clone());
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: session.active_turn_id.clone(),
            provider_item_id: None,
            provider_request_id: Some(pending.rpc_id.to_string()),
        });
        self.queue_event(event)
    }
}
