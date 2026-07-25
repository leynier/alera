//! Messaging conformance: send/check/reply round trips and long-poll waits.
//! Split out of the parent suite to keep each file focused.

use super::*;

#[test]
fn send_check_reply_roundtrip() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);

    let sent = expect_ok(request(
        &mut writer,
        &mut reader,
        1,
        "orchestration.send",
        json!({"from": "a", "to": "b", "subject": "hi", "body": "hello there"}),
    ));
    assert_eq!(sent["recipients"], json!(["b"]));
    let message_id = sent["messages"][0]["id"].as_str().unwrap().to_string();

    // First check consumes the unread message.
    let checked = expect_ok(request(
        &mut writer,
        &mut reader,
        2,
        "orchestration.check",
        json!({"terminal": "b", "inject": true}),
    ));
    assert_eq!(checked["messages"][0]["id"], json!(message_id));
    let formatted = checked["formatted"].as_str().unwrap();
    assert!(formatted.contains("--- Orchestration Messages (1) ---"));
    assert!(formatted.contains("alera orchestration reply --id"));

    // Second check is empty (read/delivered independence handled in unit tests).
    let empty = expect_ok(request(
        &mut writer,
        &mut reader,
        3,
        "orchestration.check",
        json!({"terminal": "b"}),
    ));
    assert_eq!(empty["messages"], json!([]));

    // Reply flows back to the original sender with the thread inherited.
    let reply = expect_ok(request(
        &mut writer,
        &mut reader,
        4,
        "orchestration.reply",
        json!({"id": message_id, "body": "ack"}),
    ));
    assert_eq!(reply["to_handle"], json!("a"));
    assert_eq!(reply["thread_id"], json!(message_id));
    let back = expect_ok(request(
        &mut writer,
        &mut reader,
        5,
        "orchestration.check",
        json!({"terminal": "a"}),
    ));
    assert_eq!(back["messages"][0]["subject"], json!("Re: hi"));
}

#[test]
fn check_wait_wakes_on_matching_type_only() {
    let host = start_host();
    let (mut coordinator_writer, mut coordinator_reader) = connect(host.port);
    handshake(
        &mut coordinator_writer,
        &mut coordinator_reader,
        &host.token,
    );
    let (mut sender_writer, mut sender_reader) = connect(host.port);
    handshake(&mut sender_writer, &mut sender_reader, &host.token);

    // Park a waiter filtered to escalation.
    send(
        &mut coordinator_writer,
        json!({"id": 10, "type": "orchestration.check", "payload": {
            "terminal": "coord", "wait": true, "types": ["escalation"], "timeoutMs": 10_000
        }}),
    );
    std::thread::sleep(Duration::from_millis(300));

    // A status message must NOT wake the escalation waiter.
    expect_ok(request(
        &mut sender_writer,
        &mut sender_reader,
        11,
        "orchestration.send",
        json!({"from": "w", "to": "coord", "subject": "noise", "type": "status"}),
    ));
    std::thread::sleep(Duration::from_millis(300));

    // The escalation wakes it.
    expect_ok(request(
        &mut sender_writer,
        &mut sender_reader,
        12,
        "orchestration.send",
        json!({"from": "w", "to": "coord", "subject": "blocked", "type": "escalation"}),
    ));
    let woken = read_response(&mut coordinator_reader, 10);
    assert_eq!(woken["ok"], json!(true));
    let messages = woken["payload"]["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["type"], json!("escalation"));
}

#[test]
fn check_wait_times_out_cleanly() {
    let host = start_host();
    let (mut writer, mut reader) = connect(host.port);
    handshake(&mut writer, &mut reader, &host.token);
    let timed_out = expect_ok(request(
        &mut writer,
        &mut reader,
        20,
        "orchestration.check",
        json!({"terminal": "nobody", "wait": true, "timeoutMs": 700}),
    ));
    assert_eq!(timed_out["timedOut"], json!(true));
    assert_eq!(timed_out["messages"], json!([]));
}
