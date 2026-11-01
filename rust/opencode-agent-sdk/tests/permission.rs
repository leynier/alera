use opencode_agent_sdk::{
    ClientConfig, Generation, HttpResponse, LegacyPermissionRule, MockHttpTransport,
    OpenCodeClient, SessionRequest,
};
use serde_json::{json, Value};

fn client(generation: Generation) -> OpenCodeClient<MockHttpTransport> {
    OpenCodeClient::new(
        MockHttpTransport::new(),
        ClientConfig {
            generation,
            ..ClientConfig::default()
        },
    )
}

fn respond(client: &OpenCodeClient<MockHttpTransport>, body: Value) {
    client
        .transport()
        .push_response(HttpResponse::new(200, serde_json::to_vec(&body).unwrap()));
}

fn sent(client: &OpenCodeClient<MockHttpTransport>, index: usize) -> (String, String, Value) {
    let request = &client.transport().captured_requests()[index];
    let body = if request.body.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&request.body).unwrap()
    };
    (request.method.clone(), request.path.clone(), body)
}

#[tokio::test]
async fn legacy_sessions_carry_permission_rules_on_create_and_update() {
    let mut client = client(Generation::Legacy1);
    let rules = vec![
        LegacyPermissionRule::new("*", "*", "deny"),
        LegacyPermissionRule::new("bash", "*", "ask"),
    ];
    respond(&client, json!({"id": "ses_1"}));
    respond(&client, json!({"id": "ses_1"}));
    client
        .create_session(SessionRequest {
            legacy_permission: Some(rules.clone()),
            ..SessionRequest::default()
        })
        .await
        .unwrap();
    client
        .update_session_legacy_permission("ses_1", &rules)
        .await
        .unwrap();
    let expected = json!([
        {"permission": "*", "pattern": "*", "action": "deny"},
        {"permission": "bash", "pattern": "*", "action": "ask"}
    ]);
    let (method, _, body) = sent(&client, 0);
    assert_eq!(method, "POST");
    assert_eq!(body["permission"], expected);
    assert!(body.get("permissions").is_none());
    let (method, path, body) = sent(&client, 1);
    assert_eq!(
        (method.as_str(), path.ends_with("/session/ses_1")),
        ("PATCH", true)
    );
    assert_eq!(body, json!({ "permission": expected }));
}

#[tokio::test]
async fn legacy_rules_are_read_from_a_session_record_and_refused_on_v2() {
    let record = json!({"id": "ses_1", "permission": [
        {"permission": "task", "pattern": "*", "action": "deny"},
        {"permission": 7}
    ]});
    assert_eq!(
        LegacyPermissionRule::from_session(&record),
        Some(vec![LegacyPermissionRule::new("task", "*", "deny")])
    );
    assert_eq!(
        LegacyPermissionRule::from_session(&json!({"id": "x"})),
        None
    );
    let mut v1 = client(Generation::Legacy1);
    respond(&v1, json!({"data": record.clone()}));
    assert_eq!(v1.session_record("ses_1").await.unwrap(), record);
    let mut v2 = client(Generation::V2);
    assert!(v2
        .update_session_legacy_permission("ses_1", &[])
        .await
        .is_err());
    assert!(v2.transport().captured_requests().is_empty());
}
