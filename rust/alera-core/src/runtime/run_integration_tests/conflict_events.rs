//! Merge conflicts end an attempt's integration without enabling its
//! dependents, and the run timeline records each step that led there.

use super::*;

#[tokio::test]
async fn workflow_integration_store_conflicts_are_inspectable_and_do_not_enable_dependents() {
    let fixture = Fixture::new().await;
    let record = fixture.reserve().await;
    let conflict = WorkflowGitPreparation::Conflict {
        paths: vec!["result.txt".into()],
        truncated: false,
    };
    let record = fixture
        .store
        .record_workflow_integration_preparation(&record.request.id, &conflict)
        .await
        .unwrap();
    assert_eq!(record.state, WorkflowIntegrationState::Conflict);
    assert_eq!(record.conflict_paths, vec!["result.txt"]);
    fixture.assert_dependent_blocked().await;
    let page = fixture
        .store
        .workflow_integrations_page(&fixture.plan.run_id, 0)
        .await
        .unwrap();
    assert_eq!(page.len(), 1);
    assert!(fixture
        .store
        .workflow_integrations_page(&fixture.plan.run_id, page[0].0)
        .await
        .unwrap()
        .is_empty());
    assert!(sqlx::query("DELETE FROM runIntegrations WHERE id = ?")
        .bind(&record.request.id)
        .execute(fixture.store.pool())
        .await
        .is_err());

    let events = fixture
        .store
        .run_events(&fixture.plan.run_id, 1000)
        .await
        .unwrap();
    let event = |kind: &str| {
        events
            .iter()
            .find(|event| event.kind == kind)
            .unwrap_or_else(|| panic!("no {kind} event"))
    };
    let prepared = event("attemptPrepared");
    assert_eq!(prepared.task_id.as_ref(), Some(&fixture.input.task_id));
    assert_eq!(prepared.summary, "Attempt 1");
    assert_eq!(
        prepared.payload.as_ref().unwrap()["workspaceId"],
        json!(fixture.input.workspace_id)
    );
    let accepted = event("accepted");
    assert_eq!(accepted.dispatch_id.as_ref(), Some(&fixture.dispatch));
    assert_eq!(accepted.actor_kind.as_deref(), Some("agent"));
    let started = event("integrationStarted");
    assert_eq!(started.task_id.as_ref(), Some(&fixture.input.task_id));
    assert_eq!(
        started.payload.as_ref().unwrap()["integrationId"],
        json!(record.request.id)
    );
    let conflict = event("conflict");
    assert_eq!(conflict.summary, "1 conflicting path");
    assert_eq!(
        conflict.payload.as_ref().unwrap()["paths"],
        json!(["result.txt"])
    );
}
