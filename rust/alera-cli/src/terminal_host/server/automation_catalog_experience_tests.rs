use super::*;

#[tokio::test]
async fn run_again_links_a_new_run_and_resolves_previous_failure_attention() {
    let mut fixture = harness().await;
    let run = owned_run(&mut fixture).await;
    let completed = fixture
        .actor
        .runtime_store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Failure,
            Some("Preserved work".into()),
            Some("Interrupted".into()),
            draft_definition().created_by,
        )
        .await
        .unwrap();
    let definition = fixture
        .actor
        .runtime_store
        .find_automation(&run.automation_id)
        .await
        .unwrap()
        .unwrap();
    assert!(!fixture
        .actor
        .automation_catalog_item(&definition)
        .await
        .unwrap()["attention"]
        .is_null());
    let next = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.runNow",
            &json!({"id":run.automation_id,"continueFromRunId":run.id}),
        )
        .await
        .unwrap();
    let next: AutomationRun = serde_json::from_value(next).unwrap();
    assert_ne!(next.id, run.id);
    assert_eq!(next.continue_from_run_id.as_deref(), Some(run.id.as_str()));
    assert_eq!(next.workspace_id, run.workspace_id);
    assert_eq!(next.status, AutomationRunStatus::Dispatched);
    assert!(next.rendered_prompt.unwrap().contains("Preserved work"));
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap(),
        completed
    );
    fixture
        .actor
        .runtime_store
        .complete_automation_run(
            &next.id,
            AutomationRunStatus::Success,
            Some("Recovered".into()),
            None,
            draft_definition().created_by,
        )
        .await
        .unwrap();
    assert!(fixture
        .actor
        .automation_catalog_item(&definition)
        .await
        .unwrap()["attention"]
        .is_null());
}
