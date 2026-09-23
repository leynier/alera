use super::*;
use crate::runtime::WorkspaceRelocationIntent;

#[tokio::test]
async fn explicit_relocation_id_recovers_a_lost_response_without_repeating_git_effects() {
    let (directory, store, template) = fixture().await;
    let intent = WorkspaceRelocationIntent {
        workspace_id: template.source.id.clone(),
        to_project_checkout: false,
        destination_path: Some(template.destination.path.clone()),
        branch: Some("task".into()),
        replacement_branch: None,
        move_changes: true,
        shared_impact_confirmed: true,
    };
    let id = uuid::Uuid::new_v4().to_string();
    let journal = store
        .prepare_local_workspace_relocation_with_id(intent.clone(), Some(id.clone()))
        .await
        .unwrap();
    assert_eq!(journal.id, id);
    assert!(store
        .prepare_local_workspace_relocation_with_id(
            intent.clone(),
            Some(uuid::Uuid::new_v4().to_string())
        )
        .await
        .is_err());
    let workspace = store
        .resume_local_workspace_relocation(&id, || Ok(()))
        .await
        .unwrap();
    let marker = Path::new(&workspace.path).join("after-completion.txt");
    std::fs::write(&marker, "changes after the response was lost").unwrap();
    let reopened = RuntimeStore::open(&directory.path().join("state"))
        .await
        .unwrap();
    let recovered = reopened
        .prepare_local_workspace_relocation_with_id(intent.clone(), Some(id.clone()))
        .await
        .unwrap();
    assert_eq!(recovered.phase, Phase::Completed);
    assert_eq!(
        reopened
            .resume_local_workspace_relocation(&id, || Ok(()))
            .await
            .unwrap(),
        workspace
    );
    assert_eq!(
        std::fs::read_to_string(marker).unwrap(),
        "changes after the response was lost"
    );
    let mut conflicting = intent.clone();
    conflicting.move_changes = false;
    assert!(reopened
        .prepare_local_workspace_relocation_with_id(conflicting, Some(id.clone()))
        .await
        .is_err());
    let returning = WorkspaceRelocationIntent {
        workspace_id: workspace.id,
        to_project_checkout: true,
        destination_path: None,
        branch: None,
        replacement_branch: None,
        move_changes: true,
        shared_impact_confirmed: true,
    };
    reopened
        .prepare_local_workspace_relocation(returning)
        .await
        .unwrap();
    assert!(reopened
        .prepare_local_workspace_relocation_with_id(intent, Some(id))
        .await
        .is_err());
}
