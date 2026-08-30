use std::collections::HashMap;

use alera_core::runtime::{OrchestrationTask, OrchestrationTaskStatus};
use serde_json::{json, Value};

use super::actor_test_harness::{local_client, test_actor};
use super::ServerActor;
use crate::terminal_host::client::ClientHandle;

fn payload() -> Value {
    json!({
        "spec": "Implement the fix", "workspace": "workspace", "coordinator": "coord",
        "roleContract": {
            "version": 1, "id": "builder", "revision": 1, "name": "Builder",
            "purpose": "Fix the reported bug", "instructions": "Keep changes scoped.",
            "inputSchema": {"type": "object", "properties": {"target": {"type": "string"}}, "required": ["target"]},
            "resultSchema": {"type": "object"},
            "requiredArtifacts": ["report.md"], "checklist": [{"id": "tests", "description": "Tests pass."}]
        },
        "contractInputs": {"target": "The selected feature"}
    })
}

fn success() -> Value {
    json!({"completionKind": "success", "summary": "Fixed", "artifacts": ["report.md"],
        "filesModified": [], "validation": [{"id": "tests", "passed": true, "evidence": "3 passed"}]})
}

async fn actor(dir: &tempfile::TempDir) -> ServerActor {
    let (handle, _rx) = ClientHandle::test_channels();
    test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await
}

async fn create(actor: &mut ServerActor) -> OrchestrationTask {
    let response = actor
        .handle_orchestration_request(1, 1, "orchestration.taskCreateContracted", &payload())
        .await
        .unwrap()
        .unwrap();
    serde_json::from_value(response).unwrap()
}

async fn accept(actor: &mut ServerActor, task: &OrchestrationTask) -> String {
    let dispatch = actor
        .runtime_store
        .create_scoped_orchestration_dispatch(
            &task.id,
            "worker",
            None,
            "workspace",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    actor
        .runtime_store
        .accept_orchestration_dispatch(&dispatch.id, "worker", "")
        .await
        .unwrap();
    dispatch.id
}

#[tokio::test]
async fn role_contract_rpc_requires_explicit_new_verb_and_valid_definition_before_creation() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    assert!(actor
        .handle_orchestration_request(99, 1, "orchestration.taskCreateContracted", &payload())
        .await
        .is_err());
    assert!(actor
        .handle_orchestration_request(1, 1, "orchestration.taskCreate", &payload())
        .await
        .is_err());
    for (key, value) in [
        ("roleContract", Value::Null),
        ("contractInputs", json!({})),
        ("resultSchema", json!("{}")),
    ] {
        let mut invalid = payload();
        invalid[key] = value;
        assert!(actor
            .handle_orchestration_request(1, 1, "orchestration.taskCreateContracted", &invalid)
            .await
            .is_err());
    }
    assert!(actor
        .runtime_store
        .list_orchestration_tasks(None)
        .await
        .unwrap()
        .is_empty());
    let created = create(&mut actor).await;
    assert_eq!(
        created.role_contract.as_ref().unwrap().contract.id,
        "builder"
    );
    let mut legacy = payload();
    legacy.as_object_mut().unwrap().remove("roleContract");
    legacy.as_object_mut().unwrap().remove("contractInputs");
    let response = actor
        .handle_orchestration_request(1, 1, "orchestration.taskCreate", &legacy)
        .await
        .unwrap()
        .unwrap();
    assert!(response.get("role_contract").is_none());
}

#[tokio::test]
async fn role_contract_reaches_dry_run_context_and_coordinator_prompts() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let task = create(&mut actor).await;
    let digest = &task.role_contract.as_ref().unwrap().digest;
    let dry_run = actor
        .handle_orchestration_request(
            1,
            2,
            "orchestration.dispatch",
            &json!({"task": task.id, "to": "worker", "from": "coord", "dryRun": true}),
        )
        .await
        .unwrap()
        .unwrap();
    let text = dry_run.to_string();
    assert!(text.contains(digest));
    assert!(text.contains("The selected feature"));
    assert!(actor
        .runtime_store
        .list_orchestration_dispatches_for_task(&task.id)
        .await
        .unwrap()
        .is_empty());
    let (_, _, prompt) = actor
        .coordinator_profile_prompt_for_task(&task, &task.spec)
        .await
        .unwrap();
    assert!(prompt.contains(digest));
    accept(&mut actor, &task).await;
    let context = actor
        .handle_orchestration_request(
            1,
            3,
            "orchestration.context",
            &json!({"terminal": "worker"}),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(context["task"]["role_contract"]["digest"], *digest);
    assert!(context["workerInstructions"]
        .as_str()
        .unwrap()
        .contains(digest));
}

#[tokio::test]
async fn role_contract_all_success_rpc_routes_reject_missing_evidence_without_completing() {
    for verb in ["orchestration.complete", "orchestration.workerDone"] {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = actor(&dir).await;
        let task = create(&mut actor).await;
        let dispatch_id = accept(&mut actor, &task).await;
        let mut result = success();
        result["validation"] = json!([]);
        let mut completion = json!({"terminal": "worker", "task": task.id, "dispatch": dispatch_id, "result": result});
        assert!(
            actor
                .handle_orchestration_request(1, 4, verb, &completion)
                .await
                .is_err(),
            "{verb}"
        );
        assert_eq!(
            actor
                .runtime_store
                .orchestration_task_by_id(&task.id)
                .await
                .unwrap()
                .unwrap()
                .status,
            OrchestrationTaskStatus::Dispatched
        );
        completion["result"] = success();
        actor
            .handle_orchestration_request(1, 5, verb, &completion)
            .await
            .unwrap();
        assert_eq!(
            actor
                .runtime_store
                .orchestration_task_by_id(&task.id)
                .await
                .unwrap()
                .unwrap()
                .status,
            OrchestrationTaskStatus::Completed
        );
    }
}

#[tokio::test]
async fn role_contract_failure_rpc_keeps_failure_reporting_available() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir).await;
    let task = create(&mut actor).await;
    accept(&mut actor, &task).await;
    let response = actor.handle_orchestration_request(1, 4, "orchestration.complete",
        &json!({"terminal": "worker", "result": {"completionKind": "failure", "summary": "Tests failed",
            "artifacts": [], "filesModified": [], "validation": []}})).await.unwrap().unwrap();
    assert_eq!(response["dispatchStatus"], "failed");
    assert_eq!(
        actor
            .runtime_store
            .orchestration_task_by_id(&task.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Ready
    );
}
