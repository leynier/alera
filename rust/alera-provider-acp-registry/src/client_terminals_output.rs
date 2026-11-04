use crate::client_terminals::{TerminalState, MAX_RETAINED_OUTPUT_BYTES};
use alera_provider_protocol::{CanonicalItemType, EventKind, ProviderEvent};
use serde_json::{json, Value};
use std::collections::VecDeque;

pub(crate) struct TerminalOutputBuffer {
    bytes: VecDeque<u8>,
    limit: usize,
    pub(crate) truncated: bool,
}

impl TerminalOutputBuffer {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            bytes: VecDeque::new(),
            limit,
            truncated: false,
        }
    }

    pub(crate) fn len(&self) -> usize {
        self.bytes.len()
    }

    pub(crate) fn append(&mut self, chunk: &[u8]) {
        if chunk.len() >= self.limit {
            self.truncated |= !self.bytes.is_empty() || chunk.len() > self.limit;
            self.bytes.clear();
            self.bytes.extend(&chunk[chunk.len() - self.limit..]);
        } else {
            self.trim(
                self.len()
                    .saturating_add(chunk.len())
                    .saturating_sub(self.limit),
            );
            self.bytes.extend(chunk);
        }
    }

    pub(crate) fn trim(&mut self, amount: usize) {
        let amount = amount.min(self.len());
        self.truncated |= amount > 0;
        self.bytes.drain(..amount);
    }

    pub(crate) fn text(&self) -> String {
        let bytes = self.bytes.iter().copied().collect::<Vec<_>>();
        let start = if self.truncated {
            bytes
                .iter()
                .position(|byte| byte & 0xc0 != 0x80)
                .unwrap_or(bytes.len())
        } else {
            0
        };
        String::from_utf8_lossy(&bytes[start..]).into_owned()
    }
}

pub(crate) fn append_output(state: &mut TerminalState, terminal_id: &str, bytes: &[u8]) {
    let Some(record) = state.terminals.get_mut(terminal_id) else {
        return;
    };
    record.buffer.append(bytes);
    let total = state
        .terminals
        .values()
        .map(|record| record.buffer.len())
        .sum::<usize>();
    let mut excess = total.saturating_sub(MAX_RETAINED_OUTPUT_BYTES);
    for terminal in state.terminals.values_mut() {
        if excess == 0 {
            break;
        }
        let amount = excess.min(terminal.buffer.len());
        terminal.buffer.trim(amount);
        excess -= amount;
    }
}

pub(crate) fn normalize_terminal_content(event: &mut ProviderEvent, state: &TerminalState) {
    if !matches!(
        event.kind,
        EventKind::ItemStarted | EventKind::ItemUpdated | EventKind::ItemCompleted
    ) {
        return;
    }
    let Some(session_id) = event
        .raw
        .as_ref()
        .and_then(|raw| raw.payload.get("params"))
        .and_then(|params| params.get("sessionId"))
        .and_then(Value::as_str)
    else {
        return;
    };
    let Some(content) = event
        .payload
        .get_mut("data")
        .and_then(|data| data.get_mut("content"))
        .and_then(Value::as_array_mut)
    else {
        return;
    };
    let mut terminal_output = Vec::new();
    for entry in content {
        if entry.get("type").and_then(Value::as_str) != Some("terminal") {
            continue;
        }
        let id = entry
            .get("terminalId")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let text = state
            .terminals
            .get(id)
            .filter(|record| record.session_id == session_id)
            .map_or_else(|| format!("[terminal {id}]"), |record| record.buffer.text());
        terminal_output.push(text.clone());
        *entry = json!({"type":"content", "content":{"type":"text", "text":text}});
    }
    if !terminal_output.is_empty() {
        event.payload["itemType"] = serde_json::to_value(CanonicalItemType::CommandExecution)
            .expect("item type is serializable");
        event.payload["detail"] = Value::String(terminal_output.join("\n"));
    }
}

#[cfg(test)]
mod tests {
    use super::TerminalOutputBuffer;

    #[test]
    fn tail_truncation_preserves_utf8_boundary_and_lossy_binary_output() {
        let mut buffer = TerminalOutputBuffer::new(4);
        buffer.append("😀ab".as_bytes());
        assert_eq!(buffer.text(), "ab");
        assert!(buffer.truncated);
        buffer.append(&[0xff, b'z']);
        assert_eq!(buffer.text(), "ab�z");
        assert_eq!(buffer.len(), 4);
    }

    #[test]
    fn zero_budget_discards_output() {
        let mut buffer = TerminalOutputBuffer::new(0);
        buffer.append(b"abc");
        assert_eq!(buffer.text(), "");
        assert!(buffer.truncated);
    }
}
