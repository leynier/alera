use crate::events;
use crate::provider::CodexProvider;
use crate::wire;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    Attachment, ProviderError, ProviderSession, SessionStartInput, TurnInput,
};
use serde_json::{json, Map, Value};

impl<T: JsonTransport> CodexProvider<T> {
    pub(crate) async fn call(
        &mut self,
        method: &str,
        params: Value,
    ) -> Result<Value, ProviderError> {
        let id = self.send_request(method, params).await?;
        self.await_response(id, method, self.config.request_timeout)
            .await
    }

    pub(crate) async fn send_request(
        &mut self,
        method: &str,
        params: Value,
    ) -> Result<i64, ProviderError> {
        self.ensure_open()?;
        let id = self.next_request_id;
        self.next_request_id = self
            .next_request_id
            .checked_add(1)
            .ok_or_else(|| ProviderError::InvalidState("Codex request id exhausted".into()))?;
        self.transport
            .send(wire::request(id, method, params))
            .await?;
        Ok(id)
    }

    pub(crate) async fn await_response(
        &mut self,
        id: i64,
        method: &str,
        timeout: std::time::Duration,
    ) -> Result<Value, ProviderError> {
        tokio::time::timeout(timeout, async {
            loop {
                let message = self.transport.recv().await?.ok_or(ProviderError::Closed)?;
                if self.absorb_skills_message(&message) {
                    continue;
                }
                // A server request can reuse a numeric id. Its method makes it
                // a request before its id can be a response discriminator.
                if wire::method(&message).is_some() {
                    if self.queued_events.len() >= self.config.max_queued_events {
                        return Err(ProviderError::InvalidState(
                            "Codex notification queue is full".into(),
                        ));
                    }
                    if let Some(event) = events::map_message(self, message)? {
                        self.queued_events.push_back(event);
                    }
                    continue;
                }
                if message.get("id").and_then(Value::as_i64) == Some(id) {
                    return wire::result(&message);
                }
                return Err(ProviderError::Protocol(
                    "Codex response id did not match the outstanding request".into(),
                ));
            }
        })
        .await
        .map_err(|_| ProviderError::Timeout {
            operation: method.to_owned(),
        })?
    }

    pub(crate) fn ensure_open(&self) -> Result<(), ProviderError> {
        if self.closed {
            Err(ProviderError::Closed)
        } else {
            Ok(())
        }
    }

    pub(crate) fn thread_params(
        &self,
        input: &SessionStartInput,
    ) -> Result<Map<String, Value>, ProviderError> {
        let mut params = input.options.clone();
        crate::reasoning_effort::thread_options(&mut params)?;
        // The native thread id is controlled by the start/resume operation.
        params.remove("threadId");
        let defaults = crate::policy::runtime_defaults(input.runtime_mode);
        let model = input.model.clone().or_else(|| self.config.model.clone());
        let approval_policy = input
            .approval_policy
            .or(self.config.approval_policy)
            .unwrap_or(defaults.approval_policy);
        let sandbox = input
            .sandbox_mode
            .or(self.config.sandbox_mode)
            .unwrap_or(defaults.sandbox_mode);
        if let Some(cwd) = input.cwd.as_ref().or(self.config.cwd.as_ref()) {
            params.insert(
                "cwd".into(),
                Value::String(cwd.to_string_lossy().into_owned()),
            );
        }
        if let Some(model) = model {
            params.insert("model".into(), Value::String(model));
        }
        params.insert(
            "approvalPolicy".into(),
            serde_json::to_value(approval_policy).expect("approval policy is serializable"),
        );
        params.insert(
            "sandbox".into(),
            serde_json::to_value(sandbox).expect("sandbox mode is serializable"),
        );
        params.insert(
            "approvalsReviewer".into(),
            Value::String(defaults.approvals_reviewer.to_owned()),
        );
        crate::mcp::merge_thread_config(&mut params, &input.mcp_servers)?;
        Ok(params)
    }

    pub(crate) fn turn_params(
        &self,
        input: &TurnInput,
        session: &ProviderSession,
    ) -> Result<Map<String, Value>, ProviderError> {
        let mut params = input.options.clone();
        let effort = crate::reasoning_effort::turn_options(&mut params)?;
        let values = native_input(input)?;
        params.insert(
            "threadId".into(),
            Value::String(session.native_thread_id.clone()),
        );
        params.insert("input".into(), Value::Array(values));
        if let Some(model) = input.model.clone().or_else(|| self.config.model.clone()) {
            params.insert("model".into(), Value::String(model));
        }
        if let Some(cwd) = session.cwd.as_ref().or(self.config.cwd.as_ref()) {
            params.insert(
                "cwd".into(),
                Value::String(cwd.to_string_lossy().into_owned()),
            );
        }
        let defaults = crate::policy::runtime_defaults(self.runtime_mode);
        let approval_policy = self.approval_policy.unwrap_or(defaults.approval_policy);
        let sandbox_mode = self.sandbox_mode.unwrap_or(defaults.sandbox_mode);
        params.insert(
            "approvalPolicy".into(),
            serde_json::to_value(approval_policy).expect("approval policy is serializable"),
        );
        params.insert(
            "approvalsReviewer".into(),
            Value::String(defaults.approvals_reviewer.to_owned()),
        );
        params.insert(
            "sandboxPolicy".into(),
            crate::policy::sandbox_policy(sandbox_mode),
        );
        // Codex keeps the last collaboration mode on the thread, so every turn
        // states its mode; otherwise leaving Plan would keep planning.
        let plan = matches!(
            input.interaction_mode,
            alera_provider_protocol::InteractionMode::Plan
        );
        let model = input
            .model
            .clone()
            .or_else(|| session.model.clone())
            .or_else(|| self.config.model.clone());
        match model {
            Some(model) => {
                let mut settings = Map::new();
                let effort = effort
                    .or_else(|| self.session_effort.clone())
                    .or_else(|| default_reasoning_effort(&model).map(str::to_owned));
                settings.insert("model".into(), Value::String(model));
                if let Some(effort) = effort {
                    settings.insert("reasoning_effort".into(), Value::String(effort));
                }
                params.insert(
                    "collaborationMode".into(),
                    json!({
                        "mode": if plan { "plan" } else { "default" },
                        "settings": settings,
                    }),
                );
            }
            None if plan => {
                return Err(ProviderError::Validation(
                    "plan collaboration mode requires a model".into(),
                ));
            }
            None => {}
        }
        Ok(params)
    }

    pub(crate) async fn initialize_inner(&mut self) -> Result<(), ProviderError> {
        let params = json!({
            "clientInfo": self.config.client_info(),
            "capabilities": {
                "experimentalApi": true,
                "mcpServerOpenaiFormElicitation": true,
            },
        });
        self.call("initialize", params).await?;
        self.transport
            .send(wire::notification("initialized", Value::Object(Map::new())))
            .await?;
        self.initialized = true;
        Ok(())
    }

    pub(crate) fn decode_thread_id(response: &Value) -> Result<String, ProviderError> {
        response
            .get("thread")
            .and_then(|thread| thread.get("id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .map(ToOwned::to_owned)
            .ok_or_else(|| ProviderError::Protocol("Codex response has no thread id".into()))
    }

    pub(crate) fn decode_turn_id(response: &Value) -> Result<String, ProviderError> {
        response
            .get("turn")
            .and_then(|turn| turn.get("id"))
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .ok_or_else(|| ProviderError::Protocol("Codex response has no turn id".into()))
            .map(ToOwned::to_owned)
    }
}

pub(crate) fn native_input(input: &TurnInput) -> Result<Vec<Value>, ProviderError> {
    let mut values = Vec::new();
    if !input.input.is_empty() {
        // Codex only expands `$name`; composers accept any currency sigil.
        let text = alera_provider_protocol::dollar_skill_mentions(&input.input);
        values.push(json!({ "type": "text", "text": text }));
    }
    for attachment in &input.attachments {
        values.push(match attachment {
            Attachment::Image { url } => json!({ "type": "image", "url": url }),
            Attachment::LocalImage { path } => {
                json!({ "type": "localImage", "path": path.to_string_lossy() })
            }
            Attachment::File { .. } => {
                return Err(ProviderError::Unsupported(
                    "Codex app-server does not support file attachments".into(),
                ))
            }
        });
    }
    Ok(values)
}

/// Like T3 Code, an unset effort runs gpt-6-astra at medium; every other
/// model keeps the default Codex picks for it.
fn default_reasoning_effort(model: &str) -> Option<&'static str> {
    let family = model
        .strip_prefix("openai.")
        .filter(|rest| rest.starts_with("gpt-"))
        .unwrap_or(model);
    (family == "gpt-6-astra").then_some("medium")
}
