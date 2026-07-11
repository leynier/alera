use super::*;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::thread;

#[test]
fn parses_json_hook_event() {
    let event = parse_hook_event(
        "codex",
        "application/json",
        br#"{"terminalSessionId":"s","workspaceId":"w","tabId":"t","hookEventName":"UserPromptSubmit","version":"1","payload":{"prompt":"ship"}}"#,
    )
    .expect("event");

    assert_eq!(event.agent_type, "codex");
    assert_eq!(event.hook_event_name.as_deref(), Some("UserPromptSubmit"));
    assert_eq!(event.version.as_deref(), Some("1"));
    assert!(event.payload_json.contains("ship"));
}

#[test]
fn parses_form_hook_event_with_payload_string() {
    let event = parse_hook_event(
        "claude",
        "application/x-www-form-urlencoded",
        b"terminalSessionId=s&workspaceId=w&tabId=t&hook_event_name=PreToolUse&payload=%7B%22tool_name%22%3A%22Bash%22%7D",
    )
    .expect("event");

    assert_eq!(event.hook_event_name.as_deref(), Some("PreToolUse"));
    assert!(event.payload_json.contains("Bash"));
}

#[test]
fn rejects_missing_metadata() {
    assert!(parse_hook_event(
        "codex",
        "application/json",
        br#"{"workspaceId":"w","tabId":"t","payload":{}}"#
    )
    .is_none());
}

#[test]
fn coalesces_intermediate_non_close_events() {
    let mut events = vec![
        event("s1", "cursor", "beforeSubmitPrompt"),
        event("s1", "cursor", "afterAgentResponse"),
        event("s2", "pi", "session_shutdown"),
        event("s1", "cursor", "sessionEnd"),
        event("s3", "grok", "Stop"),
        event("s3", "grok", "StopFailure"),
        event("s3", "grok", "SessionEnd"),
    ];

    let coalesced = coalesce_pending(&mut events);

    assert_eq!(coalesced, 1);
    assert_eq!(events.len(), 6);
    assert_eq!(
        events
            .iter()
            .filter(|event| event.inferred_event_name.as_deref() == Some("sessionEnd"))
            .count(),
        1
    );
}

#[test]
fn serves_http_hook_routes() {
    let endpoint = start_agent_hook_receiver(
        "test-token".to_string(),
        vec!["codex".to_string(), "grok".to_string()],
    )
    .expect("server starts");

    let forbidden = post_raw(endpoint.port, "/hook/codex", "wrong", "{}");
    assert!(forbidden.starts_with("HTTP/1.1 403"));

    let not_found = post_raw(endpoint.port, "/hook/unknown", "test-token", "{}");
    assert!(not_found.starts_with("HTTP/1.1 404"));

    let accepted = post_raw(
        endpoint.port,
        "/hook/codex",
        "test-token",
        r#"{"terminalSessionId":"s","workspaceId":"w","tabId":"t","payload":{}}"#,
    );
    assert!(accepted.starts_with("HTTP/1.1 204"));

    let grok = post_raw(
        endpoint.port,
        "/hook/grok",
        "test-token",
        r#"{"terminalSessionId":"s","workspaceId":"w","tabId":"t","hookEventName":"Stop","payload":{}}"#,
    );
    assert!(grok.starts_with("HTTP/1.1 204"));

    stop_agent_hook_receiver();
}

fn event(session: &str, agent: &str, name: &str) -> AgentHookEventDto {
    AgentHookEventDto {
        terminal_session_id: session.to_string(),
        workspace_id: "w".to_string(),
        tab_id: "t".to_string(),
        agent_type: agent.to_string(),
        payload_json: "{}".to_string(),
        hook_event_name: Some(name.to_string()),
        version: None,
        inferred_event_name: Some(name.to_string()),
    }
}

fn post_raw(port: u16, path: &str, token: &str, body: &str) -> String {
    let mut stream = connect_with_retry(port);
    write!(
        stream,
        "POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n{AGENT_HOOK_TOKEN_HEADER}: {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
    .expect("write request");
    let mut response = String::new();
    stream.read_to_string(&mut response).expect("read response");
    response
}

fn connect_with_retry(port: u16) -> TcpStream {
    let addr = (Ipv4Addr::LOCALHOST, port);
    for _ in 0..50 {
        if let Ok(stream) = TcpStream::connect(addr) {
            return stream;
        }
        thread::sleep(Duration::from_millis(10));
    }
    TcpStream::connect(addr).expect("connect to hook server")
}
