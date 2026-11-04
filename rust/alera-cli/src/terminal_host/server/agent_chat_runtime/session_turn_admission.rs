use std::path::PathBuf;

use alera_provider_protocol::Attachment;
use serde_json::{json, Value};

use super::commands::{CallerCtx, SendInput};
use super::ids::{new_id, now, payload_digest};
use super::item_normalization::segment_complete_item;
use super::session::ChatSession;
use super::wire::{ChatItem, ChatTurn, STREAM_TEXT};

/// [declines] joins the digest only when present, so receipts stored before
/// redirects existed still match their retries.
pub(super) fn client_message_digest(input: &SendInput, declines: &[String]) -> String {
    let mut digest = json!({
        "text": input.text,
        "attachments": input.attachments,
        "delivery": input.delivery,
        "model": input.model,
        "reasoningEffort": input.reasoning_effort,
        "interactionMode": input.interaction_mode,
        "origin": input.origin,
    });
    if !declines.is_empty() {
        digest["declineRequests"] = json!(declines);
    }
    payload_digest(&digest)
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
                _ => path.map(|path| Attachment::File {
                    path,
                    name: attachment
                        .get("name")
                        .and_then(Value::as_str)
                        .filter(|name| !name.trim().is_empty())
                        .map(str::to_owned),
                }),
            }
        })
        .collect()
}

/// Commands the provider parses from the prompt even before it lists them.
const BUILT_IN_COMMANDS: [&str; 2] = ["compact", "goal"];

/// The name of the slash command `text` starts with: `/name` alone or
/// followed by whitespace.
pub(super) fn slash_command_name(text: &str) -> Option<&str> {
    let rest = text.trim().strip_prefix('/')?;
    let name = rest.split(char::is_whitespace).next()?;
    (!name.is_empty() && !name.contains('/')).then_some(name)
}

impl ChatSession {
    /// Whether `text` invokes one of the provider's slash commands, which
    /// must reach it verbatim to run as a command.
    pub(super) fn is_slash_command(&self, text: &str) -> bool {
        slash_command_name(text).is_some_and(|name| {
            BUILT_IN_COMMANDS
                .iter()
                .any(|command| command.eq_ignore_ascii_case(name))
                || self
                    .header
                    .session
                    .commands
                    .iter()
                    .any(|command| command.name.eq_ignore_ascii_case(name))
        })
    }

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
            origin: None,
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

#[cfg(test)]
mod tests {
    use super::{provider_attachments, slash_command_name};
    use alera_provider_protocol::Attachment;
    use serde_json::json;
    use std::path::PathBuf;

    #[test]
    fn provider_attachments_keep_the_person_s_file_name() {
        let attachments = provider_attachments(&[
            json!({
                "type": "file",
                "path": "/rt/agent-chat-attachments/u.data.pdf",
                "name": "spec.pdf",
                "attachmentId": "u",
                "sizeBytes": 12
            }),
            json!({"type": "file", "path": "/w/notes.md", "name": "  "}),
            json!({"type": "localImage", "path": "/w/shot.png", "name": "shot.png"}),
            json!({"type": "image", "url": "https://example.test/a.png"}),
            json!({"type": "file", "name": "orphan.txt"}),
        ]);

        assert_eq!(
            attachments,
            vec![
                Attachment::File {
                    path: PathBuf::from("/rt/agent-chat-attachments/u.data.pdf"),
                    name: Some("spec.pdf".into()),
                },
                Attachment::File {
                    path: PathBuf::from("/w/notes.md"),
                    name: None,
                },
                Attachment::LocalImage {
                    path: PathBuf::from("/w/shot.png"),
                },
                Attachment::Image {
                    url: "https://example.test/a.png".into(),
                },
            ]
        );
    }

    #[test]
    fn a_slash_command_is_one_token_after_the_slash() {
        assert_eq!(slash_command_name("/compact"), Some("compact"));
        assert_eq!(
            slash_command_name("  /review focus on auth\n"),
            Some("review")
        );
        assert_eq!(slash_command_name("/home/me/notes.txt is empty"), None);
        assert_eq!(slash_command_name("/ compact"), None);
        assert_eq!(slash_command_name("Please /compact"), None);
    }
}
