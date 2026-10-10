use std::time::Duration;

use chrono::{TimeZone, Utc};
use serde_json::json;

use super::{classify, event_body, retry_delay, signed_headers, Outcome, MAX_ATTEMPTS};
use crate::events::{
    callback::CallbackError,
    secrets::{sign, signing_key},
};

#[test]
fn retries_back_off_from_five_seconds_to_fifteen_minutes() {
    let delays: Vec<u64> = (1..MAX_ATTEMPTS)
        .map(|attempt| retry_delay(attempt).as_secs())
        .collect();
    assert_eq!(
        delays,
        vec![5, 10, 20, 40, 80, 160, 320, 640, 900, 900, 900]
    );
    assert_eq!(retry_delay(0), Duration::from_secs(5));
    assert_eq!(retry_delay(i32::MAX), Duration::from_secs(900));
    let total: u64 = delays.iter().sum();
    assert!(total < 24 * 60 * 60, "every attempt fits inside retention");
}

#[test]
fn classifies_receiver_answers() {
    assert_eq!(classify(&Ok(200)), Outcome::Delivered(200));
    assert_eq!(classify(&Ok(204)), Outcome::Delivered(204));
    assert_eq!(classify(&Ok(410)), Outcome::Gone);
    assert_eq!(classify(&Ok(413)), Outcome::Dead("http_413".to_owned()));
    assert_eq!(classify(&Ok(400)), Outcome::Dead("http_400".to_owned()));
    assert_eq!(classify(&Ok(301)), Outcome::Dead("http_301".to_owned()));
    for transient in [408, 425, 429, 500, 502, 503] {
        assert_eq!(
            classify(&Ok(transient)),
            Outcome::Retry(format!("http_{transient}"))
        );
    }
    assert_eq!(
        classify(&Err(CallbackError::Timeout)),
        Outcome::Retry("timeout".to_owned())
    );
    assert_eq!(
        classify(&Err(CallbackError::DnsFailed)),
        Outcome::Retry("dns_failed".to_owned())
    );
    assert_eq!(
        classify(&Err(CallbackError::NonPublicDestination)),
        Outcome::Dead("non_public_destination".to_owned())
    );
}

#[test]
fn builds_the_mcp_events_body_with_envelope_fields() {
    let occurred = Utc
        .with_ymd_and_hms(2026, 10, 10, 12, 0, 0)
        .single()
        .unwrap_or_default();
    let body = event_body(
        "0190f1f2-7a1b-7c3d-8e4f-1234567890ab",
        "inbox.reply",
        occurred,
        ("runtime-1", Some("workspace-1"), None, 42),
        &json!({"threadId": "t1", "questionId": "q1", "workspaceId": "spoofed"}),
        "cursor-1",
    );
    assert_eq!(
        body,
        json!({
            "eventId": "0190f1f2-7a1b-7c3d-8e4f-1234567890ab",
            "name": "inbox.reply",
            "timestamp": "2026-10-10T12:00:00.000Z",
            "data": {
                "threadId": "t1",
                "questionId": "q1",
                "runtimeId": "runtime-1",
                "workspaceId": "workspace-1",
                "seq": 42,
            },
            "cursor": "cursor-1",
        })
    );
}

#[test]
fn signs_each_attempt_over_the_exact_body() {
    let secret = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
    let Some(key) = signing_key(secret) else {
        panic!("secret must decode");
    };
    let body = br#"{"eventId":"e1"}"#;
    let headers = signed_headers(
        "e1",
        ("x-mcp-subscription-id", "sub_1"),
        std::slice::from_ref(&key),
        body,
    );
    let value = |name: &str| {
        headers
            .iter()
            .find(|(header, _)| header == name)
            .map(|(_, value)| value.clone())
            .unwrap_or_default()
    };
    assert_eq!(value("webhook-id"), "e1");
    assert_eq!(value("x-mcp-subscription-id"), "sub_1");
    assert_eq!(value("content-type"), "application/json");
    let timestamp: i64 = value("webhook-timestamp").parse().unwrap_or_default();
    assert!((Utc::now().timestamp() - timestamp).abs() < 5);
    assert_eq!(
        value("webhook-signature"),
        sign(&key, "e1", timestamp, body)
    );
}
