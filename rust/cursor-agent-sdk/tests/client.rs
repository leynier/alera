use cursor_agent_sdk::{
    encode_connect_frame, CursorClient, CursorClientConfig, MockBridgeTransport, ReadyHandshake,
    SendOptions, UserMessage,
};
use serde_json::json;

#[tokio::test]
async fn client_correlates_unary_and_server_stream_calls() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message":"pong"})));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "sdkMessage": {"type":"assistant", "message":{"runId":"run-1"}}
        }))
        .unwrap(),
        encode_connect_frame(&json!({"result":{"status":"finished"}})).unwrap(),
        encode_connect_frame(&json!({"done":{}})).unwrap(),
    ]);
    let client = CursorClient::with_transport(mock.clone(), "token").unwrap();
    assert_eq!(client.ping().await.unwrap()["message"], "pong");
    let mut stream = client
        .send(
            "agent-1",
            UserMessage {
                text: "hello".into(),
                images: vec![],
            },
            SendOptions::default(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        stream.next().await.unwrap().unwrap().sdk_message.unwrap()["type"],
        "assistant"
    );
    assert_eq!(
        stream.next().await.unwrap().unwrap().result.unwrap()["status"],
        "finished"
    );
    assert!(stream.next().await.unwrap().unwrap().done.is_some());
    assert!(stream.next().await.unwrap().is_none());
    let calls = mock.calls();
    assert_eq!(calls[0].0, "sdk.v1.SdkBridgeControlService/Ping");
    assert_eq!(calls[1].0, "sdk.v1.SdkAgentService/Send");
    assert_eq!(calls[1].1["agentId"], "agent-1");
}

#[test]
fn ready_handshake_rejects_wrong_protocol_and_keeps_token_out_of_debug() {
    let result = ReadyHandshake::parse_line(
        r#"cursor-sdk-bridge ready {"schemaVersion":1,"serverVersion":"1","transport":"tcp","protocol":"grpc","host":"127.0.0.1","port":1,"authToken":"secret"}"#,
    )
    .unwrap()
    .unwrap_err();
    assert!(result.to_string().contains("tcp/connect"));
    let ready = ReadyHandshake::parse_line(
        r#"cursor-sdk-bridge ready {"schemaVersion":1,"serverVersion":"1","transport":"tcp","protocol":"connect","host":"127.0.0.1","port":1,"authToken":"secret"}"#,
    )
    .unwrap()
    .unwrap();
    assert!(!format!("{ready:?}").contains("secret"));
}

#[test]
fn remote_endpoint_requires_explicit_opt_in() {
    let error = match CursorClient::connect(CursorClientConfig::new(
        "https://bridge.example.test",
        "token",
    )) {
        Ok(_) => panic!("remote endpoint should require opt-in"),
        Err(error) => error,
    };
    assert!(error.to_string().contains("non-loopback"));
    CursorClient::connect(
        CursorClientConfig::new("https://bridge.example.test", "token").allow_remote_endpoint(true),
    )
    .unwrap();
}
