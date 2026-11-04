use crate::client_terminals::request_error;
use alera_provider_acp::agent_client_protocol::{AcpRequestId, RpcError};
use serde_json::{json, Value};
use std::io::{self, Write};

pub(crate) fn wire_output(
    id: &AcpRequestId,
    text: String,
    truncated: bool,
    exit_status: Option<Value>,
    max_frame_bytes: usize,
) -> Result<Value, RpcError> {
    let mut output = json!({"output":"", "truncated":truncated});
    if let Some(status) = exit_status {
        output["exitStatus"] = status;
    }
    let full_bytes =
        response_frame_bytes(id, &Ok(output.clone())).saturating_add(escaped_text_bytes(&text));
    if full_bytes <= max_frame_bytes {
        output["output"] = Value::String(text);
        return Ok(output);
    }
    output["truncated"] = Value::Bool(true);
    let base_bytes = response_frame_bytes(id, &Ok(output.clone()));
    let available = max_frame_bytes.checked_sub(base_bytes).ok_or_else(|| {
        request_error(
            -32003,
            "frame budget too small for terminal output metadata",
        )
    })?;
    let mut encoded = 0;
    let mut start = text.len();
    for (index, character) in text.char_indices().rev() {
        let cost = escaped_character_bytes(character);
        if cost > available.saturating_sub(encoded) {
            break;
        }
        encoded += cost;
        start = index;
    }
    if start == 0 {
        start = text.chars().next().map(char::len_utf8).ok_or_else(|| {
            request_error(
                -32003,
                "frame budget too small for terminal output metadata",
            )
        })?;
    }
    output["output"] = Value::String(text[start..].to_owned());
    Ok(output)
}

pub(crate) fn bound_response(
    id: &AcpRequestId,
    result: Result<Value, RpcError>,
    max_frame_bytes: usize,
) -> Result<Value, RpcError> {
    if response_frame_bytes(id, &result) <= max_frame_bytes {
        return result;
    }
    let (code, message) = match result {
        Err(error) => (error.code, error.message),
        Ok(_) => (
            -32003,
            "terminal response exceeds the response frame budget".into(),
        ),
    };
    let mut error = request_error(code, "");
    let available = max_frame_bytes.saturating_sub(response_frame_bytes(id, &Err(error.clone())));
    let mut encoded = 0;
    let mut end = 0;
    for (index, character) in message.char_indices() {
        let cost = escaped_character_bytes(character);
        if cost > available.saturating_sub(encoded) {
            break;
        }
        encoded += cost;
        end = index + character.len_utf8();
    }
    error.message = message[..end].to_owned();
    Err(error)
}

fn escaped_text_bytes(text: &str) -> usize {
    text.chars().map(escaped_character_bytes).sum()
}

fn escaped_character_bytes(character: char) -> usize {
    match character {
        '"' | '\\' | '\n' | '\r' | '\t' | '\u{08}' | '\u{0c}' => 2,
        '\u{00}'..='\u{1f}' => 6,
        character => character.len_utf8(),
    }
}

fn response_frame_bytes(id: &AcpRequestId, result: &Result<Value, RpcError>) -> usize {
    let mut counter = ByteCounter(0);
    serde_json::to_writer(&mut counter, &response_frame(id, result))
        .expect("JSON-RPC terminal response is serializable");
    counter.0
}

pub(crate) fn response_frame(id: &AcpRequestId, result: &Result<Value, RpcError>) -> Value {
    match result {
        Ok(value) => json!({"jsonrpc":"2.0", "id":id.as_value(), "result":value}),
        Err(error) => {
            json!({"jsonrpc":"2.0", "id":id.as_value(), "error":{"code":error.code, "message":error.message, "data":error.data}})
        }
    }
}

struct ByteCounter(usize);

impl Write for ByteCounter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0 = self.0.saturating_add(bytes.len());
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{bound_response, response_frame, wire_output};
    use alera_provider_acp::agent_client_protocol::AcpRequestId;
    use serde_json::json;

    #[test]
    fn wire_tail_budget_includes_escaped_id_metadata_and_utf8() {
        let id = AcpRequestId::String("typed\n\"id".into());
        let text = format!("{}😀tail", "\0\"\\\n".repeat(200));
        let output = wire_output(
            &id,
            text,
            false,
            Some(json!({"exitCode":7, "signal":null})),
            256,
        )
        .unwrap();
        assert_eq!(output["truncated"], true);
        assert!(output["output"].as_str().unwrap().ends_with("😀tail"));
        assert!(
            serde_json::to_vec(&response_frame(&id, &Ok(output)))
                .unwrap()
                .len()
                <= 256
        );
    }

    #[test]
    fn oversized_metadata_yields_bounded_explicit_error() {
        let id = AcpRequestId::String("x".repeat(64));
        let result = wire_output(
            &id,
            "output".into(),
            false,
            Some(json!({"exitCode":7, "signal":null})),
            160,
        );
        assert!(result.is_err());
        let response = bound_response(&id, result, 160);
        assert!(response.as_ref().unwrap_err().message.contains("budget"));
        assert!(
            serde_json::to_vec(&response_frame(&id, &response))
                .unwrap()
                .len()
                <= 160
        );
    }
}
