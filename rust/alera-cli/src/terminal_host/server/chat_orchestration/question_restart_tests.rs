//! A delegated child's question outlives a runtime restart: it stays pending
//! as `answerBy: message`, its task keeps waiting, and the answer starts a
//! new turn the task follows to its end.

use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

async fn wait_for_request(harness: &TestHarness, child: &str) -> Value {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(child).await.unwrap();
            if let Some(request) = snapshot["pendingRequests"].get(0) {
                return request.clone();
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the child never asked")
}

#[tokio::test]
async fn a_question_asked_before_a_restart_is_answered_by_message_and_the_task_completes() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    let person = human("desktop");
    let mut payload = delegate_payload("asks", json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["parentChatId"] = json!(parent);
    let delegated = harness
        .service
        .handle("delegate", &payload, &person)
        .await
        .unwrap();
    let task = delegated["taskId"].as_str().unwrap().to_owned();
    let child = delegated["childChatId"].as_str().unwrap().to_owned();
    let control = harness.control(&child).await;
    control.wait_turns(1).await;
    control.request_input(1, "native-question");
    wait_for_request(&harness, &child).await;
    harness.task_status(&task, Status::NeedsInput).await;

    let harness = harness.restart().await;
    harness.runtime.recover_after_restart().await.unwrap();
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert!(recovery.settled.is_empty(), "{:?}", recovery.settled);
    assert_eq!(recovery.awaiting_answer.len(), 1);
    harness
        .service
        .resume_task_monitors(&recovery.awaiting_answer);
    let request = wait_for_request(&harness, &child).await;
    assert_eq!(request["answerBy"], "message");
    let request_id = request["requestId"].as_str().unwrap().to_owned();

    // An unknown question id is refused and the question stays.
    let error = harness
        .service
        .handle(
            "respond",
            &json!({"requestId": "bad", "chatId": child, "runtimeRequestId": request_id,
                "response": {"type": "userInput", "answers": {"other": "x"}}}),
            &person,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "invalidAnswers");

    let answered = harness
        .service
        .handle(
            "respond",
            &json!({"requestId": "answer", "chatId": child, "runtimeRequestId": request_id,
                "response": {"type": "userInput", "answers": {"choice": "Staging"}}}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(answered["answeredBy"], "message");
    let resumed = harness.control(&child).await;
    resumed.wait_turns(1).await;
    assert_eq!(
        resumed.turns.lock().unwrap()[0].input,
        "Which target?\nStaging"
    );
    let snapshot = harness.runtime.snapshot(&child).await.unwrap();
    assert_eq!(snapshot["pendingRequests"], json!([]));
    harness.task_status(&task, Status::NeedsInput).await;
    resumed.complete(1, "Deployed to staging.");
    harness.task_status(&task, Status::Completed).await;
    let settled = harness
        .store
        .chat_orchestration_task(&task)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(settled.result_text.as_deref(), Some("Deployed to staging."));
    harness.finish().await;
}
