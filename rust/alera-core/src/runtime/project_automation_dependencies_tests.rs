use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};
use crate::runtime::{AutomationState, AutomationTarget, WorkspaceKind, WorkspaceTabRecord};

async fn prepared() -> (tempfile::TempDir, RuntimeStore, AutomationDefinition) {
    let (directory, store, _) = fixture().await;
    super::tests::seed_profile(&store).await;
    let mut definition = super::tests::definition();
    definition.target = AutomationTarget::ProjectCheckout {
        project_id: "project".into(),
        host_id: "local".into(),
        name_template: "task".into(),
        agent_profile_id: "profile".into(),
    };
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    store
        .approve_automation(
            &definition.id,
            definition.revision,
            definition.created_by.clone(),
        )
        .await
        .unwrap();
    let definition = store
        .set_automation_state(
            &definition.id,
            AutomationState::Paused,
            definition.created_by.clone(),
            None,
        )
        .await
        .unwrap();
    (directory, store, definition)
}

#[tokio::test]
async fn active_checkout_automation_protects_an_empty_project_after_restart() {
    let (directory, store, definition) = prepared().await;
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Active,
            definition.created_by.clone(),
            None,
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened
        .list_workspaces("project")
        .await
        .unwrap()
        .is_empty());
    let dependencies = reopened
        .project_automation_dependencies("project")
        .await
        .unwrap();
    assert_eq!(dependencies.len(), 1);
    assert!(dependencies[0].requires_pause);
    assert_eq!(dependencies[0].active_runs, 0);
    assert!(reopened
        .remove_project("project")
        .await
        .unwrap_err()
        .to_string()
        .contains(&definition.id));
    assert!(sqlx::query("DELETE FROM projects WHERE id = 'project'")
        .execute(reopened.pool())
        .await
        .is_err());
    assert!(reopened.find_project("project").await.unwrap().is_some());
}

#[tokio::test]
async fn paused_definition_still_requires_run_cancellation_and_retains_history() {
    let (_directory, store, definition) = prepared().await;
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Paused,
            definition.created_by.clone(),
            None,
        )
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "pending-run".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-09-12T00:00".into(),
    };
    let mut run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    let dependencies = store
        .project_automation_dependencies("project")
        .await
        .unwrap();
    assert_eq!(dependencies[0].active_runs, 1);
    assert!(dependencies[0].requires_pause);
    assert!(store.remove_project("project").await.is_err());
    run.status = AutomationRunStatus::Cancelled;
    run.finished_at = Some(Utc::now());
    store.save_automation_run(&run).await.unwrap();
    assert!(
        !store
            .project_automation_dependencies("project")
            .await
            .unwrap()[0]
            .requires_pause
    );
    store.remove_project("project").await.unwrap();
    assert!(store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        AutomationRunStatus::Cancelled
    );
    assert!(store
        .set_automation_state(
            &definition.id,
            AutomationState::Active,
            definition.created_by.clone(),
            None
        )
        .await
        .is_err());
    assert!(store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                key: "late-run".into(),
                ..occurrence
            },
            AutomationRunTrigger::Scheduled
        )
        .await
        .is_err());
}

#[tokio::test]
async fn existing_workspace_dependency_is_checked_before_child_records_are_deleted() {
    let (_directory, store, mut definition) = prepared().await;
    store
        .insert_workspace(workspace("task", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: "task".into(),
            kind: "editor".into(),
            title: "Notes".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: serde_json::json!({"filePath":"notes.md"}),
        })
        .await
        .unwrap();
    definition.target = AutomationTarget::FreshTab {
        workspace_id: "task".into(),
        agent_profile_id: "profile".into(),
    };
    definition.state = AutomationState::Active;
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    store
        .approve_automation(&definition.id, definition.revision, definition.created_by)
        .await
        .unwrap();
    assert!(store.remove_project("project").await.is_err());
    assert!(store.find_workspace("task").await.unwrap().is_some());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_some());
}

#[tokio::test]
async fn project_removal_and_automation_activation_cannot_both_commit() {
    let (_directory, store, definition) = prepared().await;
    let (removed, activated) = tokio::join!(
        store.remove_project("project"),
        store.set_automation_state(
            &definition.id,
            AutomationState::Active,
            definition.created_by.clone(),
            None
        ),
    );
    assert_ne!(removed.is_ok(), activated.is_ok());
    if activated.is_ok() {
        assert!(store.find_project("project").await.unwrap().is_some());
    }
}
