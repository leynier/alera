//! A 1.x command or compaction request that runs while the event stream is
//! read. T3 Code ends a compaction turn when its request answers, fails a
//! turn whose request fails, and fails a command the server has not admitted
//! within ten seconds.

use crate::provider::{opencode_kind, OpenCodeProvider};
use alera_provider_protocol::{EventKind, ProviderError, ProviderEvent, SessionStatus, TurnStatus};
use opencode_agent_sdk::{HttpTransport, OpenCodeError, OpenCodeEvent};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::task::{JoinError, JoinHandle};
use tokio::time::Instant;

const ADMISSION_TIMEOUT: Duration = Duration::from_secs(10);

type CallResult = Result<Value, OpenCodeError>;

pub(crate) struct BackgroundCall {
    turn_id: String,
    handle: JoinHandle<CallResult>,
    completes_turn: bool,
    /// The user message a command creates, until the stream reports it.
    admission: Option<(String, Instant)>,
}

impl BackgroundCall {
    pub(crate) fn command(
        turn_id: &str,
        handle: JoinHandle<CallResult>,
        message_id: Option<String>,
    ) -> Self {
        Self {
            turn_id: turn_id.to_owned(),
            handle,
            completes_turn: false,
            admission: message_id.map(|id| (id, Instant::now() + ADMISSION_TIMEOUT)),
        }
    }

    pub(crate) fn compaction(turn_id: &str, handle: JoinHandle<CallResult>) -> Self {
        Self {
            turn_id: turn_id.to_owned(),
            handle,
            completes_turn: true,
            admission: None,
        }
    }

    /// Cancels the request, which makes OpenCode stop the command.
    pub(crate) fn abort(self) {
        self.handle.abort();
    }

    fn admits(&self, event: &OpenCodeEvent) -> bool {
        let Some((message_id, _)) = &self.admission else {
            return false;
        };
        let info = event
            .payload
            .get("properties")
            .and_then(|properties| properties.get("info"));
        event.event_type == "message.updated"
            && info
                .and_then(|info| info.get("role"))
                .and_then(Value::as_str)
                == Some("user")
            && info.and_then(|info| info.get("id")).and_then(Value::as_str)
                == Some(message_id.as_str())
    }
}

enum Next {
    Finished(Result<CallResult, JoinError>),
    AdmissionExpired,
    Event(Result<Option<OpenCodeEvent>, OpenCodeError>),
}

impl<T: HttpTransport> OpenCodeProvider<T> {
    /// The next event, from the queue, a finished background request, or
    /// the stream.
    pub(crate) async fn next_event_or_call(
        &mut self,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        loop {
            if let Some(event) = self.queued_events.pop_front() {
                return Ok(Some(event));
            }
            let next = match self.background.as_mut() {
                None => Next::Event(self.client.next_event().await),
                Some(call) => {
                    let deadline = call.admission.as_ref().map(|(_, deadline)| *deadline);
                    tokio::select! {
                        biased;
                        finished = &mut call.handle => Next::Finished(finished),
                        _ = tokio::time::sleep_until(deadline.unwrap_or_else(Instant::now)),
                            if deadline.is_some() => Next::AdmissionExpired,
                        event = self.client.next_event() => Next::Event(event),
                    }
                }
            };
            match next {
                Next::Finished(finished) => {
                    let Some(call) = self.background.take() else {
                        continue;
                    };
                    if let Some(event) = self.finish_call(call, finished) {
                        return Ok(Some(event));
                    }
                }
                Next::AdmissionExpired => {
                    let Some(call) = self.background.take() else {
                        continue;
                    };
                    let turn_id = call.turn_id.clone();
                    call.abort();
                    let message = "OpenCode command admission did not complete within 10 seconds.";
                    if let Some(event) = self.end_turn(&turn_id, TurnStatus::Failed, Some(message))
                    {
                        return Ok(Some(event));
                    }
                }
                Next::Event(event) => {
                    let event = event.map_err(crate::config::map_open_code_error)?;
                    let Some(event) = event else {
                        return Ok(None);
                    };
                    if let Some(call) = self.background.as_mut() {
                        if call.admits(&event) {
                            call.admission = None;
                        }
                    }
                    if let Some(event) = self.native_event(event).await? {
                        return Ok(Some(event));
                    }
                }
            }
        }
    }

    /// A stream event as the session sees it; `command.updated` refreshes
    /// the command list instead.
    async fn native_event(
        &mut self,
        event: OpenCodeEvent,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        if event.event_type == "command.updated" {
            return Ok(self.commands_event().await);
        }
        self.event_from_sdk(event).map(Some)
    }

    fn finish_call(
        &mut self,
        call: BackgroundCall,
        finished: Result<CallResult, JoinError>,
    ) -> Option<ProviderEvent> {
        let interrupted = self
            .active_turn
            .as_ref()
            .filter(|turn| turn.id == call.turn_id)?
            .interrupted;
        match finished {
            Ok(Ok(_)) if call.completes_turn => {
                let state = if interrupted {
                    TurnStatus::Interrupted
                } else {
                    TurnStatus::Completed
                };
                self.end_turn(&call.turn_id, state, None)
            }
            Ok(Ok(_)) => None,
            // The transport bounds a request in time, while OpenCode answers
            // these only when they are done; the stream reports the outcome.
            Ok(Err(OpenCodeError::Timeout { .. })) => None,
            _ if interrupted => None,
            Ok(Err(error)) => {
                let message = error.to_string();
                self.end_turn(&call.turn_id, TurnStatus::Failed, Some(&message))
            }
            Err(error) if error.is_cancelled() => None,
            Err(error) => {
                let message = format!("OpenCode request task failed: {error}");
                self.end_turn(&call.turn_id, TurnStatus::Failed, Some(&message))
            }
        }
    }

    fn end_turn(
        &mut self,
        turn_id: &str,
        state: TurnStatus,
        error: Option<&str>,
    ) -> Option<ProviderEvent> {
        let active = self.active_turn.take_if(|turn| turn.id == turn_id)?;
        self.native_parts.clear();
        let session = self.session.as_mut()?;
        session.status = if state == TurnStatus::Failed {
            SessionStatus::Error
        } else {
            SessionStatus::Ready
        };
        session.active_turn_id = None;
        let mut payload = json!({ "state": state });
        if let Some(error) = error {
            payload["errorMessage"] = Value::String(error.to_owned());
        }
        let mut event = ProviderEvent::new(
            opencode_kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::TurnCompleted,
            payload,
            None,
        );
        event.turn_id = Some(active.id);
        event.provider_refs = Some(crate::request_events::refs(
            active.native_message_id,
            None,
            None,
        ));
        Some(event)
    }
}
