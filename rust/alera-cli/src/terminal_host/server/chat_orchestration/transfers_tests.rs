use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};
use super::wakes::deliver_next_wake;

fn transfers(snapshot: &Value) -> Vec<Value> {
    snapshot["contextTransfers"]
        .as_array()
        .cloned()
        .unwrap_or_default()
}

#[tokio::test]
async fn a_delegated_brief_and_its_delivered_result_leave_transfers() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate the research.")
        .await;
    let parent_control = harness.control(&parent).await;
    let mut payload = delegate_payload("brief", json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!("always");
    let delegated = harness
        .service
        .handle("delegate", &payload, &harness.agent(&parent).await)
        .await
        .unwrap();
    let task = delegated["taskId"].as_str().unwrap().to_owned();
    let child = delegated["childChatId"].as_str().unwrap().to_owned();
    let child_control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, child_control.wait_turns(1))
        .await
        .unwrap();
    let child_snapshot = harness.runtime.snapshot(&child).await.unwrap();
    let brief = transfers(&child_snapshot);
    assert_eq!(brief.len(), 1);
    assert_eq!(brief[0]["kind"], "subagentSpawn");
    assert_eq!(brief[0]["sourceChatId"], parent.as_str());
    assert_eq!(brief[0]["taskId"], task.as_str());
    assert_eq!(
        brief[0]["targetTurnId"],
        child_snapshot["turns"][0]["turnId"]
    );

    child_control.complete(1, "Child result.");
    harness.task_status(&task, Status::Completed).await;
    parent_control.complete(1, "Parent is ready.");
    tokio::time::timeout(TEST_DEADLINE, async {
        while !harness.runtime.snapshot(&parent).await.unwrap()["session"]["activeTurnId"].is_null()
        {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(transfers(&harness.runtime.snapshot(&parent).await.unwrap()).is_empty());
    assert!(deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events
    )
    .await
    .unwrap());
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    let result = transfers(&snapshot);
    assert_eq!(result.len(), 1);
    assert_eq!(result[0]["kind"], "subagentResult");
    assert_eq!(result[0]["sourceChatId"], child.as_str());
    assert_eq!(result[0]["targetChatId"], parent.as_str());
    assert_eq!(result[0]["status"], "consumed");
    assert_eq!(result[0]["targetTurnId"], snapshot["turns"][1]["turnId"]);
    assert!(result[0].get("error").is_none());

    let listed = harness
        .service
        .handle("transfers", &json!({"chatId": parent}), &human("desktop"))
        .await
        .unwrap();
    assert_eq!(
        listed["transfers"][0]["transferId"],
        result[0]["transferId"]
    );
    assert_eq!(listed["transfers"][0]["taskId"], task.as_str());
    let refused = harness
        .service
        .handle("transfers", &json!({}), &human("desktop"))
        .await
        .unwrap_err();
    assert!(format!("{refused:?}").contains("chatId is required"));
    harness.finish().await;
}
