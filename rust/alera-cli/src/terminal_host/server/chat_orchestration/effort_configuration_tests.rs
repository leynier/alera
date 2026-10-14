use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::models::OrchestrationRequest;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

#[test]
fn configure_distinguishes_absent_selection_from_explicit_reset() {
    for (selection, expected) in [
        (None, None),
        (Some(json!(null)), Some(None)),
        (Some(json!("high")), Some(Some("high".into()))),
    ] {
        let mut payload = json!({"requestId":"configure", "chatId":"chat"});
        if let Some(selection) = selection {
            payload["model"] = selection.clone();
            payload["reasoningEffort"] = selection;
        }
        let OrchestrationRequest::Configure {
            model,
            reasoning_effort,
            ..
        } = OrchestrationRequest::parse("configure", &payload).unwrap()
        else {
            panic!("expected configure");
        };
        assert_eq!(model, expected);
        assert_eq!(reasoning_effort, expected);
    }
    assert!(OrchestrationRequest::parse(
        "configure",
        &json!({"requestId":"bad", "chatId":"chat", "reasoningEffort":3})
    )
    .is_err());
}

#[tokio::test]
async fn configure_omits_keep_settings_and_explicit_resets_restore_provider_defaults() {
    for workspace in ["ws-a", "ws-b"] {
        let harness = TestHarness::new().await;
        let chat = harness.create_chat(workspace, "approval-required").await;
        harness.service.handle("configure", &json!({"requestId":"select", "chatId":chat, "model":"test-model", "reasoningEffort":"high"}), &human("desktop")).await.unwrap();
        harness
            .service
            .handle(
                "configure",
                &json!({"requestId":"keep", "chatId":chat, "interactionMode":"plan"}),
                &human("desktop"),
            )
            .await
            .unwrap();
        let snapshot = harness.service.runtime.snapshot(&chat).await.unwrap();
        assert_eq!(snapshot["session"]["model"], "test-model");
        assert_eq!(snapshot["session"]["reasoningEffort"], "high");
        let reset = json!({"requestId":"reset-effort", "chatId":chat, "reasoningEffort":null});
        let response = harness
            .service
            .handle("configure", &reset, &human("desktop"))
            .await
            .unwrap();
        assert_eq!(
            harness
                .service
                .handle("configure", &reset, &human("desktop"))
                .await
                .unwrap(),
            response
        );
        let snapshot = harness.service.runtime.snapshot(&chat).await.unwrap();
        assert_eq!(snapshot["session"]["model"], "test-model");
        assert!(snapshot["session"]["reasoningEffort"].is_null());
        assert_eq!(snapshot["session"]["runtimeMode"], "approval-required");
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle(
                        "configure",
                        &json!({"requestId":"reset-effort", "chatId":chat}),
                        &human("desktop")
                    )
                    .await
                    .unwrap_err()
            ),
            "request_conflict"
        );
        harness
            .service
            .handle(
                "configure",
                &json!({"requestId":"reset-model", "chatId":chat, "model":null}),
                &human("desktop"),
            )
            .await
            .unwrap();
        assert!(
            harness.service.runtime.snapshot(&chat).await.unwrap()["session"]["model"].is_null()
        );
        assert!(harness.factory.launches.lock().unwrap().is_empty());
        harness.finish().await;
    }
}

#[tokio::test]
async fn delegation_effort_reaches_create_and_existing_turn_without_escalating_modes() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto-accept-edits").await;
    harness.service.handle("configure", &json!({"requestId":"parent-effort", "chatId":parent, "model":"test-model", "reasoningEffort":"high"}), &human("desktop")).await.unwrap();
    harness
        .send_human(&parent, "parent", "Delegate using only my permissions.")
        .await;
    let caller = harness.agent(&parent).await;
    let default_child = harness
        .service
        .handle(
            "delegate",
            &delegate_payload(
                "default-effort",
                json!({"workspace":{"workspaceId":"ws-a"}}),
            ),
            &caller,
        )
        .await
        .unwrap();
    assert!(harness
        .service
        .runtime
        .snapshot(default_child["childChatId"].as_str().unwrap())
        .await
        .unwrap()["session"]["reasoningEffort"]
        .is_null());
    for (index, target) in [
        json!({"workspace":{"workspaceId":"ws-a"}}),
        json!({"workspace":{"workspaceId":"ws-b"}}),
    ]
    .into_iter()
    .enumerate()
    {
        let mut payload = delegate_payload(&format!("effort-{index}"), target);
        payload["agent"]["options"] = json!({"reasoningEffort":"high"});
        let response = harness
            .service
            .handle("delegate", &payload, &caller)
            .await
            .unwrap();
        let child = response["childChatId"].as_str().unwrap();
        let control = harness.control(child).await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        assert_eq!(
            harness.service.runtime.snapshot(child).await.unwrap()["session"]["reasoningEffort"],
            "high"
        );
        assert_eq!(response["runtimeMode"], "auto-accept-edits");
        assert_eq!(
            control.turns.lock().unwrap()[0].options["reasoningEffort"],
            "high"
        );
        control.complete(1, "Effort selected.");
        wait_idle(&harness, child).await;
        let mut next = delegate_payload(
            &format!("turn-effort-{index}"),
            json!({"chat":{"chatId":child}}),
        );
        next["agent"]["options"] = json!({"reasoningEffort":"low"});
        harness
            .service
            .handle("delegate", &next, &caller)
            .await
            .unwrap();
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(2))
            .await
            .unwrap();
        assert_eq!(
            control.turns.lock().unwrap()[1].options["reasoningEffort"],
            "low"
        );
        assert_eq!(
            harness.service.runtime.snapshot(child).await.unwrap()["session"]["runtimeMode"],
            "auto-accept-edits"
        );
        control.complete(2, "Turn effort selected.");
        wait_idle(&harness, child).await;
        let elevated = json!({"requestId":format!("elevated-{index}"), "chatId":child, "reasoningEffort":"high", "runtimeMode":"full-access"});
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("configure", &elevated, &caller)
                    .await
                    .unwrap_err()
            ),
            "mode_ceiling"
        );
        harness.service.handle("configure", &json!({"requestId":format!("bound-reset-{index}"), "chatId":child, "reasoningEffort":null}), &caller).await.unwrap();
        let snapshot = harness.service.runtime.snapshot(child).await.unwrap();
        assert!(snapshot["session"]["reasoningEffort"].is_null());
        assert_eq!(snapshot["session"]["model"], "test-model");
        assert_eq!(snapshot["session"]["runtimeMode"], "auto-accept-edits");
    }
    harness.finish().await;
}

#[tokio::test]
async fn delegation_rejects_unknown_options_and_unverified_model_efforts() {
    let harness = TestHarness::new().await;
    for (id, options) in [
        ("options", json!({"runtimeMode":"full-access"})),
        (
            "mixed",
            json!({"reasoningEffort":"high", "model":"test-model"}),
        ),
    ] {
        let mut payload = delegate_payload(id, json!({"workspace":{"workspaceId":"ws-a"}}));
        payload["agent"]["options"] = options;
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("delegate", &payload, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "unsupported"
        );
    }
    for effort in [json!(null), json!(true), json!(""), json!("x".repeat(129))] {
        assert!(super::delegation_options::delegation_effort(Some(
            &json!({"reasoningEffort":effort})
        ))
        .is_err());
    }
    for (id, model, effort) in [
        ("unverified", "custom-model", "high"),
        ("invalid", "test-model", "ultra"),
    ] {
        let mut payload = delegate_payload(id, json!({"workspace":{"workspaceId":"ws-a"}}));
        payload["agent"]["model"] = json!(model);
        payload["agent"]["options"] = json!({"reasoningEffort":effort});
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("delegate", &payload, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "unsupported"
        );
    }
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}

async fn wait_idle(harness: &TestHarness, chat: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            if harness.service.runtime.snapshot(chat).await.unwrap()["session"]["activeTurnId"]
                .is_null()
            {
                return;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}
