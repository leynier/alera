use super::*;
use crate::managed_workspace::workflow::tests::fixture::Fixture;
use alera_core::runtime::{ControlWorkflowExecution, WorkflowExecutionAction};

#[tokio::test]
async fn workflow_cleanup_preview_preserves_selection_and_rejects_foreign_resources() {
    let fixture = Fixture::new("").await;
    let resource = fixture.integration().await;
    let id = Uuid::new_v4().to_string();
    let request = |run: &str, remove_branch| CleanupSelection {
        id: id.clone(),
        run_id: run.into(),
        resources: vec![CleanupResourceSelection {
            workspace_id: resource.identity.workspace.id.clone(),
            remove_branch,
        }],
    };
    assert!(preview(&fixture.store, request("foreign-run", false))
        .await
        .is_err());
    assert!(
        preview(&fixture.store, request(&fixture.plan.run_id, false))
            .await
            .is_err()
    );
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-for-cleanup-preview".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    let first = preview(&fixture.store, request(&fixture.plan.run_id, false))
        .await
        .unwrap();
    assert!(!first.items[0].remove_branch);
    assert!(!first.items[0].git.dirty);
    let obstruction = Path::new(&resource.identity.workspace.path).join("untracked-after-preview");
    std::fs::write(&obstruction, "preserve this file").unwrap();
    let replay = preview(&fixture.store, request(&fixture.plan.run_id, false))
        .await
        .unwrap();
    assert_eq!(
        serde_json::to_value(&first).unwrap(),
        serde_json::to_value(replay).unwrap()
    );
    assert!(preview(&fixture.store, request(&fixture.plan.run_id, true))
        .await
        .is_err());
    let mut fresh = request(&fixture.plan.run_id, false);
    fresh.id = Uuid::new_v4().to_string();
    let dirty = preview(&fixture.store, fresh).await.unwrap();
    assert!(dirty.items[0].git.dirty);
    assert!(fixture
        .store
        .claim_workflow_cleanup(&dirty.id, &dirty.digest)
        .await
        .is_err());
    assert_eq!(
        std::fs::read_to_string(obstruction).unwrap(),
        "preserve this file"
    );
    fixture
        .store
        .require_workspace_outside_cleanup(&resource.identity.workspace.id)
        .await
        .unwrap();
    let mut duplicate = request(&fixture.plan.run_id, false);
    duplicate.resources.push(CleanupResourceSelection {
        workspace_id: resource.identity.workspace.id.clone(),
        remove_branch: false,
    });
    assert!(preview(&fixture.store, duplicate).await.is_err());
}
