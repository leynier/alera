//! How a turn's text reaches OpenCode, as T3 Code's adapters send it: a bare
//! `/compact` compacts the session, a text that opens with a command the
//! server lists runs it through the command route, and everything else is a
//! prompt. A 1.x command or compaction answers only when it is done, so it
//! runs beside the event stream instead of holding the turn start.

use crate::background::BackgroundCall;
use crate::commands::command_of;
use crate::config::OpenCodeGeneration;
use crate::provider::{timed, ActiveTurn, OpenCodeProvider};
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderSession, SessionStatus, TurnInput,
    TurnStartResult,
};
use opencode_agent_sdk::{CommandRequest, HttpTransport, OpenCodeClient};
use serde_json::{json, Value};
use std::time::Duration;

/// How long a 2.x turn waits for the command list before sending a prompt.
const V2_INVENTORY_TIMEOUT: Duration = Duration::from_secs(5);
/// How long a 1.x turn waits for the command list before sending a prompt.
const LEGACY_INVENTORY_TIMEOUT: Duration = Duration::from_secs(10);

enum Dispatch {
    Prompt {
        parts: Vec<Value>,
        skills: Vec<String>,
    },
    Command {
        name: String,
        arguments: String,
        files: Vec<Value>,
    },
    Compact,
}

impl<T: HttpTransport + Clone + 'static> OpenCodeProvider<T> {
    async fn dispatch_for(&mut self, input: &TurnInput) -> Result<Dispatch, ProviderError> {
        let bare = input.attachments.is_empty();
        if bare && input.input.trim() == "/compact" {
            return Ok(Dispatch::Compact);
        }
        let parts = crate::config::prompt_parts(input)?;
        let generation = self.config.generation;
        // 2.x runs commands only for text alone; 1.x sends files along.
        let candidate = match generation {
            OpenCodeGeneration::V2 if !bare => None,
            _ => command_of(&input.input),
        };
        if let Some((name, arguments)) = candidate {
            let timeout = match generation {
                OpenCodeGeneration::V2 => V2_INVENTORY_TIMEOUT,
                OpenCodeGeneration::Legacy1 => LEGACY_INVENTORY_TIMEOUT,
            };
            if self.knows_command(&name, timeout).await {
                let files = parts
                    .into_iter()
                    .filter(|part| part.get("type").and_then(Value::as_str) == Some("file"))
                    .collect();
                return Ok(Dispatch::Command {
                    name,
                    arguments,
                    files,
                });
            }
        }
        let skills = self.mentioned_skills(&input.input).await;
        Ok(Dispatch::Prompt { parts, skills })
    }

    pub(crate) async fn start_turn(
        &mut self,
        input: TurnInput,
        session: ProviderSession,
    ) -> Result<TurnStartResult, ProviderError> {
        let dispatch = self.dispatch_for(&input).await?;
        let model = input.model.clone().or_else(|| session.model.clone());
        let legacy = self.config.generation == OpenCodeGeneration::Legacy1;
        if legacy && matches!(dispatch, Dispatch::Compact) && !is_model_slug(model.as_deref()) {
            return Err(ProviderError::Validation(
                "OpenCode compaction needs a provider/model model".into(),
            ));
        }
        let turn_id = self.next_turn_id();
        let mut started = ProviderEvent::new(
            Self::provider_kind(),
            self.config.provider_instance_id.clone(),
            session.thread_id.clone(),
            EventKind::TurnStarted,
            model
                .as_ref()
                .map(|model| json!({ "model": model }))
                .unwrap_or_else(|| json!({})),
            None,
        );
        let requested_message_id = crate::native_message_id::native_message_id(&started);
        // A 2.x command and a 1.x compaction take no message id.
        let sends_id = match dispatch {
            Dispatch::Prompt { .. } => true,
            Dispatch::Command { .. } => legacy,
            Dispatch::Compact => !legacy,
        };
        let requested = sends_id.then_some(requested_message_id);
        self.active_turn = Some(ActiveTurn {
            id: turn_id.clone(),
            native_message_id: requested.clone(),
            interrupted: false,
        });
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Running;
            session.active_turn_id = Some(turn_id.clone());
        }
        let native = &session.native_thread_id;
        let timeout = self.config.request_timeout;
        let sent = match dispatch {
            Dispatch::Prompt { parts, skills } => {
                let prompt = self.client.prompt_parts_with_skills(
                    native,
                    parts,
                    model.as_deref(),
                    requested.as_deref(),
                    &skills,
                );
                timed(timeout, "session.prompt", prompt).await.map(Some)
            }
            Dispatch::Command {
                name,
                arguments,
                files,
            } => {
                let request = CommandRequest {
                    name,
                    arguments,
                    message_id: requested.clone().filter(|_| legacy),
                    model: model.clone().filter(|_| legacy),
                    files: if legacy { files } else { Vec::new() },
                };
                if legacy {
                    self.run_in_background(&turn_id, native, requested.clone(), request);
                    Ok(None)
                } else {
                    let command = self.client.run_command(native, request);
                    timed(timeout, "session.command", command).await.map(Some)
                }
            }
            Dispatch::Compact if legacy => {
                self.compact_in_background(&turn_id, native, model.clone());
                Ok(None)
            }
            Dispatch::Compact => {
                let compact = self
                    .client
                    .compact_session(native, requested.as_deref(), None);
                timed(timeout, "session.compact", compact).await.map(Some)
            }
        };
        let response = match sent {
            Ok(response) => response,
            Err(error) => {
                self.active_turn = None;
                if let Some(session) = self.session.as_mut() {
                    session.status = SessionStatus::Ready;
                    session.active_turn_id = None;
                }
                return Err(error);
            }
        };
        let native_message_id = response
            .as_ref()
            .and_then(|response| response.get("id").or_else(|| response.get("messageID")))
            .and_then(Value::as_str)
            .map(str::to_owned)
            .or(requested);
        self.native_parts.start_turn(native_message_id.clone());
        if let Some(active) = self.active_turn.as_mut() {
            active.native_message_id = native_message_id.clone();
        }
        started.turn_id = Some(turn_id.clone());
        started.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: native_message_id.clone(),
            provider_item_id: native_message_id.clone(),
            provider_request_id: None,
        });
        started.validate()?;
        self.queued_events.push_back(started);
        Ok(TurnStartResult {
            thread_id: session.thread_id,
            turn_id,
            native_turn_id: native_message_id,
        })
    }

    fn detached_client(&self) -> OpenCodeClient<T> {
        OpenCodeClient::new(
            self.client.transport().clone(),
            self.client.config().clone(),
        )
    }

    fn run_in_background(
        &mut self,
        turn_id: &str,
        session_id: &str,
        message_id: Option<String>,
        request: CommandRequest,
    ) {
        let mut client = self.detached_client();
        let session_id = session_id.to_owned();
        let handle = tokio::spawn(async move { client.run_command(&session_id, request).await });
        self.background = Some(BackgroundCall::command(turn_id, handle, message_id));
    }

    fn compact_in_background(&mut self, turn_id: &str, session_id: &str, model: Option<String>) {
        let mut client = self.detached_client();
        let session_id = session_id.to_owned();
        let handle = tokio::spawn(async move {
            client
                .compact_session(&session_id, None, model.as_deref())
                .await
        });
        self.background = Some(BackgroundCall::compaction(turn_id, handle));
    }
}

fn is_model_slug(model: Option<&str>) -> bool {
    model
        .and_then(|model| model.split_once('/'))
        .is_some_and(|(provider, model)| !provider.is_empty() && !model.is_empty())
}
