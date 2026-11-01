//! Claude 5.1+ models write their progress updates as thinking. As T3 Code
//! cae6c6627a, the second of two thinking blocks of one message right
//! before that message's tool call is shown as assistant text; every other
//! thinking block stays reasoning.
//!
//! Each thinking block gets its own `{messageId}:thinking:{n}` item, so a
//! reply that shares the message id never lands in a reasoning item.

use super::*;
use std::collections::HashMap;

#[derive(Debug, Default)]
pub(crate) struct ThinkingProgress {
    /// Thinking blocks seen per message, for the next block's index.
    blocks: HashMap<String, usize>,
    /// The message whose last block was non-empty thinking.
    last_thinking_message: Option<String>,
    held: Option<HeldThinking>,
}

#[derive(Debug)]
struct HeldThinking {
    message_id: String,
    item_id: String,
    text: String,
    raw: Value,
}

/// Whether the model writes progress updates as thinking: Claude 5.1 and
/// later, read from ids such as `claude-opus-5-5` or
/// `us.anthropic.claude-fable-5-1-v1:0`.
pub(crate) fn claude_writes_updates_as_thinking(model: &str) -> bool {
    let Some(start) = model.find("claude-") else {
        return false;
    };
    let rest = &model[start + "claude-".len()..];
    let family = rest.bytes().take_while(u8::is_ascii_lowercase).count();
    if family == 0 || rest.as_bytes().get(family) != Some(&b'-') {
        return false;
    }
    let rest = &rest[family + 1..];
    let major_len = rest.bytes().take_while(u8::is_ascii_digit).count();
    let Ok(major) = rest[..major_len].parse::<u32>() else {
        return false;
    };
    let rest = &rest[major_len..];
    let minor = rest
        .strip_prefix('-')
        .map(|rest| {
            let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
            if (1..=2).contains(&digits) {
                rest[..digits].parse::<u32>().unwrap_or(0)
            } else {
                0
            }
        })
        .unwrap_or(0);
    major > 5 || (major == 5 && minor >= 1)
}

impl ClaudeProvider {
    /// A thinking block: shown as reasoning now, or held when it may be a
    /// progress update.
    pub(super) fn thinking_block(
        &mut self,
        model: &str,
        message_id: Option<&str>,
        text: String,
        raw: &Value,
    ) -> Vec<ProviderEvent> {
        let Some(message_id) = message_id else {
            let raw = self.raw("assistant", raw.clone());
            return vec![self.content_event(StreamKind::ReasoningText, text, raw, None)];
        };
        let mut events = self.release_held_thinking();
        let progress = &mut self.turn_signals.thinking;
        let index = progress.blocks.entry(message_id.to_owned()).or_default();
        let item_id = format!("{message_id}:thinking:{index}");
        *index += 1;
        let follows = progress.last_thinking_message.as_deref() == Some(message_id);
        let non_empty = !text.trim().is_empty();
        if non_empty && follows && claude_writes_updates_as_thinking(model) {
            progress.held = Some(HeldThinking {
                message_id: message_id.to_owned(),
                item_id,
                text,
                raw: raw.clone(),
            });
            return events;
        }
        progress.last_thinking_message = non_empty.then(|| message_id.to_owned());
        let raw = self.raw("assistant", raw.clone());
        events.push(self.content_event(StreamKind::ReasoningText, text, raw, Some(item_id)));
        events
    }

    /// Any other block: a held thinking block becomes assistant text when
    /// this block is its message's tool call, and reasoning otherwise.
    pub(super) fn non_thinking_block(
        &mut self,
        tool_use: bool,
        message_id: Option<&str>,
    ) -> Vec<ProviderEvent> {
        self.turn_signals.thinking.last_thinking_message = None;
        let Some(held) = self.turn_signals.thinking.held.take() else {
            return Vec::new();
        };
        let kind = if tool_use && message_id == Some(held.message_id.as_str()) {
            StreamKind::AssistantText
        } else {
            StreamKind::ReasoningText
        };
        let raw = self.raw("assistant", held.raw);
        vec![self.content_event(kind, held.text, raw, Some(held.item_id))]
    }

    /// Shows a held block as reasoning, before any frame that is not an
    /// assistant block.
    pub(super) fn release_held_thinking(&mut self) -> Vec<ProviderEvent> {
        let Some(held) = self.turn_signals.thinking.held.take() else {
            return Vec::new();
        };
        let raw = self.raw("assistant", held.raw);
        vec![self.content_event(
            StreamKind::ReasoningText,
            held.text,
            raw,
            Some(held.item_id),
        )]
    }

    pub(super) fn holds_thinking(&self) -> bool {
        self.turn_signals.thinking.held.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::claude_writes_updates_as_thinking as writes;

    #[test]
    fn claude_5_1_and_later_write_updates_as_thinking() {
        for model in [
            "claude-opus-5-5",
            "claude-fable-5-1",
            "claude-opus-6",
            "claude-opus-5-5[1m]",
            "us.anthropic.claude-opus-5-5-v1:0",
        ] {
            assert!(writes(model), "{model}");
        }
        for model in [
            "claude-opus-5",
            "claude-sonnet-4-6",
            "claude-opus-5-20261001",
            "opus",
        ] {
            assert!(!writes(model), "{model}");
        }
    }
}
