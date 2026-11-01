//! Children that keep working after their delegated turn completed.

use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{ChatOrchestrationTask, ChatOrchestrationTaskStatus as Status};
use alera_provider_protocol::EventKind;
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::mock_provider::MockProviderControl;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

pub(super) struct Delegated {
    pub parent: String,
    pub task: String,
    pub child: String,
    pub control: Arc<MockProviderControl>,
}

/// A person delegates to a new child under an idle parent chat; the task
/// wakes that parent.
pub(super) async fn delegated(harness: &TestHarness) -> Delegated {
    let parent = harness.create_chat("ws-a", "auto").await;
    let mut payload = delegate_payload("held", json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!("always");
    payload["parentChatId"] = json!(parent);
    let response = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    let control = harness.control(&child).await;
    control.wait_turns(1).await;
    Delegated {
        parent,
        task: response["taskId"].as_str().unwrap().to_owned(),
        child,
        control,
    }
}

/// The child's agent starts a turn on its own and answers in it.
pub(super) fn continue_on_its_own(control: &MockProviderControl, native_turn: usize, text: &str) {
    control.event(
        EventKind::TurnStarted,
        native_turn,
        json!({"agentStarted": {"origin": "backgroundContinuation"}}),
    );
    control.complete(native_turn, text);
}

pub(super) async fn task(harness: &TestHarness, task_id: &str) -> ChatOrchestrationTask {
    harness
        .store
        .chat_orchestration_task(task_id)
        .await
        .unwrap()
        .unwrap()
}

/// Asserts the task stays running for a while, longer than the settle quiet.
pub(super) async fn stays_running(harness: &TestHarness, task_id: &str) {
    tokio::time::sleep(Duration::from_millis(800)).await;
    assert_eq!(task(harness, task_id).await.status, Status::Running);
}

/// The follow-up the child's newest turn opened.
pub(super) async fn followup_of(
    harness: &TestHarness,
    child: &str,
    of: &str,
) -> ChatOrchestrationTask {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            if let Some(task) = harness
                .store
                .latest_chat_orchestration_task_for_child(child)
                .await
                .unwrap()
            {
                if task
                    .launch_options
                    .as_ref()
                    .and_then(|options| options["followupOfTaskId"].as_str())
                    == Some(of)
                {
                    return task;
                }
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("no follow-up of {of} opened"))
}
