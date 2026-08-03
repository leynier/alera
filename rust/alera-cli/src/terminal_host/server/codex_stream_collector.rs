//! Streaming batch policy for Codex Markdown deltas.
//!
//! The app-server can emit thousands of tiny fragments for one answer. This
//! policy keeps ordered batches while avoiding commits in the middle of a
//! fenced block, table row, or link. The actual reducer still owns all state.

use std::time::Duration;

use serde_json::Value;

const MAX_MESSAGES: usize = 128;
const TARGET_CHARS: usize = 768;
const HARD_CHARS: usize = 2_048;
const CATCH_UP_MESSAGES: usize = 16;
const SEVERE_CATCH_UP_MESSAGES: usize = 64;

pub(super) fn should_force_flush(messages: &[Value]) -> bool {
    if messages.len() >= MAX_MESSAGES {
        return true;
    }
    let chars = messages.iter().map(delta_chars).sum::<usize>();
    chars >= HARD_CHARS && safe_boundary(messages)
}

pub(super) fn batch_delay(messages: &[Value]) -> Duration {
    let chars = messages.iter().map(delta_chars).sum::<usize>();
    if chars >= HARD_CHARS || messages.len() >= SEVERE_CATCH_UP_MESSAGES {
        Duration::from_millis(12)
    } else if chars >= TARGET_CHARS || messages.len() >= CATCH_UP_MESSAGES {
        Duration::from_millis(20)
    } else {
        Duration::from_millis(32)
    }
}

pub(super) fn safe_boundary(messages: &[Value]) -> bool {
    let text = messages.iter().filter_map(delta_text).collect::<String>();
    if text.is_empty() {
        return true;
    }
    if odd_fence_count(&text)
        || open_link(&text)
        || open_inline_code(&text)
        || open_math(&text)
        || open_html_tag(&text)
    {
        return false;
    }
    let trimmed = text.trim_end();
    if trimmed.starts_with('|') && !trimmed.ends_with('|') {
        return false;
    }
    text.ends_with('\n')
        || text.ends_with(['.', ',', ';', ':', '!', '?', ')', ']', '}', '`'])
        || text.len() >= HARD_CHARS
}

pub(super) fn delta_chars(message: &Value) -> usize {
    delta_text(message).map_or(0, str::len)
}

fn delta_text(message: &Value) -> Option<&str> {
    let params = message.get("params")?;
    params
        .get("delta")
        .or_else(|| params.get("text"))
        .or_else(|| params.get("output"))
        .or_else(|| params.get("interaction"))
        .or_else(|| params.pointer("/item/text"))
        .and_then(Value::as_str)
}

fn odd_fence_count(text: &str) -> bool {
    let mut count = 0;
    let mut offset = 0;
    while let Some(index) = text[offset..].find("```") {
        count += 1;
        offset += index + 3;
    }
    count % 2 == 1
}

fn open_link(text: &str) -> bool {
    let Some(index) = text.rfind("](") else {
        return false;
    };
    !text[index + 2..].contains(')')
}

fn open_inline_code(text: &str) -> bool {
    let mut count = 0;
    let mut offset = 0;
    while let Some(index) = text[offset..].find('`') {
        let index = offset + index;
        if !is_escaped(text, index) && !is_triple_backtick(text, index) {
            count += 1;
        }
        offset = index + 1;
    }
    count % 2 == 1
}

fn open_math(text: &str) -> bool {
    let mut inline = 0;
    let mut block = 0;
    let mut offset = 0;
    while let Some(index) = text[offset..].find('$') {
        let index = offset + index;
        if is_escaped(text, index) {
            offset = index + 1;
            continue;
        }
        if text[index..].starts_with("$$") {
            block += 1;
            offset = index + 2;
        } else {
            inline += 1;
            offset = index + 1;
        }
    }
    block % 2 == 1 || inline % 2 == 1
}

fn open_html_tag(text: &str) -> bool {
    let Some(open) = text.rfind('<') else {
        return false;
    };
    let Some(close) = text.rfind('>') else {
        return text[open + 1..]
            .chars()
            .next()
            .is_some_and(|character| character.is_ascii_alphabetic() || character == '/');
    };
    open > close
}

fn is_escaped(text: &str, index: usize) -> bool {
    let bytes = text.as_bytes();
    let mut offset = index;
    let mut slashes = 0;
    while offset > 0 && bytes[offset - 1] == b'\\' {
        slashes += 1;
        offset -= 1;
    }
    slashes % 2 == 1
}

fn is_triple_backtick(text: &str, index: usize) -> bool {
    let bytes = text.as_bytes();
    (index >= 2 && bytes[index - 2..=index] == *b"```")
        || (index > 0 && index + 1 < bytes.len() && bytes[index - 1..=index + 1] == *b"```")
        || bytes
            .get(index..)
            .is_some_and(|tail| tail.starts_with(b"```"))
}

#[cfg(test)]
mod tests {
    use super::{batch_delay, safe_boundary, should_force_flush};
    use serde_json::json;

    fn delta(text: &str) -> serde_json::Value {
        json!({"method": "item/agentMessage/delta", "params": {"delta": text}})
    }

    #[test]
    fn preserves_partial_markdown_structures() {
        assert!(!safe_boundary(&[delta("```rust\nfn main() {")]));
        assert!(!safe_boundary(&[delta("[docs](https://example")]));
        assert!(!safe_boundary(&[delta("`partial code")]));
        assert!(!safe_boundary(&[delta("$x^2")]));
        assert!(!safe_boundary(&[delta("<span")]));
        assert!(!safe_boundary(&[delta("| name | value")]));
        assert!(safe_boundary(&[delta("| name | value |\n")]));
    }

    #[test]
    fn adapts_delay_as_the_batch_catches_up() {
        let small = vec![delta("x")];
        let large = vec![delta(&"x".repeat(800))];
        let huge = vec![delta(&"x".repeat(2_100))];
        assert!(batch_delay(&small) > batch_delay(&large));
        assert!(batch_delay(&large) > batch_delay(&huge));
        let catch_up = (0..16).map(|_| delta("x")).collect::<Vec<_>>();
        let severe = (0..64).map(|_| delta("x")).collect::<Vec<_>>();
        assert!(batch_delay(&small) > batch_delay(&catch_up));
        assert!(batch_delay(&catch_up) > batch_delay(&severe));
    }

    #[test]
    fn caps_message_count_and_flushes_large_safe_batches() {
        let capped = (0..128).map(|_| delta("x")).collect::<Vec<_>>();
        assert!(should_force_flush(&capped));
        let large = vec![delta(&format!("{}\n", "x".repeat(2_100)))];
        assert!(should_force_flush(&large));
        let partial = vec![delta(&format!("```\n{}", "x".repeat(2_100)))];
        assert!(!should_force_flush(&partial));
    }
}
