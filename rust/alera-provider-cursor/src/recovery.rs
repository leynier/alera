use super::CursorProvider;
use crate::mapping::map_run_message;
use alera_provider_protocol::{
    EventKind, Provider, ProviderError, ProviderEvent, ProviderRefs, RawEvent, TurnStatus,
};
use cursor_agent_sdk::RunStreamMessage;
use serde_json::Value;

impl CursorProvider {
    pub(super) fn clear_turn_state(&mut self) {
        self.stream = None;
        self.active_turn_id = None;
        self.native_run_id = None;
        self.native_item_id = None;
        self.streamed_assistant = false;
        self.last_status_error_message = None;
        self.stream_recovery_attempted = false;
        if let Some(session) = self.session.as_mut() {
            session.status = alera_provider_protocol::SessionStatus::Ready;
            session.active_turn_id = None;
        }
    }

    pub(super) fn terminal_failure(
        &mut self,
        message: String,
        raw_payload: Value,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let session = self.active_session()?;
        let mut event = ProviderEvent::new(
            self.kind(),
            &self.config.provider_instance_id,
            &session.thread_id,
            EventKind::TurnCompleted,
            serde_json::json!({
                "state": TurnStatus::Failed,
                "errorMessage": message,
            }),
            Some(RawEvent {
                source: "cursor.sdk.bridge".into(),
                method: Some("stream.recovery".into()),
                message_type: Some("stream_error".into()),
                payload: raw_payload,
            }),
        );
        event.turn_id = self.active_turn_id.clone();
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: self.native_run_id.clone(),
            provider_item_id: self.native_item_id.clone(),
            provider_request_id: None,
        });
        event.validate()?;
        self.queued_events.push_back(event);
        self.clear_turn_state();
        Ok(self.queued_events.pop_front())
    }

    pub(super) async fn recover_stream_loss(
        &mut self,
        stream_error: String,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        if let Some(stream) = self.stream.as_mut() {
            let _ = stream.close().await;
        }
        self.stream = None;
        let Some(native_run_id) = self.native_run_id.clone() else {
            return self.terminal_failure(
                format!("{stream_error}; native run id is unavailable"),
                serde_json::json!({ "streamError": stream_error }),
            );
        };

        match self.client.wait_live_run(&native_run_id).await {
            Ok(response) => {
                let message = wait_result_message(response, &native_run_id);
                let session = self.active_session()?;
                let mapped = match map_run_message(
                    &message,
                    &self.config.provider_instance_id,
                    &session.thread_id,
                    self.active_turn_id.as_deref(),
                    self.native_run_id.as_deref(),
                    self.native_item_id.as_deref(),
                    self.streamed_assistant,
                ) {
                    Ok(mapped) => mapped,
                    Err(error) => {
                        return self.terminal_failure(
                            format!("{stream_error}; waitLiveRun mapping failed: {error}"),
                            serde_json::json!({
                                "streamError": stream_error,
                                "waitLiveRunMappingError": error.to_string(),
                            }),
                        )
                    }
                };
                self.queued_events.extend(mapped);
                self.clear_turn_state();
                Ok(self.queued_events.pop_front())
            }
            Err(wait_error) if !self.stream_recovery_attempted => {
                match self.client.observe_run(&native_run_id, None).await {
                    Ok(stream) => {
                        self.stream = Some(stream);
                        self.stream_recovery_attempted = true;
                        self.next_event().await
                    }
                    Err(observe_error) => self.terminal_failure(
                        format!(
                            "{stream_error}; waitLiveRun failed: {wait_error}; ObserveRun failed: {observe_error}"
                        ),
                        serde_json::json!({
                            "streamError": stream_error,
                            "waitLiveRunError": wait_error.to_string(),
                            "observeRunError": observe_error.to_string(),
                        }),
                    ),
                }
            }
            Err(wait_error) => self.terminal_failure(
                format!("{stream_error}; waitLiveRun failed: {wait_error}"),
                serde_json::json!({
                    "streamError": stream_error,
                    "waitLiveRunError": wait_error.to_string(),
                }),
            ),
        }
    }
}

pub(super) fn wait_result_message(response: Value, native_run_id: &str) -> RunStreamMessage {
    let run_result = response.get("result").cloned().unwrap_or(response);
    let status = run_result
        .get("status")
        .cloned()
        .unwrap_or_else(|| Value::String("RUN_LIFECYCLE_STATUS_FINISHED".into()));
    let run_id = run_result
        .get("runId")
        .or_else(|| run_result.get("run_id"))
        .cloned()
        .unwrap_or_else(|| Value::String(native_run_id.to_owned()));
    RunStreamMessage {
        sdk_message: None,
        result: Some(serde_json::json!({
            "runId": run_id,
            "status": status,
            "result": run_result,
        })),
        done: None,
        interaction_update: None,
        step: None,
        offset: None,
        extra: serde_json::Map::new(),
    }
}
