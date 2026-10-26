//! Folds canonical provider events into chat items, turns, requests and
//! usage. Native ids are mapped to runtime ids here and nowhere else.

use alera_core::runtime::AgentChatNativeIdInput;
use alera_provider_protocol::{
    ContentDeltaPayload, EventKind, ItemLifecyclePayload, ProviderEvent, StreamKind,
};
use serde_json::{json, Value};

use super::ids::{native_key, new_id, now};
use super::item_normalization::{bounded_data, final_output, final_text, project_item_data};
use super::session::ChatSession;
use super::session_turns::TurnEnd;
use super::wire::{json, ChatItem, STREAM_OUTPUT, STREAM_REASONING, STREAM_TEXT};

impl ChatSession {
    pub(super) async fn apply_provider_event(&mut self, event: ProviderEvent) {
        if let Some(turn_id) = event.turn_id.as_deref() {
            self.adopt_turn(turn_id).await;
        }
        match &event.kind {
            EventKind::ThreadStarted | EventKind::SessionStarted | EventKind::SessionConfigured => {
                let native = event.payload["providerThreadId"]
                    .as_str()
                    .map(str::to_string)
                    .or_else(|| {
                        self.provider
                            .as_ref()
                            .and_then(|provider| provider.session())
                            .map(|session| session.native_thread_id.clone())
                    });
                if let Some(native) = native {
                    self.record_native_session(&native).await;
                }
            }
            EventKind::SessionExited => {
                self.provider_failed("The provider session exited.".into())
                    .await;
                return;
            }
            EventKind::TurnStarted => {
                let model = event.payload["model"].as_str().map(str::to_string);
                if let (Some(active), Some(model)) =
                    (self.header.session.active_turn_id.clone(), model)
                {
                    if let Some(turn) = self.header.turn_mut(&active) {
                        turn.model = Some(model);
                    }
                }
            }
            EventKind::TurnCompleted => {
                self.apply_token_usage(&event.payload["tokenUsage"]);
                let state = event.payload["state"]
                    .as_str()
                    .unwrap_or("completed")
                    .to_string();
                let error = event.payload["errorMessage"].as_str().map(str::to_string);
                self.end_turn(TurnEnd {
                    failure_class: event.failure_class(),
                    child_turns_continue: event.child_turns_continue(),
                    ..TurnEnd::new(&state, error, None)
                })
                .await;
                self.drain_queue().await;
                return;
            }
            EventKind::TurnAborted => {
                self.apply_token_usage(&event.payload["tokenUsage"]);
                let reason = event.payload["reason"]
                    .as_str()
                    .unwrap_or("aborted")
                    .to_string();
                self.finish_turn("interrupted", None, Some(reason)).await;
                self.drain_queue().await;
                return;
            }
            EventKind::TurnPlanUpdated => {
                if let Err(error) = self.apply_plan(&event).await {
                    self.record_projection_error(&error);
                }
            }
            EventKind::TurnDiffUpdated => {
                if let Some(turn_id) = self.app_turn_id(&event) {
                    if let Err(error) = self.record_turn_diff(&turn_id, &event.payload).await {
                        self.record_projection_error(&error);
                    }
                }
            }
            EventKind::ItemStarted | EventKind::ItemUpdated | EventKind::ItemCompleted => {
                if let Err(error) = self.apply_item(&event).await {
                    self.record_projection_error(&error);
                }
                if matches!(&event.kind, EventKind::ItemCompleted) {
                    let _ = self.flush().await;
                    return;
                }
            }
            EventKind::ContentDelta => {
                if let Err(error) = self.apply_delta(&event).await {
                    self.record_projection_error(&error);
                }
            }
            EventKind::RequestOpened | EventKind::UserInputRequested => {
                self.open_request(&event).await;
                let _ = self.flush().await;
                return;
            }
            EventKind::RequestResolved | EventKind::UserInputResolved => {
                self.resolve_request_from_provider(&event);
            }
            EventKind::TaskStarted
            | EventKind::TaskProgress
            | EventKind::TaskUpdated
            | EventKind::TaskCompleted => {
                self.track_awaited_task(&event);
                self.apply_subagent_task(&event).await;
            }
            EventKind::ThreadTokenUsageUpdated => self.apply_token_usage(&event.payload),
            EventKind::AccountRateLimitsUpdated => {
                let windows = event.payload["limits"]["windows"].clone();
                let usage = self.header.usage.get_or_insert_with(|| json!({}));
                usage["windows"] = windows;
            }
            EventKind::RuntimeError => {
                let message = event.payload["message"]
                    .as_str()
                    .unwrap_or("Provider error");
                self.add_notice("error", message, event.payload.get("detail"));
            }
            EventKind::RuntimeWarning | EventKind::ModelRerouted | EventKind::ToolDenied => {
                let message = event.payload["message"]
                    .as_str()
                    .map(str::to_string)
                    .unwrap_or_else(|| event.kind.as_str().to_string());
                self.add_notice("notice", &message, None);
            }
            _ => {}
        }
        self.schedule_flush().await;
    }

    /// Maps the provider's turn id onto the running app turn.
    async fn adopt_turn(&mut self, native_turn: &str) {
        let key = native_key(&self.epoch_kind("turn"), &Value::String(native_turn.into()));
        if self.native_ids.contains_key(&key) {
            return;
        }
        if let Some(turn_id) = self.header.session.active_turn_id.clone() {
            self.map_native_turn(native_turn, &turn_id).await;
        }
    }

    pub(super) fn epoch_kind(&self, kind: &str) -> String {
        format!("{kind}@{}", self.process_epoch)
    }

    pub(super) async fn map_native_turn(&mut self, native_turn: &str, app_turn: &str) {
        self.map_native("turn", Value::String(native_turn.into()), app_turn)
            .await;
    }

    /// Records a native id under this process's kind. The in-memory map is
    /// authoritative for the live process; the stored row keeps the link.
    pub(super) async fn map_native(&mut self, kind: &str, native: Value, app_id: &str) {
        let kind = self.epoch_kind(kind);
        let key = native_key(&kind, &native);
        if self.native_ids.get(&key).map(String::as_str) == Some(app_id) {
            return;
        }
        self.native_ids.insert(key, app_id.to_string());
        let input = AgentChatNativeIdInput {
            chat_id: self.header.chat_id.clone(),
            generation: self.generation,
            kind,
            native_id: native,
            app_id: Some(app_id.to_string()),
        };
        if let Err(error) = self.deps.store.map_agent_chat_native_id(&input).await {
            tracing::debug!(chat_id = %self.header.chat_id, error = %error, "agent chat native id kept in memory only");
        }
    }

    pub(super) fn app_turn_id(&self, event: &ProviderEvent) -> Option<String> {
        event
            .turn_id
            .as_deref()
            .and_then(|id| {
                self.native_ids
                    .get(&native_key(
                        &self.epoch_kind("turn"),
                        &Value::String(id.into()),
                    ))
                    .cloned()
            })
            .or_else(|| self.header.session.active_turn_id.clone())
    }

    /// The app id for a native item, allocating one on first sight.
    pub(super) async fn app_item_id(&mut self, native: &str) -> String {
        let key = native_key(&self.epoch_kind("item"), &Value::String(native.into()));
        if let Some(id) = self.native_ids.get(&key) {
            return id.clone();
        }
        let id = new_id("item");
        self.map_native("item", Value::String(native.into()), &id)
            .await;
        id
    }

    /// Brings back an item of an earlier turn that the provider updates late.
    pub(super) async fn load_item(&mut self, item_id: &str) {
        if self.items.contains_key(item_id) {
            return;
        }
        if let Ok(Some(stored)) = self
            .deps
            .store
            .agent_chat_item(&self.header.chat_id, item_id)
            .await
        {
            if let Ok(item) = serde_json::from_value::<ChatItem>(stored) {
                self.items.insert(item_id.to_string(), item);
            }
        }
    }

    fn item_entry(
        &mut self,
        item_id: &str,
        item_type: &str,
        turn_id: Option<String>,
    ) -> &mut ChatItem {
        if !self.items.contains_key(item_id) {
            let mut item = ChatItem::new(item_id.into(), item_type, &now(), self.generation);
            item.turn_id = turn_id;
            self.insert_item(item);
        }
        self.items.get_mut(item_id).expect("item was inserted")
    }

    async fn apply_item(&mut self, event: &ProviderEvent) -> Result<(), String> {
        let Ok(payload) = serde_json::from_value::<ItemLifecyclePayload>(event.payload.clone())
        else {
            return Ok(());
        };
        let item_type = json(&payload.item_type)
            .as_str()
            .unwrap_or("unknown")
            .to_string();
        // The runtime records the user's message itself when it sends it.
        if item_type == "user_message" {
            self.record_native_user_echo(event).await?;
            return Ok(());
        }
        let native = event.item_id.clone().unwrap_or_else(|| {
            format!("{}:{item_type}", event.turn_id.clone().unwrap_or_default())
        });
        let item_id = self.app_item_id(&native).await;
        self.load_item(&item_id).await;
        let turn_id = self.app_turn_id(event);
        let completed = matches!(&event.kind, EventKind::ItemCompleted);
        let final_text_value = completed
            .then(|| payload.data.as_ref().and_then(final_text))
            .flatten();
        let final_output_value = completed
            .then(|| payload.data.as_ref().and_then(final_output))
            .flatten();
        let mut projected_payload = None;
        let mut has_data = false;
        let (set_text, set_output) = {
            let item = self.item_entry(&item_id, &item_type, turn_id.clone());
            item.item_type = item_type.clone();
            if let Some(status) = payload.status {
                item.status = json(&status).as_str().unwrap_or("inProgress").to_string();
            } else if completed {
                item.status = "completed".into();
            }
            item.streaming = !completed && item.status == "inProgress";
            if payload.title.is_some() {
                item.title = payload.title.clone();
            }
            if payload.detail.is_some() {
                item.detail = payload.detail.clone();
            }
            if let Some(data) = payload.data.as_ref() {
                has_data = true;
                let projected =
                    project_item_data(&item_type, data, canonical_data_fields(&item_type));
                for (key, value) in projected.normalized {
                    item.normalized.insert(key, value);
                }
                item.data = projected.data;
                projected_payload = projected.payload;
            }
            let set_text = completed
                && item.text.as_deref().is_none_or(str::is_empty)
                && final_text_value.is_some();
            let set_output = completed
                && item.output.as_deref().is_none_or(str::is_empty)
                && final_output_value.is_some();
            item.updated_at = now();
            self.pending.item(&item_id);
            (set_text, set_output)
        };
        self.rebalance_streams(&item_id).await?;
        if set_text {
            if let Some(text) = final_text_value.as_deref() {
                self.set_complete_stream(&item_id, &item_type, turn_id.clone(), STREAM_TEXT, text)
                    .await?;
            }
        }
        if set_output {
            if let Some(output) = final_output_value.as_deref() {
                self.set_complete_stream(
                    &item_id,
                    &item_type,
                    turn_id.clone(),
                    STREAM_OUTPUT,
                    output,
                )
                .await?;
            }
        }
        if has_data {
            self.set_item_payload(&item_id, projected_payload.as_deref())
                .await?;
        }
        self.rebalance_streams(&item_id).await?;
        self.record_subagent_threads(&item_id, event).await;
        self.link_subagent_item(&item_id, event).await;
        Ok(())
    }

    async fn apply_delta(&mut self, event: &ProviderEvent) -> Result<(), String> {
        let Ok(payload) = serde_json::from_value::<ContentDeltaPayload>(event.payload.clone())
        else {
            return Ok(());
        };
        let (stream, item_type) = match payload.stream_kind {
            StreamKind::AssistantText => (STREAM_TEXT, "assistant_message"),
            StreamKind::PlanText => (STREAM_TEXT, "plan"),
            StreamKind::ReasoningSummaryText => (STREAM_TEXT, "reasoning"),
            StreamKind::ReasoningText => (STREAM_REASONING, "reasoning"),
            StreamKind::CommandOutput => (STREAM_OUTPUT, "command_execution"),
            StreamKind::FileChangeOutput => (STREAM_OUTPUT, "file_change"),
            StreamKind::Unknown => (STREAM_OUTPUT, "unknown"),
        };
        let native = event.item_id.clone().unwrap_or_else(|| {
            format!("{}:{item_type}", event.turn_id.clone().unwrap_or_default())
        });
        let parent_item_id = self.app_item_id(&native).await;
        self.load_item(&parent_item_id).await;
        let turn_id = self.app_turn_id(event);
        self.append_stream(&parent_item_id, item_type, turn_id, stream, &payload.delta)
            .await?;
        self.link_subagent_item(&parent_item_id, event).await;
        Ok(())
    }

    async fn apply_plan(&mut self, event: &ProviderEvent) -> Result<(), String> {
        let Some(turn_id) = self.header.session.active_turn_id.clone() else {
            return Ok(());
        };
        let item_id = self.app_item_id(&format!("plan:{turn_id}")).await;
        let projected = project_item_data("plan", &event.payload, &[]);
        let payload = projected.payload;
        {
            let item = self.item_entry(&item_id, "plan", Some(turn_id));
            for (key, value) in projected.normalized {
                item.normalized.insert(key, value);
            }
            item.data = projected.data;
            item.status = "inProgress".into();
            item.updated_at = now();
        }
        self.pending.item(&item_id);
        self.rebalance_streams(&item_id).await?;
        self.set_item_payload(&item_id, payload.as_deref()).await?;
        Ok(())
    }

    fn apply_token_usage(&mut self, usage: &Value) {
        if !usage.is_object() {
            return;
        }
        let mut tokens = json!({});
        for (canonical, wire) in [
            ("inputTokens", "input"),
            ("outputTokens", "output"),
            ("cachedInputTokens", "cached"),
            ("reasoningTokens", "reasoning"),
            ("contextTokens", "context"),
            ("contextWindow", "contextWindow"),
        ] {
            if let Some(value) = usage.get(canonical).filter(|value| value.is_u64()) {
                tokens[wire] = value.clone();
            }
        }
        if tokens.as_object().is_some_and(|tokens| tokens.is_empty()) {
            return;
        }
        let entry = self.header.usage.get_or_insert_with(|| json!({}));
        entry["tokens"] = tokens;
    }

    fn add_notice(&mut self, item_type: &str, message: &str, detail: Option<&Value>) {
        let mut item = ChatItem::new(new_id("item"), item_type, &now(), self.generation);
        item.turn_id = self.header.session.active_turn_id.clone();
        item.status = "completed".into();
        item.title = Some(message.chars().take(2000).collect());
        item.data = bounded_data(detail);
        self.insert_item(item);
    }

    fn record_projection_error(&mut self, error: &str) {
        self.add_notice(
            "error",
            "The provider event could not be persisted.",
            Some(&json!({"message": error})),
        );
    }
}

fn canonical_data_fields(item_type: &str) -> &'static [&'static str] {
    match item_type {
        "assistant_message" | "plan" | "reasoning" => &["text", "message"],
        "command_execution"
        | "file_change"
        | "mcp_tool_call"
        | "dynamic_tool_call"
        | "collab_agent_tool_call" => &["output", "aggregatedOutput"],
        _ => &[],
    }
}
