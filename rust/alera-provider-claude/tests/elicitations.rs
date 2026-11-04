mod support;

use alera_provider_claude::ClaudeProvider;
use alera_provider_protocol::{
    ElicitationAction, EventKind, Provider, ProviderEvent, RequestKind, RuntimeResponse, TurnInput,
};
use serde_json::{json, Value};
use support::*;

fn elicitation(request: Value) -> Value {
    let mut frame = json!({
        "subtype": "elicitation", "mcp_server_name": "github", "message": "Who reviews?",
    });
    for (key, value) in request.as_object().unwrap() {
        frame[key] = value.clone();
    }
    json!({"type": "control_request", "request_id": "elicit-native", "request": frame})
}

async fn opened(frames: Vec<Value>) -> (ClaudeProvider, ScriptedTransportHandle, ProviderEvent) {
    let mut incoming = vec![initialize_response()];
    incoming.extend(frames);
    let (mut provider, handle) = started_provider(incoming).await;
    provider
        .send_turn(TurnInput::text("app-thread", "elicit"))
        .await
        .unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::RequestOpened {
            return (provider, handle, event);
        }
    }
}

async fn answer(
    provider: &mut ClaudeProvider,
    handle: &ScriptedTransportHandle,
    event: &ProviderEvent,
    action: ElicitationAction,
    content: Option<Value>,
) -> Value {
    let request = event.runtime_request.clone().unwrap();
    provider
        .respond(RuntimeResponse::Elicitation {
            request_id: request.request_id,
            action,
            content,
        })
        .await
        .unwrap();
    for _ in 0..50 {
        tokio::task::yield_now().await;
        let writes = handle.writes.lock().unwrap();
        if let Some(frame) = writes
            .iter()
            .find(|frame| frame["response"]["request_id"] == "elicit-native")
        {
            return frame["response"]["response"].clone();
        }
    }
    panic!("no elicitation reply was written");
}

#[tokio::test]
async fn a_form_elicitation_opens_the_generic_request_and_sends_the_form() {
    let schema = json!({"type": "object", "properties": {"name": {"type": "string"}}});
    let (mut provider, handle, event) = opened(vec![elicitation(json!({
        "mode": "form", "requested_schema": schema, "title": "Reviewer", "elicitation_id": "e-1",
    }))])
    .await;
    event.validate().unwrap();
    let request = event.runtime_request.clone().unwrap();
    assert_eq!(request.kind, RequestKind::McpElicitationApproval);
    assert!(!request.supports_feedback);
    assert_eq!(event.payload["serverName"], "github");
    assert_eq!(event.payload["mode"], "form");
    assert_eq!(event.payload["requestedSchema"], schema);
    assert_eq!(event.payload["title"], "Reviewer");
    assert_eq!(
        event
            .provider_refs
            .as_ref()
            .unwrap()
            .provider_request_id
            .as_deref(),
        Some("elicit-native")
    );
    let reply = answer(
        &mut provider,
        &handle,
        &event,
        ElicitationAction::Accept,
        Some(json!({"name": "Ada"})),
    )
    .await;
    assert_eq!(
        reply,
        json!({"action": "accept", "content": {"name": "Ada"}})
    );
    let resolved = provider.next_event().await.unwrap().unwrap();
    assert_eq!(resolved.kind, EventKind::RequestResolved);
    assert!(resolved.payload.get("resolution").is_none());
}

#[tokio::test]
async fn confirmations_and_links_accept_without_values() {
    let (mut provider, handle, event) = opened(vec![elicitation(json!({
        "mode": "form", "requested_schema": {"type": "object", "properties": {}},
    }))])
    .await;
    let reply = answer(
        &mut provider,
        &handle,
        &event,
        ElicitationAction::Accept,
        None,
    )
    .await;
    assert_eq!(reply, json!({"action": "accept", "content": {}}));

    let (mut provider, handle, event) =
        opened(vec![elicitation(json!({"url": "https://auth.example"}))]).await;
    assert_eq!(event.payload["mode"], "url");
    assert_eq!(event.payload["url"], "https://auth.example");
    let reply = answer(
        &mut provider,
        &handle,
        &event,
        ElicitationAction::Accept,
        None,
    )
    .await;
    assert_eq!(reply, json!({"action": "accept"}));

    let (mut provider, handle, event) = opened(vec![elicitation(json!({}))]).await;
    let reply = answer(
        &mut provider,
        &handle,
        &event,
        ElicitationAction::Cancel,
        None,
    )
    .await;
    assert_eq!(reply, json!({"action": "cancel"}));
}

#[tokio::test]
async fn content_that_is_not_an_object_is_rejected_and_the_request_stays_open() {
    let (mut provider, _handle, event) = opened(vec![elicitation(json!({}))]).await;
    let request = event.runtime_request.unwrap();
    let error = provider
        .respond(RuntimeResponse::Elicitation {
            request_id: request.request_id.clone(),
            action: ElicitationAction::Accept,
            content: Some(json!("text")),
        })
        .await
        .unwrap_err();
    assert!(error.to_string().contains("null or an object"), "{error}");
    provider
        .respond(RuntimeResponse::Elicitation {
            request_id: request.request_id,
            action: ElicitationAction::Decline,
            content: None,
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn a_cancelled_elicitation_withdraws_its_card() {
    let (mut provider, _handle, event) = opened(vec![
        elicitation(json!({})),
        json!({"type": "control_cancel_request", "request_id": "elicit-native"}),
        json!({
            "type": "system", "subtype": "elicitation_complete", "session_id": "native-session",
            "mcp_server_name": "github", "elicitation_id": "e-1"
        }),
        result_message(false, None),
    ])
    .await;
    let request_id = event.runtime_request.unwrap().request_id.to_string();
    let mut withdrawn = None;
    let mut status = None;
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        match event.kind {
            EventKind::RequestResolved => withdrawn = Some(event),
            EventKind::McpStatusUpdated => status = Some(event),
            EventKind::TurnCompleted => break,
            _ => {}
        }
    }
    let withdrawn = withdrawn.expect("the cancelled card is withdrawn");
    assert_eq!(withdrawn.request_id.as_deref(), Some(request_id.as_str()));
    assert_eq!(withdrawn.payload["decision"], "cancel");
    assert_eq!(withdrawn.payload["withdrawn"], true);
    assert_eq!(status.unwrap().payload["status"], "elicitationComplete");
}
