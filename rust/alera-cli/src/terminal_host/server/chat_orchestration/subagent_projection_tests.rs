use alera_core::runtime::ChatOrchestrationTaskStatus;
use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::test_support::{human, TestHarness, TEST_DEADLINE};

fn item(snapshot: &Value, predicate: impl Fn(&Value) -> bool) -> Option<&Value> {
    snapshot["items"]
        .as_array()?
        .iter()
        .find(|item| predicate(item))
}

#[tokio::test]
async fn native_subagents_hang_under_the_call_that_started_them() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&chat, "go", "Explore with helpers.")
        .await;
    let control = harness.control(&chat).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    // Claude: a Task tool call, its task events and an item of its own.
    control.item_event(
        EventKind::ItemStarted,
        1,
        "task-call",
        json!({"itemType": "dynamic_tool_call", "status": "inProgress", "title": "Task"}),
    );
    control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "claude-task", "description": "Explore the parser",
            "status": "running", "nativeTask": {"nativeToolCallId": "task-call"}}),
    );
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "sub-command",
        json!({"itemType": "command_execution", "status": "completed",
            "data": {"command": "ls"}, "parentToolUseId": "task-call"}),
    );
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "claude-task", "summary": "Found the parser",
            "status": "completed", "nativeTask": {"nativeToolCallId": "task-call"}}),
    );
    // Codex: a collab call names its child thread, whose events are tasks.
    control.item_event(
        EventKind::ItemStarted,
        1,
        "collab-call",
        json!({"itemType": "collab_agent_tool_call", "status": "inProgress",
            "nativeTask": {"nativeToolCallId": "collab-call",
                "childNativeThreadIds": ["child-thread"]}}),
    );
    control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "child-thread", "status": "failed",
            "nativeTask": {"childNativeThreadIds": ["child-thread"]}}),
    );
    control.complete(1, "Done.");
    let snapshot = tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.service.runtime.snapshot(&chat).await.unwrap();
            let codex_done = item(&snapshot, |item| {
                item["normalized"]["subagent"]["status"] == "failed"
            })
            .is_some();
            let answered = item(&snapshot, |item| item["text"] == "Done.").is_some();
            if codex_done && answered {
                break snapshot;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let task = item(&snapshot, |item| item["title"] == "Task").unwrap();
    let mut subagent = task["normalized"]["subagent"].clone();
    for clock in ["startedAt", "completedAt"] {
        assert!(subagent[clock].is_string(), "{clock}");
        subagent.as_object_mut().unwrap().remove(clock);
    }
    assert_eq!(
        subagent,
        json!({"status": "completed", "taskId": "claude-task",
            "description": "Explore the parser", "summary": "Found the parser"})
    );
    let command = item(&snapshot, |item| item["type"] == "command_execution").unwrap();
    assert_eq!(command["normalized"]["parentItemId"], task["itemId"]);
    let collab = item(&snapshot, |item| item["type"] == "collab_agent_tool_call").unwrap();
    assert_eq!(collab["normalized"]["subagent"]["status"], "failed");
    assert!(task["normalized"].get("parentItemId").is_none());
    harness.finish().await;
}

#[tokio::test]
async fn a_delegated_result_skips_subagent_and_blank_assistant_items() {
    let harness = TestHarness::new().await;
    let response = harness
        .service
        .handle(
            "delegate",
            &json!({"requestId": "r1", "task": "Answer with helpers.", "notify": "never",
                "agent": {"providerInstanceId": "codex"},
                "target": {"workspace": {"workspaceId": "ws-a"}}}),
            &human("desktop"),
        )
        .await
        .unwrap();
    let task_id = response["taskId"].as_str().unwrap();
    let child = response["childChatId"].as_str().unwrap();
    let control = harness.control(child).await;
    control.wait_turns(1).await;
    control.item_event(
        EventKind::ItemStarted,
        1,
        "task-call",
        json!({"itemType": "dynamic_tool_call", "status": "inProgress", "title": "Task"}),
    );
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "main-answer",
        json!({"itemType": "assistant_message", "status": "completed",
            "data": {"text": "Main answer"}}),
    );
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "sub-answer",
        json!({"itemType": "assistant_message", "status": "completed",
            "data": {"text": "Sub-agent answer"}, "parentToolUseId": "task-call"}),
    );
    control.item_event(
        EventKind::ItemCompleted,
        1,
        "blank-answer",
        json!({"itemType": "assistant_message", "status": "completed",
            "data": {"text": "  \n"}}),
    );
    control.event(EventKind::TurnCompleted, 1, json!({"state": "completed"}));
    harness
        .task_status(task_id, ChatOrchestrationTaskStatus::Completed)
        .await;
    let task = harness
        .store
        .chat_orchestration_task(task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.result_text.as_deref(), Some("Main answer"));
    harness.finish().await;
}
