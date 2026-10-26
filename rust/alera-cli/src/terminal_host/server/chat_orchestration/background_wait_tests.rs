use serde_json::json;

use super::models::OrchestrationRequest;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn a_bound_agent_marks_only_its_own_chats_background_tasks() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    let other = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&chat, "first", "Run the tests in the background.")
        .await;
    let control = harness.control(&chat).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    *control.background_tasks.lock().unwrap() = Some(vec!["tests".into()]);
    let caller = harness.agent(&chat).await;
    // A caller-supplied chat is ignored: the credential names the chat.
    let payload = json!({"requestId": "wait-0001", "taskIds": ["tests", "other"], "chatId": other});
    let marked = harness
        .service
        .handle("backgroundWait", &payload, &caller)
        .await
        .unwrap();
    assert_eq!(marked["matched"], json!(["tests"]));
    assert_eq!(marked["unmatched"], json!(["other"]));
    *control.background_tasks.lock().unwrap() = Some(Vec::new());
    let replayed = harness
        .service
        .handle("backgroundWait", &payload, &caller)
        .await
        .unwrap();
    assert_eq!(replayed, marked);
    let conflict = harness
        .service
        .handle(
            "backgroundWait",
            &json!({"requestId": "wait-0001", "taskIds": ["tests"], "waiting": false}),
            &caller,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&conflict), "request_conflict");

    let person = harness
        .service
        .handle(
            "backgroundWait",
            &json!({"requestId": "wait-0002", "taskIds": ["tests"]}),
            &human("desktop"),
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&person), "unsupported");
    harness.finish().await;
}

#[tokio::test]
async fn providers_without_background_waits_refuse_the_bound_agent() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "first", "Start a build.").await;
    let control = harness.control(&chat).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let caller = harness.agent(&chat).await;
    let error = harness
        .service
        .handle(
            "backgroundWait",
            &json!({"requestId": "wait-0001", "taskIds": ["build"]}),
            &caller,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "unsupported");
    assert!(error.wire_message().starts_with("Invalid request"));
    harness.finish().await;
}

#[test]
fn background_wait_requests_name_1_to_20_task_ids() {
    let parsed = OrchestrationRequest::parse(
        "backgroundWait",
        &json!({"requestId": "r", "taskIds": [" bash-1 "]}),
    )
    .unwrap();
    let OrchestrationRequest::BackgroundWait {
        task_ids, waiting, ..
    } = parsed
    else {
        panic!("a background wait");
    };
    assert_eq!(task_ids, ["bash-1"]);
    assert!(waiting);
    let too_many: Vec<String> = (0..21).map(|index| format!("bash-{index}")).collect();
    for payload in [
        json!({"requestId": "r", "taskIds": []}),
        json!({"requestId": "r", "taskIds": too_many}),
        json!({"requestId": "r", "taskIds": [""]}),
        json!({"requestId": "r", "taskIds": [1]}),
        json!({"requestId": "r", "taskIds": ["bash"], "waiting": "no"}),
        json!({"taskIds": ["bash"]}),
    ] {
        assert!(OrchestrationRequest::parse("backgroundWait", &payload).is_err());
    }
}
