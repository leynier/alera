use std::path::PathBuf;

use alera_provider_protocol::Attachment;
use serde_json::{json, Value};

use super::commands::{CallerCtx, SendInput};
use super::ids::{new_id, now, payload_digest};
use super::item_normalization::segment_complete_item;
use super::session::ChatSession;
use super::wire::{ChatItem, ChatTurn, STREAM_TEXT};

pub(super) fn client_message_digest(input: &SendInput) -> String {
    payload_digest(&json!({
        "text": input.text,
        "attachments": input.attachments,
        "delivery": input.delivery,
        "model": input.model,
        "reasoningEffort": input.reasoning_effort,
        "interactionMode": input.interaction_mode,
        "origin": input.origin,
    }))
}

pub(super) fn provider_attachments(attachments: &[Value]) -> Vec<Attachment> {
    attachments
        .iter()
        .filter_map(|attachment| {
            let path = attachment
                .get("path")
                .and_then(Value::as_str)
                .map(PathBuf::from);
            match attachment.get("type").and_then(Value::as_str) {
                Some("image") => attachment
                    .get("url")
                    .and_then(Value::as_str)
                    .map(|url| Attachment::Image { url: url.into() }),
                Some("localImage") => path.map(|path| Attachment::LocalImage { path }),
                _ => path.map(|path| Attachment::File { path }),
            }
        })
        .collect()
}

impl ChatSession {
    pub(super) async fn derive_first_send_title(&mut self, text: &str) {
        if !self.never_sent() || self.header.title_source != "default" {
            return;
        }
        let title: String = text
            .lines()
            .find(|line| !line.trim().is_empty())
            .unwrap_or_default()
            .trim()
            .chars()
            .take(200)
            .collect();
        if title.is_empty() {
            return;
        }
        self.header.title = title;
        self.header.title_source = "derived".into();
        if let Ok(Some(workspace_id)) = self
            .deps
            .tabs
            .rename_tab(&self.header.tab_id, &self.header.title)
            .await
        {
            self.notify_tabs(workspace_id);
        }
        self.notify_chats();
    }

    pub(super) async fn record_rejected_queued_turn(
        &mut self,
        input: SendInput,
        ctx: &CallerCtx,
        error_message: String,
    ) {
        let stamp = now();
        let turn_id = new_id("turn");
        let turn = ChatTurn {
            turn_id: turn_id.clone(),
            status: "failed".into(),
            started_at: stamp.clone(),
            completed_at: Some(stamp.clone()),
            error_message: Some(error_message),
            failure_class: None,
            reason: Some("admissionFailed".into()),
            model: input
                .model
                .clone()
                .or_else(|| self.header.session.model.clone()),
            reasoning_effort: input
                .reasoning_effort
                .clone()
                .or_else(|| self.header.session.reasoning_effort.clone()),
            provider: self.header.provider.clone(),
            provider_instance_id: self.header.provider_instance_id.clone(),
            generation: self.generation,
        };
        let mut item = ChatItem::new(new_id("item"), "user_message", &stamp, self.generation);
        item.turn_id = Some(turn_id);
        item.status = "failed".into();
        item.client_message_id = Some(input.client_message_id);
        item.actor = Some(ctx.actor.clone());
        item.normalized.insert(
            "origin".into(),
            input.origin.unwrap_or_else(|| json!({"kind": "user"})),
        );
        if !input.attachments.is_empty() {
            item.attachments = Some(input.attachments);
        }
        let segments = match segment_complete_item(item, STREAM_TEXT, &input.text) {
            Ok(segments) => segments,
            Err(error) => {
                tracing::error!(chat_id = %self.header.chat_id, error, "failed queued message projection");
                return;
            }
        };
        self.header.upsert_turn(turn);
        for item in segments {
            self.insert_item(item);
        }
    }
}
