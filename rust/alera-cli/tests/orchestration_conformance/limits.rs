use super::*;

#[test]
fn lifecycle_to_group_and_unknown_recipients_are_rejected() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let group_lifecycle = request(
        &mut writer,
        &mut reader,
        70,
        "orchestration.send",
        json!({"from": "a", "to": "@all", "subject": "x", "type": "worker_done"}),
    );
    assert_eq!(group_lifecycle["ok"], json!(false));

    let no_recipients = request(
        &mut writer,
        &mut reader,
        71,
        "orchestration.send",
        json!({"from": "a", "to": "@all", "subject": "x"}),
    );
    assert_eq!(no_recipients["ok"], json!(false));
}

#[test]
fn unsafe_orchestration_messages_are_rejected_before_persistence() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let self_lifecycle = request(
        &mut writer,
        &mut reader,
        80,
        "orchestration.send",
        json!({"from": "worker", "to": "worker", "subject": "done", "type": "worker_done"}),
    );
    assert_eq!(self_lifecycle["ok"], json!(false));
    assert!(self_lifecycle["error"]
        .as_str()
        .is_some_and(|error| error.contains("lifecycle operation")));

    let oversized = request(
        &mut writer,
        &mut reader,
        81,
        "orchestration.send",
        json!({"from": "a", "to": "b", "subject": "large", "body": "x".repeat(64 * 1024 + 1)}),
    );
    assert_eq!(oversized["ok"], json!(false));
    assert!(oversized["error"]
        .as_str()
        .is_some_and(|error| error.contains("message_too_large")));

    let oversized_payload = request(
        &mut writer,
        &mut reader,
        83,
        "orchestration.send",
        json!({"from": "a", "to": "b", "subject": "large payload", "payload": "x".repeat(64 * 1024 + 1)}),
    );
    assert_eq!(oversized_payload["ok"], json!(false));
    assert!(oversized_payload["error"]
        .as_str()
        .is_some_and(|error| error.contains("payload")));

    let original = expect_ok(request(
        &mut writer,
        &mut reader,
        84,
        "orchestration.send",
        json!({"from": "a", "to": "b", "subject": "reply root"}),
    ));
    let original_id = original["messages"][0]["id"].as_str().unwrap();
    let oversized_reply = request(
        &mut writer,
        &mut reader,
        85,
        "orchestration.reply",
        json!({"id": original_id, "body": "x".repeat(64 * 1024 + 1)}),
    );
    assert_eq!(oversized_reply["ok"], json!(false));
    assert!(oversized_reply["error"]
        .as_str()
        .is_some_and(|error| error.contains("body")));

    let oversized_ask = request(
        &mut writer,
        &mut reader,
        86,
        "orchestration.ask",
        json!({"from": "a", "to": "b", "question": "x".repeat(64 * 1024 + 1)}),
    );
    assert_eq!(oversized_ask["ok"], json!(false));
    assert!(oversized_ask["error"]
        .as_str()
        .is_some_and(|error| error.contains("message_too_large")));

    let injected_self_dispatch = request(
        &mut writer,
        &mut reader,
        82,
        "orchestration.dispatch",
        json!({"task": "missing", "from": "same", "to": "same", "inject": true}),
    );
    assert_eq!(injected_self_dispatch["ok"], json!(false));
    assert!(injected_self_dispatch["error"]
        .as_str()
        .is_some_and(|error| error.contains("self_dispatch_requires_opt_in")));
}
