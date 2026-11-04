use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;
use super::test_support::{error_code, human, TestHarness};

/// A parent agent on codex with test-model at high effort.
async fn parent(harness: &TestHarness) -> OrchestrationCaller {
    let chat = harness.create_chat("ws-a", "auto").await;
    harness
        .service
        .handle(
            "configure",
            &json!({"requestId": "parent", "chatId": chat, "model": "test-model",
                "reasoningEffort": "high"}),
            &human("desktop"),
        )
        .await
        .unwrap();
    harness.send_human(&chat, "go", "Delegate.").await;
    harness.agent(&chat).await
}

async fn delegate(
    harness: &TestHarness,
    caller: &OrchestrationCaller,
    id: &str,
    agent: Option<Value>,
    workspace: &str,
) -> Value {
    let mut payload = json!({"requestId": id, "task": "Inspect.", "notify": "never",
        "target": {"workspace": {"workspaceId": workspace}}});
    if let Some(agent) = agent {
        payload["agent"] = agent;
    }
    harness
        .service
        .handle("delegate", &payload, caller)
        .await
        .unwrap()
}

async fn session(harness: &TestHarness, response: &Value) -> Value {
    harness
        .service
        .runtime
        .snapshot(response["childChatId"].as_str().unwrap())
        .await
        .unwrap()["session"]
        .clone()
}

#[tokio::test]
async fn a_new_child_inherits_the_parents_instance_model_and_effort() {
    let harness = TestHarness::new().await;
    let caller = parent(&harness).await;
    let inherited = delegate(&harness, &caller, "inherit", None, "ws-a").await;
    let child = session(&harness, &inherited).await;
    assert_eq!(child["model"], "test-model");
    assert_eq!(child["reasoningEffort"], "high");
    assert_eq!(inherited["providerInstanceId"], "codex");
    assert_eq!(inherited["reasoningEffort"], "high");
    assert_eq!(inherited["reasoningEffortSource"], "inherited");

    let null_options = delegate(
        &harness,
        &caller,
        "null",
        Some(json!({"options": null})),
        "ws-a",
    )
    .await;
    assert_eq!(
        session(&harness, &null_options).await["reasoningEffort"],
        "high"
    );

    let cleared = delegate(
        &harness,
        &caller,
        "clear",
        Some(json!({"options": {}})),
        "ws-a",
    )
    .await;
    assert!(session(&harness, &cleared).await["reasoningEffort"].is_null());
    assert!(cleared.get("reasoningEffortSource").is_none());

    let explicit = delegate(
        &harness,
        &caller,
        "explicit",
        Some(json!({"options": {"reasoningEffort": "low"}})),
        "ws-a",
    )
    .await;
    assert_eq!(session(&harness, &explicit).await["reasoningEffort"], "low");
    assert_eq!(explicit["reasoningEffortSource"], "explicit");
    harness.finish().await;
}

#[tokio::test]
async fn effort_stays_behind_on_another_model_or_host() {
    let harness = TestHarness::new().await;
    let caller = parent(&harness).await;
    let other_model = delegate(
        &harness,
        &caller,
        "model",
        Some(json!({"model": "other-model"})),
        "ws-a",
    )
    .await;
    assert!(other_model.get("reasoningEffortSource").is_none());
    assert!(session(&harness, &other_model).await["reasoningEffort"].is_null());
    let other_host = delegate(&harness, &caller, "host", None, "ws-b").await;
    assert_eq!(other_host["providerInstanceId"], "codex");
    assert!(other_host.get("reasoningEffortSource").is_none());
    harness.finish().await;
}

#[tokio::test]
async fn people_and_existing_chats_inherit_nothing() {
    let harness = TestHarness::new().await;
    let error = harness
        .service
        .handle(
            "delegate",
            &json!({"requestId": "person", "task": "Inspect.",
                "target": {"newWorkspace": {"projectId": "project-a", "hostId": "local", "mode": "shared"}}}),
            &human("desktop"),
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "providerUnavailable");
    assert!(harness.targets.created.lock().unwrap().is_empty());
    assert!(harness
        .service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap()["tasks"]
        .as_array()
        .unwrap()
        .is_empty());

    let caller = parent(&harness).await;
    let existing = harness.create_chat("ws-a", "auto").await;
    let response = harness
        .service
        .handle(
            "delegate",
            &json!({"requestId": "existing", "task": "Continue.", "notify": "never",
                "target": {"chat": {"chatId": existing}}}),
            &caller,
        )
        .await
        .unwrap();
    assert!(response.get("reasoningEffortSource").is_none());
    harness.finish().await;
}

#[test]
fn only_an_effort_error_drops_the_inherited_effort() {
    use crate::terminal_host::host_error::HostError;
    assert!(super::delegation_inheritance::effort_refused(
        &HostError::conflict(
            "invalid_request",
            "This model does not report support for this reasoning effort.",
            json!({}),
        )
    ));
    assert!(!super::delegation_inheritance::effort_refused(
        &HostError::state("disk full")
    ));
}
