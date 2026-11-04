use super::super::{commands, header, provider_traits};
use super::*;

impl AgentChatRuntime {
    pub(crate) async fn create(
        &self,
        input: CreateChatInput,
        ctx: CallerCtx,
        receipt_key: Option<ReceiptKey>,
    ) -> HostResult<Value> {
        let instance_id = input
            .provider_instance_id
            .clone()
            .or_else(|| input.provider.clone())
            .unwrap_or_else(|| alera_core::runtime::AGENT_CHAT_UNSELECTED_PROVIDER.into());
        let unselected = instance_id == alera_core::runtime::AGENT_CHAT_UNSELECTED_PROVIDER;
        let provider = if unselected {
            instance_id.clone()
        } else {
            self.inner
                .deps
                .instances
                .provider_of(&instance_id, input.provider.as_deref())
                .ok_or_else(|| {
                    conflict(
                        "providerUnavailable",
                        format!("Unknown provider instance {instance_id}"),
                    )
                })?
        };
        let traits = provider_traits(&provider);
        if !unselected && traits.is_none() {
            return Err(conflict("providerUnavailable", "Unknown provider"));
        }
        if unselected && (input.model.is_some() || input.reasoning_effort.is_some()) {
            return Err(conflict(
                "providerRequired",
                "Choose an agent before selecting a model or effort.",
            ));
        }
        let workspace = self
            .inner
            .deps
            .tabs
            .workspace(&input.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("Unknown workspace {}", input.workspace_id)))?;
        if workspace.host_id != "local" {
            return Err(HostError::conflict(
                "host_unavailable",
                "The local chat runtime cannot start a chat on a remote host.",
                json!({"hostId": workspace.host_id}),
            ));
        }
        if workspace.archived {
            return Err(HostError::state(
                "Unarchive the workspace before starting a chat.",
            ));
        }
        let runtime_mode = input
            .runtime_mode
            .clone()
            .unwrap_or_else(|| "approval-required".into());
        let interaction_mode = input
            .interaction_mode
            .clone()
            .unwrap_or_else(|| "default".into());
        if traits
            .as_ref()
            .map(|traits| !traits.runtime_modes.contains(&runtime_mode.as_str()))
            .unwrap_or(provider_traits::parse_runtime_mode(&runtime_mode).is_none())
        {
            return Err(commands::unsupported(format!(
                "{provider} does not support the {runtime_mode} runtime mode."
            )));
        }
        if traits
            .as_ref()
            .map(|traits| {
                !traits
                    .interaction_modes
                    .contains(&interaction_mode.as_str())
            })
            .unwrap_or(!matches!(interaction_mode.as_str(), "default" | "plan"))
        {
            return Err(commands::unsupported(format!(
                "{provider} does not support the {interaction_mode} interaction mode."
            )));
        }
        let model = input.model.clone().or_else(|| {
            self.inner
                .deps
                .instances
                .find(&instance_id)
                .and_then(|instance| instance.default_model)
        });
        if let Some(effort) = input.reasoning_effort.as_deref() {
            let instance = self.inner.deps.instances.find(&instance_id);
            self.inner
                .deps
                .factory
                .validate_reasoning_effort(
                    &provider,
                    instance.as_ref(),
                    Some(workspace.path.clone()),
                    model.as_deref(),
                    effort,
                )
                .await
                .map_err(commands::unsupported)?;
        }
        let chat_id = uuid::Uuid::new_v4().to_string();
        let tab_id = new_id("tab");
        let title = input
            .title
            .clone()
            .map(|title| title.trim().chars().take(200).collect())
            .filter(|title: &String| !title.is_empty())
            .unwrap_or_else(|| {
                self.inner
                    .deps
                    .instances
                    .find(&instance_id)
                    .and_then(|instance| instance.label)
                    .unwrap_or_else(|| {
                        traits
                            .as_ref()
                            .map(|traits| traits.label)
                            .unwrap_or("Agent Chat")
                            .into()
                    })
            });
        let title_source = if input
            .title
            .as_ref()
            .is_some_and(|title| !title.trim().is_empty())
        {
            "user"
        } else {
            "default"
        };
        let capabilities = provider_traits::capabilities_json(&provider, None);
        let snapshot = Header::from_snapshot(json!({
            "chatId": chat_id.clone(),
            "workspaceId": input.workspace_id.clone(),
            "tabId": tab_id.clone(),
            "providerInstanceId": instance_id.clone(),
            "provider": provider.clone(),
            "title": title.clone(),
            "titleSource": title_source,
            "cursor": 0,
            "session": {
                "status": "stopped",
                "model": model.clone(),
                "reasoningEffort": input.reasoning_effort,
                "runtimeMode": runtime_mode.clone(),
                "interactionMode": interaction_mode.clone(),
                "cwd": workspace.path.to_string_lossy(),
                "generation": 1,
                "capabilities": capabilities,
            },
            "lineage": header::lineage_from_metadata(input.metadata.as_ref()),
            "turns": [], "items": [], "pendingRequests": [], "queue": []
        }))
        .map_err(HostError::state)?
        .to_snapshot();
        let stamp = chrono::Utc::now();
        let record = AgentChatRecord {
            chat_id: chat_id.clone(),
            tab_id: tab_id.clone(),
            workspace_id: input.workspace_id.clone(),
            provider_instance_id: instance_id.clone(),
            provider: provider.clone(),
            native_thread_id: None,
            generation: 1,
            archived: false,
            archived_at: None,
            cursor: 0,
            created_at: stamp,
            updated_at: stamp,
            metadata: input.metadata.clone(),
            snapshot,
        };
        let mut tab_payload = chat_tab_payload(&chat_id, &provider, &instance_id, model.as_deref());
        if unselected {
            tab_payload["provider"] = Value::Null;
            tab_payload["providerInstanceId"] = Value::Null;
        }
        let tab = chat_tab_record(&tab_id, &input.workspace_id, &title, tab_payload);
        let receipt = receipt_key.as_ref().map(|key| AgentChatReceipt {
            caller_scope: receipt_scope(&ctx.scope, &key.verb),
            request_id: key.request_id.clone(),
            digest: key.digest.clone(),
            receipt: json!({"chatId": chat_id, "tabId": tab_id}),
        });
        let created = self
            .inner
            .deps
            .store
            .create_agent_chat(&record, &tab, receipt.as_ref())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        match created {
            AgentChatCreateOutcome::Replay(response) => return Ok(response),
            AgentChatCreateOutcome::ReceiptConflict => {
                return Err(conflict(
                    "request_conflict",
                    "This requestId was already used for a different request.",
                ));
            }
            AgentChatCreateOutcome::Created(_) => {}
        }
        self.inner
            .deps
            .sink
            .emit(ChatRuntimeEvent::ChatsChanged {
                workspace_id: Some(input.workspace_id.clone()),
            })
            .await;
        self.inner
            .deps
            .sink
            .emit(ChatRuntimeEvent::TabsChanged {
                workspace_id: input.workspace_id,
            })
            .await;
        self.created_response(&chat_id).await
    }

    async fn created_response(&self, chat_id: &str) -> HostResult<Value> {
        let snapshot = self.snapshot(chat_id).await?;
        Ok(json!({"chatId": chat_id, "tabId": snapshot["tabId"], "snapshot": snapshot}))
    }
}
