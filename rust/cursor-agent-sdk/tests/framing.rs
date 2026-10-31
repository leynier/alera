use cursor_agent_sdk::{encode_connect_frame, ConnectFrameDecoder, CursorSdkError};
use serde_json::json;

#[test]
fn decoder_handles_fragmented_and_multiple_frames() {
    let first = encode_connect_frame(&json!({"sdkMessage":{"type":"assistant"}})).unwrap();
    let second = encode_connect_frame(&json!({"result":{"status":"finished"}})).unwrap();
    let mut bytes = first;
    bytes.extend(second);
    let mut decoder = ConnectFrameDecoder::default();
    let mut values = Vec::new();
    for chunk in bytes.chunks(3) {
        values.extend(decoder.push(chunk).unwrap());
    }
    assert_eq!(values.len(), 2);
    assert_eq!(values[0]["sdkMessage"]["type"], "assistant");
    assert_eq!(values[1]["result"]["status"], "finished");
    decoder.finish().unwrap();
}

#[test]
fn decoder_rejects_end_error_and_oversized_frame() {
    let mut end_error = vec![2, 0, 0, 0, 17];
    end_error.extend_from_slice(br#"{"error":"failed"}"#);
    let mut decoder = ConnectFrameDecoder::default();
    assert!(decoder.push(&end_error).is_err());

    let mut oversized = vec![0];
    oversized.extend_from_slice(&((16 * 1024 * 1024 + 1) as u32).to_be_bytes());
    let mut decoder = ConnectFrameDecoder::default();
    assert!(decoder.push(&oversized).is_err());
}

#[test]
fn decoder_keeps_the_connect_code_of_an_end_error() {
    let mut end_error = encode_connect_frame(&json!({
        "error": {"code": "resource_exhausted", "message": "Too many requests"}
    }))
    .unwrap();
    end_error[0] = 2;
    let error = ConnectFrameDecoder::default().push(&end_error).unwrap_err();
    let CursorSdkError::Rpc { code, message, .. } = &error else {
        panic!("expected a typed end error, got {error:?}");
    };
    assert_eq!(code, "resource_exhausted");
    assert_eq!(message, "Too many requests");
    assert!(error.is_usage_limit());
}
