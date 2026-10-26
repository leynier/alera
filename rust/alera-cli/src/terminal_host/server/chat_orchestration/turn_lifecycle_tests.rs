use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use alera_provider_protocol::{EventKind, RuntimeResponse};
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn queued_task_matches_its_client_message_instead_of_the_unrelated_human_turn() {
    let mut harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    let human_turn = harness
        .send_human(&child, "human-first", "Unrelated human work.")
        .await;
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let delegated = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("queued-child", json!({"chat": {"chatId": child}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    let task_id = delegated["taskId"].as_str().unwrap();
    let task = harness
        .store
        .chat_orchestration_task(task_id)
        .await
        .unwrap()
        .unwrap();
    assert!(task.child_turn_id.is_none());
    assert_eq!(task.status, Status::Running);
    let published = tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let published = harness.events.recv().await.unwrap();
            assert_eq!(published.0["taskId"], task_id);
            if published.1 == Status::Running {
                break published;
            }
            assert_eq!(published.1, Status::Preparing);
        }
    })
    .await
    .unwrap();
    assert_eq!(published.0["taskId"], task_id);
    assert_eq!(published.1, Status::Running);
    control.complete(1, "Unrelated human completion.");
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(2))
        .await
        .unwrap();
    let task = harness
        .store
        .chat_orchestration_task(task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, Status::Running);
    let snapshot = harness.runtime.snapshot(&child).await.unwrap();
    let item = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["clientMessageId"] == format!("chat-orchestration-task:{task_id}"))
        .unwrap();
    assert_ne!(item["turnId"], human_turn["turnId"]);
    control.complete(2, "Only the delegated result.");
    harness.task_status(task_id, Status::Completed).await;
    let settled = harness
        .service
        .handle("task", &json!({"taskId": task_id}), &human("desktop"))
        .await
        .unwrap();
    assert_eq!(
        settled["task"]["result"]["text"],
        "Only the delegated result."
    );
    assert_eq!(settled["task"]["result"]["turnId"], item["turnId"]);
    harness.finish().await;
}

#[tokio::test]
async fn child_input_request_is_exposed_and_answered_through_canonical_runtime_identity() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Coordinate child input.")
        .await;
    let caller = harness.agent(&parent).await;
    let delegated = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("child-input", json!({"workspace": {"workspaceId": "ws-b"}})),
            &caller,
        )
        .await
        .unwrap();
    let task_id = delegated["taskId"].as_str().unwrap();
    let child = delegated["childChatId"].as_str().unwrap();
    let control = harness.control(child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.request_input(1, "native-request-42");
    harness.task_status(task_id, Status::NeedsInput).await;
    let requests = harness
        .service
        .handle("requests", &json!({"taskId": task_id}), &caller)
        .await
        .unwrap();
    assert_eq!(requests["requests"].as_array().unwrap().len(), 1);
    let row = &requests["requests"][0];
    assert_eq!(row["chatId"], child);
    assert_eq!(row["taskId"], task_id);
    let request_id = row["request"]["requestId"].as_str().unwrap();
    assert_ne!(request_id, "native-request-42");
    let answer = json!({"requestId": "answer-once", "chatId": child,
        "runtimeRequestId": request_id, "response": {"type": "userInput",
            "requestId": "forged-native-id", "answers": {"choice": "Use the existing branch."}}});
    let response = harness
        .service
        .handle("respond", &answer, &caller)
        .await
        .unwrap();
    assert_eq!(response["resolved"], true);
    assert_eq!(
        harness
            .service
            .handle("respond", &answer, &caller)
            .await
            .unwrap(),
        response
    );
    harness.task_status(task_id, Status::Running).await;
    let responses = control.responses.lock().unwrap().clone();
    assert_eq!(responses.len(), 1);
    assert_eq!(responses[0].request_id().to_string(), "native-request-42");
    let RuntimeResponse::UserInput { answers, .. } = &responses[0] else {
        panic!("expected user input");
    };
    assert_eq!(answers["choice"], "Use the existing branch.");
    assert!(harness
        .service
        .handle("requests", &json!({"chatId": child}), &caller)
        .await
        .unwrap()["requests"]
        .as_array()
        .unwrap()
        .is_empty());
    control.complete(1, "Completed after the parent answered.");
    harness.task_status(task_id, Status::Completed).await;
    harness.finish().await;
}

#[tokio::test]
async fn desktop_and_mobile_can_answer_unrelated_chats_and_resolved_requests_do_not_reopen() {
    let harness = TestHarness::new().await;
    for (turn, scope) in [(1, "desktop"), (2, "mobile:phone")] {
        let child = harness.create_chat("ws-b", "approval-required").await;
        harness
            .send_human(&child, &format!("human-{turn}"), "Wait for a human.")
            .await;
        let control = harness.control(&child).await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        control.request_input(1, &format!("native-{turn}"));
        let request_id = tokio::time::timeout(TEST_DEADLINE, async {
            loop {
                let response = harness
                    .service
                    .handle("requests", &json!({"chatId": child}), &human(scope))
                    .await
                    .unwrap();
                if let Some(id) = response["requests"][0]["request"]["requestId"].as_str() {
                    break id.to_owned();
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        harness
            .service
            .handle(
                "respond",
                &json!({"requestId": format!("respond-{turn}"),
            "chatId": child, "runtimeRequestId": request_id,
            "response": {"type": "userInput", "answers": {"choice": "Continue."}}}),
                &human(scope),
            )
            .await
            .unwrap();
        let stale = harness
            .service
            .handle(
                "respond",
                &json!({"requestId": format!("stale-{turn}"),
            "chatId": child, "runtimeRequestId": request_id,
            "response": {"type": "userInput", "answers": {"choice": "Again."}}}),
                &human(scope),
            )
            .await
            .unwrap_err();
        assert_eq!(error_code(&stale), "request_resolved");
    }
    harness.finish().await;
}

#[tokio::test]
async fn bounded_wait_supports_zero_fifty_any_and_all_without_restarting_inference() {
    let harness = TestHarness::new().await;
    let mut ids = Vec::new();
    let mut controls = Vec::new();
    for id in ["first", "second"] {
        let response = harness
            .service
            .handle(
                "delegate",
                &delegate_payload(id, json!({"workspace": {"workspaceId": "ws-a"}})),
                &human("desktop"),
            )
            .await
            .unwrap();
        ids.push(response["taskId"].as_str().unwrap().to_owned());
        let control = harness
            .control(response["childChatId"].as_str().unwrap())
            .await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        controls.push(control);
    }
    for until in ["any", "all"] {
        let zero = tokio::time::timeout(
            TEST_DEADLINE,
            harness.service.handle(
                "wait",
                &json!({"taskIds": ids, "waitSeconds": 0, "until": until}),
                &human("desktop"),
            ),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(zero["timedOut"], true);
    }
    controls[0].complete(1, "First result.");
    harness.task_status(&ids[0], Status::Completed).await;
    let any = tokio::time::timeout(
        TEST_DEADLINE,
        harness.service.handle(
            "wait",
            &json!({"taskIds": ids, "waitSeconds": 50, "until": "any"}),
            &human("mobile:phone"),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(any["timedOut"], false);
    let all = harness
        .service
        .handle(
            "wait",
            &json!({"taskIds": ids, "waitSeconds": 0, "until": "all"}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(all["timedOut"], true);
    controls[1].complete(1, "Second result.");
    let all = tokio::time::timeout(
        TEST_DEADLINE,
        harness.service.handle(
            "wait",
            &json!({"taskIds": ids, "waitSeconds": 50, "until": "all"}),
            &human("desktop"),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(all["timedOut"], false);
    assert_eq!(all["tasks"].as_array().unwrap().len(), 2);
    assert!(controls
        .iter()
        .all(|control| control.turns.lock().unwrap().len() == 1));
    let too_long = harness
        .service
        .handle(
            "wait",
            &json!({"taskIds": ids, "waitSeconds": 51}),
            &human("desktop"),
        )
        .await
        .unwrap_err();
    assert!(too_long.wire_message().contains("50"));
    harness.finish().await;
}

#[tokio::test]
async fn read_excludes_reasoning_native_payloads_and_credentials() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&child, "read", "Visible user input.")
        .await;
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.event(
        EventKind::ItemCompleted,
        1,
        json!({"itemType": "reasoning",
        "data": {"text": "hidden reasoning", "credential": "private-provider-token"}}),
    );
    control.event(
        EventKind::TurnPlanUpdated,
        1,
        json!({"explanation": "Visible plan.",
        "plan": [{"step": "Inspect", "status": "completed"}]}),
    );
    control.complete(1, "Visible final answer.");
    let read = tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let read = harness
                .service
                .handle("read", &json!({"chatId": child}), &human("mobile:phone"))
                .await
                .unwrap();
            if read["messages"]
                .as_array()
                .unwrap()
                .iter()
                .any(|message| message["text"] == "Visible final answer.")
            {
                break read;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(read["messages"].as_array().unwrap().len(), 2);
    assert_eq!(read["plans"][0]["steps"][0]["step"], "Inspect");
    let serialized = read.to_string();
    assert!(!serialized.contains("hidden reasoning"));
    assert!(!serialized.contains("private-provider-token"));
    assert!(!serialized.contains("native-turn"));
    harness.finish().await;
}

#[tokio::test]
async fn bounded_final_result_keeps_unicode_boundaries_and_reports_truncation() {
    let harness = TestHarness::new().await;
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("long-result", json!({"workspace": {"workspaceId": "ws-a"}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    let control = harness
        .control(response["childChatId"].as_str().unwrap())
        .await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let result = "界".repeat(super::tasks::PUBLIC_RESULT_MAX_BYTES);
    control.complete(1, &result);
    let task_id = response["taskId"].as_str().unwrap();
    harness.task_status(task_id, Status::Completed).await;
    let task = harness
        .service
        .handle("task", &json!({"taskId": task_id}), &human("desktop"))
        .await
        .unwrap();
    let text = task["task"]["result"]["text"].as_str().unwrap();
    assert!(text.len() <= super::tasks::PUBLIC_RESULT_MAX_BYTES);
    assert!(result.starts_with(text));
    assert_eq!(task["task"]["result"]["truncated"], true);
    harness.finish().await;
}
