use super::*;

#[tokio::test]
async fn completion_endpoints_reject_artifact_overflow_without_sealing_the_task() {
    for verb in ["orchestration.complete", "orchestration.workerDone"] {
        let (fixture, launch, token) = accepted_workflow().await;
        let workspace = fixture
            .store
            .workflow_workspace(&launch.request.workspace_id)
            .await
            .unwrap();
        commit_result(&workspace.identity.workspace.path);
        let mut output = result(&fixture);
        output["artifacts"] = json!((0..=alera_core::git::MAX_WORKFLOW_ARTIFACTS)
            .map(|index| format!("artifact-{index}.txt"))
            .collect::<Vec<_>>());
        let (mut actor, mut commands, mut responses) = actor_for(&fixture).await;
        assert!(actor
            .handle_orchestration_request(
                1,
                1,
                verb,
                &json!({"terminal": launch.terminal_handle, "task": launch.request.task_id,
                    "dispatch": launch.dispatch_id, "contextToken": token, "result": output}),
            )
            .await
            .unwrap()
            .is_none());
        let response = finish_deferred_completion(&mut actor, &mut commands, &mut responses).await;
        assert_eq!(response["ok"], false, "{verb}: {response}");
        assert!(response.to_string().contains("too many artifacts"));
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
}
