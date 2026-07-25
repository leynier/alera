//! Length-prefixed framing for the local terminal-host socket.
//!
//! The default wire format is newline-delimited JSON with PTY output base64'd
//! inside it. That costs the app a UTF-8 decode of the whole socket, a line
//! split, a JSON parse and a base64 decode before the emulator sees a byte,
//! and inflates the traffic by a third.
//!
//! A client that negotiates the binary-frames capability switches the whole
//! connection to uniform frames instead. Uniform, not hybrid: one parser is far
//! easier to get right than a reader that has to tell JSON lines apart from
//! interleaved binary.
//!
//! ```text
//! [u8 kind][u32be length][payload]
//!
//! kind 1 = JSON     payload = the same object that would have been a line
//! kind 2 = output   payload = [u16be len][sessionId utf8][raw pty bytes]
//! ```

use serde_json::Value;

pub const FRAME_KIND_JSON: u8 = 1;
pub const FRAME_KIND_OUTPUT: u8 = 2;

/// Header size: the kind byte plus the u32 length.
pub const FRAME_HEADER_LEN: usize = 5;

pub fn encode_json_frame(value: &Value) -> std::io::Result<Vec<u8>> {
    let payload = serde_json::to_vec(value).map_err(std::io::Error::other)?;
    Ok(frame(FRAME_KIND_JSON, &payload))
}

/// Encodes PTY output without base64, which is the whole point of the format.
pub fn encode_output_frame(session_id: &str, data: &[u8]) -> Vec<u8> {
    let id = session_id.as_bytes();
    let mut payload = Vec::with_capacity(2 + id.len() + data.len());
    payload.extend_from_slice(&(id.len() as u16).to_be_bytes());
    payload.extend_from_slice(id);
    payload.extend_from_slice(data);
    frame(FRAME_KIND_OUTPUT, &payload)
}

fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(FRAME_HEADER_LEN + payload.len());
    out.push(kind);
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(payload);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn split_header(bytes: &[u8]) -> (u8, usize, &[u8]) {
        let kind = bytes[0];
        let len = u32::from_be_bytes([bytes[1], bytes[2], bytes[3], bytes[4]]) as usize;
        (kind, len, &bytes[FRAME_HEADER_LEN..])
    }

    #[test]
    fn json_frame_round_trips() {
        let value = json!({ "event": "exit", "payload": { "exitCode": 0 } });
        let bytes = encode_json_frame(&value).unwrap();
        let (kind, len, payload) = split_header(&bytes);

        assert_eq!(kind, FRAME_KIND_JSON);
        assert_eq!(len, payload.len());
        assert_eq!(
            serde_json::from_slice::<Value>(payload).unwrap(),
            value,
            "a JSON frame must carry exactly the object a line would have"
        );
    }

    #[test]
    fn output_frame_carries_raw_bytes() {
        let data = vec![0x1b, b'[', b'0', b'm', 0xff, 0x00];
        let bytes = encode_output_frame("session-1", &data);
        let (kind, len, payload) = split_header(&bytes);

        assert_eq!(kind, FRAME_KIND_OUTPUT);
        assert_eq!(len, payload.len());
        let id_len = u16::from_be_bytes([payload[0], payload[1]]) as usize;
        assert_eq!(&payload[2..2 + id_len], b"session-1");
        // Not base64: the raw bytes, including ones that are not valid UTF-8.
        assert_eq!(&payload[2 + id_len..], data.as_slice());
    }

    #[test]
    fn empty_payloads_are_representable() {
        let bytes = encode_output_frame("", &[]);
        let (kind, len, payload) = split_header(&bytes);

        assert_eq!(kind, FRAME_KIND_OUTPUT);
        assert_eq!(len, 2, "just the empty session id length");
        assert_eq!(payload, &[0, 0]);
    }

    #[test]
    fn a_unicode_session_id_is_measured_in_bytes_not_chars() {
        // The length prefix is a byte count, so a multi-byte id must not be
        // truncated by a reader that trusts it.
        let bytes = encode_output_frame("sesión", b"x");
        let (_, _, payload) = split_header(&bytes);
        let id_len = u16::from_be_bytes([payload[0], payload[1]]) as usize;

        assert_eq!(id_len, "sesión".len());
        assert_eq!(
            std::str::from_utf8(&payload[2..2 + id_len]).unwrap(),
            "sesión"
        );
    }
}
