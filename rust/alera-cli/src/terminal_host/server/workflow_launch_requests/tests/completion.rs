use std::path::Path;

use alera_core::runtime::{OrchestrationTaskStatus, WorkflowLaunchRecord};
use serde_json::{json, Value};

use crate::terminal_host::server::ServerCommand;

use super::*;

async fn accepted_workflow() -> (Fixture, WorkflowLaunchRecord, String) {
    let fixture = Fixture::new("").await;
    let (_, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    fixture
        .store
        .claim_workflow_launch(&record.id)
        .await
        .unwrap();
    fixture
        .store
        .mark_workflow_launch_started(&record.id)
        .await
        .unwrap();
    fixture
        .store
        .accept_orchestration_dispatch(
            &record.dispatch_id,
            &record.terminal_handle,
            &hex::encode(Sha256::digest(token.as_bytes())),
        )
        .await
        .unwrap();
    drop(locks);
    (fixture, record, token)
}

fn commit_result(path: &str) -> String {
    let repo = git2::Repository::open(path).unwrap();
    std::fs::write(Path::new(path).join("shared.txt"), "completed\n").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("shared.txt")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = repo.signature().unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "test: completed result",
        &tree,
        &[&parent],
    )
    .unwrap()
    .to_string()
}

fn result(fixture: &Fixture) -> Value {
    let contract = &fixture
        .plan
        .plan
        .tasks
        .iter()
        .find(|task| task.task.id == "fix")
        .unwrap()
        .contract
        .contract;
    json!({
        "completionKind": "success",
        "summary": "Completed",
        "artifacts": ["shared.txt"],
        "filesModified": ["shared.txt"],
        "validation": contract.checklist.iter().map(|item| json!({
            "id": item.id,
            "passed": true,
            "evidence": "focused checks passed",
        })).collect::<Vec<_>>(),
    })
}

async fn actor_for(
    fixture: &Fixture,
) -> (
    ServerActor,
    tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
    tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) {
    let directory = tempfile::tempdir().unwrap();
    let (client, responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &directory,
        HashMap::from([(1, local_client(client))]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    (actor, commands, responses)
}

async fn finish_deferred_completion(
    actor: &mut ServerActor,
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
    responses: &mut tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) -> Value {
    let command = tokio::time::timeout(std::time::Duration::from_secs(10), commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        &command,
        ServerCommand::OrchestrationCompletionFinished(_)
    ));
    actor.handle(command).await;
    tokio::time::timeout(std::time::Duration::from_secs(10), responses.recv())
        .await
        .unwrap()
        .unwrap()
        .as_json()
        .unwrap()
}

#[tokio::test]
async fn workflow_completion_endpoints_capture_the_task_tip() {
    for verb in ["orchestration.complete", "orchestration.workerDone"] {
        let (fixture, launch, token) = accepted_workflow().await;
        let workspace = fixture
            .store
            .workflow_workspace(&launch.request.workspace_id)
            .await
            .unwrap();
        let sha = commit_result(&workspace.identity.workspace.path);
        let (mut actor, mut commands, mut responses) = actor_for(&fixture).await;
        let response = actor
            .handle_orchestration_request(
                1,
                1,
                verb,
                &json!({
                    "terminal": launch.terminal_handle,
                    "task": launch.request.task_id,
                    "dispatch": launch.dispatch_id,
                    "contextToken": token,
                    "result": result(&fixture),
                }),
            )
            .await
            .unwrap();
        assert!(response.is_none());
        let inspection = actor
            .handle_orchestration_request(
                1,
                2,
                "orchestration.taskShow",
                &json!({"id": launch.request.task_id}),
            )
            .await
            .unwrap()
            .unwrap();
        assert_eq!(inspection["task"]["status"], "dispatched");
        let response = finish_deferred_completion(&mut actor, &mut commands, &mut responses).await;
        assert_eq!(response["payload"]["lifecycleAccepted"], true);
        let completed = fixture
            .store
            .orchestration_dispatch_by_id(&launch.dispatch_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(completed.completion_sha.as_deref(), Some(sha.as_str()));
    }
}

#[tokio::test]
async fn workflow_completion_rejects_missing_invalid_or_dirty_result_sha_without_state_change() {
    let (fixture, launch, token) = accepted_workflow().await;
    let result = result(&fixture).to_string();
    assert!(fixture
        .store
        .complete_orchestration_dispatch(&launch.dispatch_id, &launch.terminal_handle, &result)
        .await
        .unwrap_err()
        .to_string()
        .contains("must include its exact result SHA"));
    assert!(fixture
        .store
        .complete_workflow_orchestration_dispatch(
            &launch.dispatch_id,
            &launch.terminal_handle,
            &result,
            "invalid",
        )
        .await
        .unwrap_err()
        .to_string()
        .contains("exact committed result SHA"));
    let workspace = fixture
        .store
        .workflow_workspace(&launch.request.workspace_id)
        .await
        .unwrap();
    std::fs::write(
        Path::new(&workspace.identity.workspace.path).join("shared.txt"),
        "dirty\n",
    )
    .unwrap();
    let (mut actor, mut commands, mut responses) = actor_for(&fixture).await;
    let response = actor
        .handle_orchestration_request(
            1,
            1,
            "orchestration.complete",
            &json!({
                "terminal": launch.terminal_handle,
                "contextToken": token,
                "result": serde_json::from_str::<Value>(&result).unwrap(),
            }),
        )
        .await
        .unwrap();
    assert!(response.is_none());
    let response = finish_deferred_completion(&mut actor, &mut commands, &mut responses).await;
    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("pending changes"));
    let dispatch = fixture
        .store
        .orchestration_dispatch_by_id(&launch.dispatch_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(dispatch.status, OrchestrationDispatchStatus::Dispatched);
    assert!(dispatch.completion_sha.is_none());
    assert_eq!(
        fixture
            .store
            .orchestration_task_by_id(&launch.request.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Dispatched
    );
}

#[tokio::test]
async fn workflow_completion_rechecks_dispatch_after_deferred_git_work() {
    let (fixture, launch, token) = accepted_workflow().await;
    let workspace = fixture
        .store
        .workflow_workspace(&launch.request.workspace_id)
        .await
        .unwrap();
    commit_result(&workspace.identity.workspace.path);
    let (mut actor, mut commands, mut responses) = actor_for(&fixture).await;

    let response = actor
        .handle_orchestration_request(
            1,
            1,
            "orchestration.complete",
            &json!({
                "terminal": launch.terminal_handle,
                "contextToken": token,
                "result": result(&fixture),
            }),
        )
        .await
        .unwrap();
    assert!(response.is_none());
    fixture
        .store
        .cancel_orchestration_task(&launch.request.task_id, "cancel while verifying")
        .await
        .unwrap();

    let response = finish_deferred_completion(&mut actor, &mut commands, &mut responses).await;
    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("no longer active"));
    let dispatch = fixture
        .store
        .orchestration_dispatch_by_id(&launch.dispatch_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(dispatch.status, OrchestrationDispatchStatus::Cancelled);
    assert!(dispatch.completion_sha.is_none());
}
