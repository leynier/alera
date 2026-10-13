use crate::rpc::{self, AcpRequestId, RpcError};
use crate::AcpError;
use serde_json::Value;
use std::io::{self, Write};

pub(crate) fn bounded_response(
    id: &AcpRequestId,
    result: Result<Value, RpcError>,
    limit: usize,
) -> Result<Value, AcpError> {
    let is_error = result.is_err();
    let mut frame = rpc::response(id, result);
    let full_bytes = frame_bytes(&frame)?;
    if full_bytes <= limit {
        return Ok(frame);
    }
    if !is_error {
        return Err(AcpError::Protocol(format!(
            "ACP response exceeds the configured {limit}-byte frame budget ({full_bytes} bytes)"
        )));
    }

    let error = frame["error"].as_object_mut().expect("RPC error object");
    error.remove("data");
    if frame_bytes(&frame)? <= limit {
        return Ok(frame);
    }
    let error = frame["error"].as_object_mut().expect("RPC error object");
    let message = error
        .insert("message".into(), Value::String(String::new()))
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .expect("RPC error message");
    let minimum = frame_bytes(&frame)?;
    let available = limit.checked_sub(minimum).ok_or_else(|| {
        AcpError::Protocol(format!(
            "ACP response frame budget {limit} bytes cannot preserve the request id and error code (minimum {minimum} bytes)"
        ))
    })?;
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
    frame["error"]["message"] = Value::String(message[..end].into());
    Ok(frame)
}

fn escaped_character_bytes(character: char) -> usize {
    match character {
        '"' | '\\' | '\n' | '\r' | '\t' | '\u{08}' | '\u{0c}' => 2,
        '\u{00}'..='\u{1f}' => 6,
        character => character.len_utf8(),
    }
}

fn frame_bytes(frame: &Value) -> Result<usize, serde_json::Error> {
    let mut counter = FrameByteCounter(0);
    serde_json::to_writer(&mut counter, frame)?;
    Ok(counter.0)
}

struct FrameByteCounter(usize);

impl Write for FrameByteCounter {
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
    use super::bounded_response;
    use crate::{AcpRequestId, RpcError};
    use serde_json::{json, Value};

    fn error(message: &str, data: Option<Value>) -> Result<Value, RpcError> {
        Err(RpcError {
            code: -32601,
            message: message.into(),
            data,
        })
    }

    #[test]
    fn data_and_message_are_preserved_without_budget_pressure() {
        let id = AcpRequestId::Number(9);
        let result = error("Method not found", Some(json!({"reason":"future"})));
        let frame = bounded_response(&id, result.clone(), 512).unwrap();
        assert_eq!(frame, crate::rpc::response(&id, result));
    }

    #[test]
    fn exact_long_id_and_code_fit_without_optional_data_or_message_text() {
        let id = AcpRequestId::String("x".repeat(450));
        let frame = bounded_response(&id, error("Method not found", None), 512).unwrap();
        assert_eq!(frame["id"], id.as_value());
        assert_eq!(frame["error"]["code"], -32601);
        assert_eq!(frame["error"]["message"], "");
        assert!(frame["error"].get("data").is_none());
        assert_eq!(serde_json::to_vec(&frame).unwrap().len(), 512);
    }

    #[test]
    fn trim_counts_json_escapes_and_preserves_utf8_boundaries() {
        let id = AcpRequestId::String("typed\n\"id😀".into());
        let message = "😀\0\"\\\n".repeat(100);
        let frame = bounded_response(
            &id,
            error(&message, Some(json!({"large":"x".repeat(512)}))),
            128,
        )
        .unwrap();
        assert_eq!(frame["id"], id.as_value());
        assert_eq!(frame["error"]["code"], -32601);
        assert!(message.starts_with(frame["error"]["message"].as_str().unwrap()));
        assert!(serde_json::to_vec(&frame).unwrap().len() <= 128);
    }

    #[test]
    fn impossible_envelope_and_oversized_success_fail_explicitly() {
        let id = AcpRequestId::String("x".repeat(451));
        let failure = bounded_response(&id, error("Method not found", None), 512).unwrap_err();
        assert!(
            matches!(failure, crate::AcpError::Protocol(message) if message.contains("minimum 513 bytes"))
        );
        assert!(bounded_response(
            &AcpRequestId::Null,
            Ok(json!({"value":"x".repeat(512)})),
            128
        )
        .is_err());
    }
}
