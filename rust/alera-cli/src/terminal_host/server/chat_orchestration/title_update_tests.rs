use serde_json::json;

use super::test_support::{error_code, human, TestHarness};

#[tokio::test]
async fn a_bound_agent_names_its_own_chat_but_never_over_a_person_title() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&chat, "live", "Fix the login crash.")
        .await;
    let caller = harness.agent(&chat).await;
    let unrelated = harness.create_chat("ws-b", "approval-required").await;

    let renamed = harness
        .service
        .handle(
            "updateTitle",
            &json!({"requestId": "own", "title": "Login Crash Fix"}),
            &caller,
        )
        .await
        .unwrap();
    assert_eq!(renamed["title"], "Login Crash Fix");
    let snapshot = harness.runtime.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["title"], "Login Crash Fix");
    assert_eq!(snapshot["titleSource"], "generated");

    let denied = harness
        .service
        .handle(
            "updateTitle",
            &json!({"requestId": "other", "chatId": unrelated, "title": "Taken Over"}),
            &caller,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&denied), "not_in_lineage");

    harness
        .service
        .handle(
            "updateTitle",
            &json!({"requestId": "person", "chatId": chat, "title": "My Name"}),
            &human("desktop"),
        )
        .await
        .unwrap();
    for (request, payload) in [
        ("agent-rename", json!({"title": "Agent Name"})),
        ("agent-regenerate", json!({"regenerate": true})),
    ] {
        let mut payload = payload;
        payload["requestId"] = json!(request);
        harness
            .service
            .handle("updateTitle", &payload, &caller)
            .await
            .unwrap_err();
    }
    let refused = harness
        .service
        .handle(
            "updateTitle",
            &json!({"requestId": "agent-rename-again", "title": "Agent Name"}),
            &caller,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "titleSetByUser");
    let snapshot = harness.runtime.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["title"], "My Name");
    assert_eq!(snapshot["titleSource"], "user");
    harness.finish().await;
}

#[tokio::test]
async fn update_title_takes_exactly_one_change() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    for payload in [
        json!({"requestId": "none", "chatId": chat}),
        json!({"requestId": "both", "chatId": chat, "title": "A", "regenerate": true}),
        json!({"requestId": "kind", "chatId": chat, "regenerate": "yes"}),
    ] {
        harness
            .service
            .handle("updateTitle", &payload, &human("desktop"))
            .await
            .unwrap_err();
    }
    let missing = harness
        .service
        .handle(
            "updateTitle",
            &json!({"requestId": "person", "title": "A"}),
            &human("desktop"),
        )
        .await
        .unwrap_err();
    assert!(missing.wire_message().contains("chatId"));
    harness.finish().await;
}
