use crate::error::CursorSdkError;
use serde_json::Value;

pub const MAX_CONNECT_FRAME_BYTES: usize = 16 * 1024 * 1024;

/// Encode a Connect server-streaming request frame: flags byte, big-endian
/// length, and JSON payload.
pub fn encode_connect_frame(value: &Value) -> Result<Vec<u8>, CursorSdkError> {
    let payload = serde_json::to_vec(value)
        .map_err(|error| CursorSdkError::Protocol(format!("request JSON: {error}")))?;
    if payload.len() > MAX_CONNECT_FRAME_BYTES {
        return Err(CursorSdkError::Protocol(format!(
            "request frame exceeds {} bytes",
            MAX_CONNECT_FRAME_BYTES
        )));
    }
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.push(0);
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    frame.extend_from_slice(&payload);
    Ok(frame)
}

/// A Connect end-of-stream error keeps its code, so callers can classify it.
fn end_stream_error(error: &Value, frame: &Value) -> CursorSdkError {
    match error.get("code").and_then(Value::as_str) {
        Some(code) => CursorSdkError::Rpc {
            method: "run stream".into(),
            code: code.to_owned(),
            message: error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("bridge stream failed")
                .to_owned(),
            details: Box::new(error.clone()),
        },
        None => CursorSdkError::Protocol(format!("stream end error: {frame}")),
    }
}

#[derive(Debug, Default)]
pub struct ConnectFrameDecoder {
    buffer: Vec<u8>,
}

impl ConnectFrameDecoder {
    pub fn push(&mut self, bytes: &[u8]) -> Result<Vec<Value>, CursorSdkError> {
        self.buffer.extend_from_slice(bytes);
        let mut values = Vec::new();
        loop {
            if self.buffer.len() < 5 {
                if self.buffer.len() > MAX_CONNECT_FRAME_BYTES.saturating_add(5) {
                    return Err(CursorSdkError::Protocol(
                        "stream frame buffer exceeded limit".into(),
                    ));
                }
                break;
            }
            let flags = self.buffer[0];
            if flags & !0x03 != 0 {
                return Err(CursorSdkError::Protocol(format!(
                    "unsupported Connect frame flags: {flags:#04x}"
                )));
            }
            let length = u32::from_be_bytes([
                self.buffer[1],
                self.buffer[2],
                self.buffer[3],
                self.buffer[4],
            ]) as usize;
            if length > MAX_CONNECT_FRAME_BYTES {
                return Err(CursorSdkError::Protocol(format!(
                    "stream frame exceeds {} bytes",
                    MAX_CONNECT_FRAME_BYTES
                )));
            }
            let total = 5usize.saturating_add(length);
            if self.buffer.len() < total {
                break;
            }
            let payload = self.buffer[5..total].to_vec();
            self.buffer.drain(..total);
            let value = serde_json::from_slice::<Value>(&payload)
                .map_err(|error| CursorSdkError::Protocol(format!("stream JSON: {error}")))?;
            if flags & 0x02 != 0 {
                if let Some(error) = value.get("error") {
                    return Err(end_stream_error(error, &value));
                }
                continue;
            }
            if flags & 0x01 != 0 {
                return Err(CursorSdkError::Protocol(
                    "compressed Connect frame unsupported".into(),
                ));
            }
            values.push(value);
        }
        Ok(values)
    }

    pub fn finish(&self) -> Result<(), CursorSdkError> {
        if self.buffer.is_empty() {
            Ok(())
        } else {
            Err(CursorSdkError::Protocol(
                "truncated Connect stream frame".into(),
            ))
        }
    }
}
