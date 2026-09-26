use std::collections::HashMap;

use super::super::actor_test_harness::test_actor;
use super::super::{ClientHandle, ClientState};
use super::*;

fn settings() -> RuntimeAiAssistSettings {
    serde_json::from_value(json!({"enabled": true, "agent": "claude", "timeoutSeconds": 45}))
        .unwrap()
}

#[test]
fn forwarded_payload_names_the_workspace_and_carries_hub_settings() {
    let forwarded = forwarded_payload(
        "ws-remote",
        &settings(),
        json!({"operationId": "op-1", "tabId": "hub-tab", "text": "hello"}),
    )
    .unwrap();
    assert_eq!(forwarded["workspaceId"], "ws-remote");
    assert!(
        forwarded.get("tabId").is_none(),
        "hub tabs do not exist on the satellite"
    );
    assert_eq!(forwarded["operationId"], "op-1");
    assert_eq!(forwarded[AI_ASSIST_SETTINGS_KEY]["agent"], "claude");
    assert_eq!(forwarded[AI_ASSIST_SETTINGS_KEY]["timeoutSeconds"], 45);
    assert!(forwarded_payload("ws", &settings(), json!("text")).is_err());
}

#[test]
fn hub_settings_are_optional_and_validated() {
    assert!(hub_ai_assist_settings(&json!({})).unwrap().is_none());
    assert!(
        hub_ai_assist_settings(&json!({AI_ASSIST_SETTINGS_KEY: null}))
            .unwrap()
            .is_none()
    );
    let parsed = hub_ai_assist_settings(&json!({AI_ASSIST_SETTINGS_KEY: settings()}))
        .unwrap()
        .unwrap();
    assert_eq!(parsed.agent, "claude");
    assert!(hub_ai_assist_settings(&json!({AI_ASSIST_SETTINGS_KEY: "claude"})).is_err());
}

#[tokio::test]
async fn hub_settings_win_over_the_runtime_settings_when_present() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let own = effective_ai_assist_settings(&store, None).await.unwrap();
    let mut hub = settings();
    hub.agent = "opencode".into();
    hub.timeout_seconds = own.timeout_seconds + 7;
    let chosen = effective_ai_assist_settings(&store, Some(hub))
        .await
        .unwrap();
    assert_eq!(chosen.agent, "opencode");
    assert_eq!(chosen.timeout_seconds, own.timeout_seconds + 7);
}

#[tokio::test]
async fn only_a_local_client_may_send_ai_assist_settings() {
    let root = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let (local, _) = ClientHandle::test_channels();
    clients.insert(1, ClientState::local(local, true));
    let (phone, _) = ClientHandle::test_channels();
    let mut mobile = ClientState::local(phone, false);
    mobile.kind = ClientKind::Mobile;
    clients.insert(2, mobile);
    let actor = test_actor(&root, clients, HashMap::new()).await;
    let payload = json!({AI_ASSIST_SETTINGS_KEY: {"customCommand": "sh -c 'id'"}});
    assert!(actor.refuse_hub_only_payload_fields(1, &payload).is_ok());
    let refused = actor
        .refuse_hub_only_payload_fields(2, &payload)
        .unwrap_err();
    assert!(refused.to_string().contains("local client"), "{refused}");
    assert!(actor.refuse_hub_only_payload_fields(2, &json!({})).is_ok());
    assert!(actor.refuse_hub_only_payload_fields(99, &payload).is_err());
}

#[test]
fn only_checkout_generations_are_routed_by_workspace_id() {
    assert!(is_workspace_generation_verb(
        "aiText.commitMessage.generate"
    ));
    assert!(is_workspace_generation_verb(
        "aiText.pullRequestDetails.generate"
    ));
    assert!(!is_workspace_generation_verb(
        "aiText.workspaceIdentity.generate"
    ));
    assert!(!is_workspace_generation_verb("aiText.cancel"));
}
