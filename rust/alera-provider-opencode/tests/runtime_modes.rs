//! Runtime modes become session permission rules, as T3 Code writes them.

use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{EventKind, Provider, RuntimeMode, SessionStartInput};
use serde_json::{json, Value};

fn ok(body: Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&body).unwrap())
}

/// A provider whose transport answers `responses` in order. The session
/// start lists commands after its session request; that listing fails.
fn provider(
    generation: OpenCodeGeneration,
    responses: Vec<HttpResponse>,
    stream: &[u8],
) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    for response in responses {
        transport.push_response(response);
    }
    transport.push_stream([stream.to_vec()]);
    OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    )
}

fn requests(provider: &OpenCodeProvider<MockHttpTransport>) -> Vec<(String, String, Value)> {
    provider
        .client()
        .transport()
        .captured_requests()
        .into_iter()
        .map(|request| {
            let body = serde_json::from_slice(&request.body).unwrap_or(Value::Null);
            (request.method, request.path, body)
        })
        .collect()
}

async fn start(
    provider: &mut OpenCodeProvider<MockHttpTransport>,
    mode: RuntimeMode,
    resume: Option<&str>,
) {
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = mode;
    input.resume_thread_id = resume.map(str::to_owned);
    provider.start_session(input).await.unwrap();
}

fn rule(action: &str, effect: &str) -> Value {
    json!({"action": action, "resource": "*", "effect": effect})
}

#[tokio::test]
async fn v2_sessions_are_created_with_the_mode_rules() {
    for (mode, expected) in [
        (
            RuntimeMode::ApprovalRequired,
            json!([
                rule("shell", "ask"),
                rule("edit", "ask"),
                rule("external_directory", "ask")
            ]),
        ),
        (
            RuntimeMode::AutoAcceptEdits,
            json!([
                rule("shell", "ask"),
                rule("edit", "allow"),
                rule("external_directory", "ask")
            ]),
        ),
        (RuntimeMode::FullAccess, json!([rule("*", "allow")])),
    ] {
        let responses = vec![
            ok(json!({"id": "session-1"})),
            HttpResponse::new(404, vec![]),
        ];
        let mut provider = provider(OpenCodeGeneration::V2, responses, b"");
        start(&mut provider, mode, None).await;
        let (method, _, body) = &requests(&provider)[0];
        assert_eq!(method, "POST");
        assert_eq!(body["permissions"], expected, "{mode:?}");
        assert!(body.get("permission").is_none());
    }
}

#[tokio::test]
async fn legacy_sessions_are_created_with_the_mode_rules() {
    let responses = vec![
        ok(json!({"id": "session-1"})),
        HttpResponse::new(404, vec![]),
    ];
    let mut full = provider(OpenCodeGeneration::Legacy1, responses, b"");
    start(&mut full, RuntimeMode::FullAccess, None).await;
    let body = &requests(&full)[0].2;
    assert_eq!(
        body["permission"],
        json!([{"permission": "*", "pattern": "*", "action": "allow"}])
    );
    assert!(body.get("permissions").is_none());

    let responses = vec![
        ok(json!({"id": "session-1"})),
        HttpResponse::new(404, vec![]),
    ];
    let mut edits = provider(OpenCodeGeneration::Legacy1, responses, b"");
    start(&mut edits, RuntimeMode::AutoAcceptEdits, None).await;
    let rules = requests(&edits)[0].2["permission"]
        .as_array()
        .unwrap()
        .clone();
    // Denials first, so a sub-agent inherits them until its own rules land.
    assert_eq!(
        rules[0],
        json!({"permission": "*", "pattern": "*", "action": "deny"})
    );
    assert!(rules.contains(&json!({"permission": "bash", "pattern": "*", "action": "ask"})));
    assert!(rules.contains(&json!({"permission": "read", "pattern": "*.env", "action": "ask"})));
    assert_eq!(
        rules.last().unwrap(),
        &json!({"permission": "edit", "pattern": "*", "action": "allow"})
    );
}

#[tokio::test]
async fn resumed_sessions_get_the_mode_rules_again() {
    for generation in [OpenCodeGeneration::V2, OpenCodeGeneration::Legacy1] {
        let responses = vec![
            ok(json!({"id": "session-1"})),
            ok(json!({"id": "session-1"})),
            HttpResponse::new(404, vec![]),
        ];
        let mut provider = provider(generation, responses, b"");
        start(&mut provider, RuntimeMode::FullAccess, Some("session-1")).await;
        let (method, path, body) = &requests(&provider)[1];
        assert_eq!(method, "PATCH");
        assert!(path.ends_with("/session/session-1"), "{path}");
        let expected = match generation {
            OpenCodeGeneration::V2 => json!({"permissions": [rule("*", "allow")]}),
            OpenCodeGeneration::Legacy1 => {
                json!({"permission": [{"permission": "*", "pattern": "*", "action": "allow"}]})
            }
        };
        assert_eq!(body, &expected, "{generation:?}");
    }
}

fn created(id: &str, parent: &str, permission: Option<Value>) -> String {
    let mut info = json!({"id": id, "parentID": parent});
    if let Some(permission) = permission {
        info["permission"] = permission;
    }
    let event = json!({"type": "session.created", "properties": {"info": info}});
    format!("data: {event}\n\n")
}

#[tokio::test]
async fn legacy_sub_agent_sessions_get_the_parent_mode_with_their_own_restrictions() {
    let own = json!({"permission": "task", "pattern": "*", "action": "deny"});
    let stream = [
        created("child-1", "session-1", Some(json!([own]))),
        // A grandchild without rules in its event is read first.
        created("grandchild-1", "child-1", None),
        // Another chat's session is left alone.
        created("other-1", "other-root", Some(json!([]))),
    ]
    .concat();
    let responses = vec![
        ok(json!({"id": "session-1"})),
        HttpResponse::new(404, vec![]),
        ok(json!({"id": "child-1"})),
        ok(json!({"id": "grandchild-1", "permission": []})),
        ok(json!({"id": "grandchild-1"})),
    ];
    let mut provider = provider(OpenCodeGeneration::Legacy1, responses, stream.as_bytes());
    start(&mut provider, RuntimeMode::FullAccess, None).await;
    let mut kinds = Vec::new();
    while let Ok(Some(event)) = provider.next_event().await {
        kinds.push(event.kind);
    }
    assert!(!kinds.contains(&EventKind::RuntimeWarning), "{kinds:?}");
    // After the session, command listing and event stream requests.
    let sent = requests(&provider)[3..].to_vec();
    let full_access = json!({"permission": "*", "pattern": "*", "action": "allow"});
    assert_eq!(sent[0].0, "PATCH");
    assert!(sent[0].1.ends_with("/session/child-1"));
    assert_eq!(sent[0].2, json!({"permission": [full_access, own]}));
    assert_eq!(sent[1].0, "GET");
    assert!(sent[1].1.ends_with("/session/grandchild-1"));
    assert!(sent[2].1.ends_with("/session/grandchild-1"));
    assert_eq!(sent[2].2, json!({"permission": [full_access]}));
    assert_eq!(sent.len(), 3);
}

#[tokio::test]
async fn a_failed_sub_agent_update_is_a_warning() {
    let stream = created("child-1", "session-1", Some(json!([])));
    let responses = vec![
        ok(json!({"id": "session-1"})),
        HttpResponse::new(404, vec![]),
        HttpResponse::new(500, b"{\"error\":\"nope\"}".to_vec()),
    ];
    let mut provider = provider(OpenCodeGeneration::Legacy1, responses, stream.as_bytes());
    start(&mut provider, RuntimeMode::ApprovalRequired, None).await;
    let mut warnings = Vec::new();
    while let Ok(Some(event)) = provider.next_event().await {
        if event.kind == EventKind::RuntimeWarning {
            warnings.push(
                event.payload["message"]
                    .as_str()
                    .unwrap_or_default()
                    .to_owned(),
            );
        }
    }
    assert_eq!(warnings.len(), 1);
    assert!(
        warnings[0].contains("sub-agent session child-1"),
        "{warnings:?}"
    );
}

#[tokio::test]
async fn legacy_sub_agents_drop_the_rules_they_inherited() {
    let own = json!({"permission": "task", "pattern": "*", "action": "deny"});
    let inherited = json!({"permission": "*", "pattern": "*", "action": "deny"});
    let stream = created("child-1", "session-1", Some(json!([inherited, own])));
    let responses = vec![
        ok(json!({"id": "session-1"})),
        HttpResponse::new(404, vec![]),
        ok(json!({"id": "child-1"})),
    ];
    let mut provider = provider(OpenCodeGeneration::Legacy1, responses, stream.as_bytes());
    start(&mut provider, RuntimeMode::ApprovalRequired, None).await;
    while let Ok(Some(_)) = provider.next_event().await {}
    let sent = requests(&provider);
    let parent = sent[0].2["permission"].as_array().unwrap().clone();
    let child = sent[3].2["permission"].as_array().unwrap().clone();
    assert_eq!(child.len(), parent.len() + 1);
    assert_eq!(child[..parent.len()], parent[..]);
    assert_eq!(child.last().unwrap(), &own);
}
