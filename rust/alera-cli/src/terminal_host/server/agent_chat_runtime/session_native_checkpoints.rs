//! Explicit checkpoint launch settings and observed user-message identities.

use alera_provider_protocol::ProviderEvent;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::unsupported;
use super::session::{ChatSession, CLOSE_TIMEOUT};

impl ChatSession {
    pub(super) fn file_checkpointing_enabled(&self) -> bool {
        self.header.session.extra.get("fileCheckpointing") == Some(&Value::Bool(true))
    }

    pub(super) async fn configure_file_checkpoints(&mut self, enabled: bool) -> HostResult<Value> {
        self.require_idle("changing file checkpointing")?;
        if self.header.provider != "claudeAgent" {
            return Err(unsupported("This agent cannot launch file checkpointing."));
        }
        if enabled != self.file_checkpointing_enabled() {
            self.revoke_launch_credentials("fileCheckpointingChanged")
                .await;
            if let Some(mut provider) = self.provider.take() {
                let _ = tokio::time::timeout(CLOSE_TIMEOUT, provider.close()).await;
            }
            self.events_armed = false;
            self.live_caps = None;
            self.header
                .session
                .extra
                .insert("fileCheckpointing".into(), json!(enabled));
            self.set_status("stopped");
            self.notify_chats();
        }
        self.snapshot().await
    }

    /// An adapter attaches both identities only to a verified submitted-prompt
    /// echo. The original app item remains the only visible user message.
    pub(super) async fn record_native_user_echo(
        &mut self,
        event: &ProviderEvent,
    ) -> Result<(), String> {
        if self.header.provider != "claudeAgent" {
            return Ok(());
        }
        let Some(native) = event
            .payload
            .get("nativeUserMessageId")
            .and_then(Value::as_str)
        else {
            return Ok(());
        };
        if uuid::Uuid::parse_str(native).is_err() {
            return Ok(());
        }
        let Some(item_id) = event.payload.get("appUserItemId").and_then(Value::as_str) else {
            return Ok(());
        };
        let Some(native_turn) = event.turn_id.as_deref() else {
            return Ok(());
        };
        let turn = self
            .deps
            .store
            .agent_chat_native_id_for_app(
                &self.header.chat_id,
                self.generation,
                &self.epoch_kind("turn"),
                &self.app_turn_id(event).unwrap_or_default(),
            )
            .await
            .map_err(|error| error.to_string())?;
        let Some(turn) = turn.filter(|turn| turn.native_id.as_str() == Some(native_turn)) else {
            return Ok(());
        };
        let item = match self.items.get(item_id) {
            Some(item) => Some(super::wire::json(item)),
            None => self
                .deps
                .store
                .agent_chat_item(&self.header.chat_id, item_id)
                .await
                .map_err(|error| error.to_string())?,
        };
        let Some(item) = item.filter(|item| {
            item["type"] == "user_message"
                && item["turnId"] == turn.app_id
                && item["generation"].as_i64() == Some(self.generation)
                && item
                    .get("clientMessageId")
                    .and_then(Value::as_str)
                    .is_some()
        }) else {
            return Ok(());
        };
        let item_id = item["itemId"].as_str().unwrap_or_default();
        self.map_native("userMessage", json!(native), item_id).await;
        self.map_native("userTurn", json!(native), &turn.app_id)
            .await;
        Ok(())
    }

    pub(super) async fn current_native_boundary(
        &mut self,
        kind: &str,
        app_id: &str,
    ) -> HostResult<String> {
        let mapping = self
            .deps
            .store
            .agent_chat_native_id_for_app(
                &self.header.chat_id,
                self.generation,
                &self.epoch_kind(kind),
                app_id,
            )
            .await
            .map_err(|_| unsupported("This turn has conflicting native boundaries."))?;
        mapping
            .filter(|mapping| mapping.kind == self.epoch_kind(kind))
            .and_then(|mapping| mapping.native_id.as_str().map(str::to_owned))
            .filter(|native| !native.is_empty())
            .ok_or_else(|| {
                HostError::conflict(
                    "unsupported",
                    "This turn has no verified boundary in the current agent process.",
                    json!({}),
                )
            })
    }
}
