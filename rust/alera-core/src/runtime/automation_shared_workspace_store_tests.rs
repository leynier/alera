use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};
use crate::runtime::{AutomationOccurrence, AutomationRunTrigger, AutomationTarget};

async fn run(store: &RuntimeStore, host_id: &str) -> AutomationRun {
    let mut definition = super::super::tests::definition();
    definition.id = uuid::Uuid::new_v4().to_string();
    definition.slug = definition.id.clone();
    definition.project_id = Some("project".into());
    definition.target = AutomationTarget::ProjectCheckout {
        project_id: "project".into(),
        host_id: host_id.into(),
        name_template: "task".into(),
        agent_profile_id: "profile".into(),
    };
    store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: uuid::Uuid::new_v4().to_string(),
        scheduled_at: Utc::now(),
        local_time: "2026-09-12T00:00".into(),
    };
    let mut run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    store.save_automation_run(&run).await.unwrap()
}

async fn prepared() -> (tempfile::TempDir, RuntimeStore, AutomationRun) {
    let (directory, store, _) = fixture().await;
    super::super::tests::seed_profile(&store).await;
    store
        .register_project_checkout("project", "local", "/repo")
        .await
        .unwrap();
    let run = run(&store, "local").await;
    (directory, store, run)
}

#[tokio::test]
async fn empty_project_allocations_are_atomic_distinct_and_survive_restart() {
    let (directory, store, first) = prepared().await;
    assert!(store.list_workspaces("project").await.unwrap().is_empty());
    let (bound, task) = store
        .allocate_automation_shared_workspace(
            &first,
            workspace("first", "local", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    assert!(bound.owned_workspace);
    assert!(store.save_automation_run(&first).await.is_err());
    assert_eq!(bound.workspace_id.as_deref(), Some(task.id.as_str()));
    let second = run(&store, "local").await;
    store
        .allocate_automation_shared_workspace(
            &second,
            workspace("second", "local", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    let current = reopened
        .find_automation_run(&first.id)
        .await
        .unwrap()
        .unwrap();
    let (_, resumed) = reopened
        .allocate_automation_shared_workspace(
            &current,
            workspace(
                "retry-must-not-be-created",
                "local",
                "/repo",
                WorkspaceKind::Main,
            ),
        )
        .await
        .unwrap();
    assert_eq!(resumed.instance_id, task.instance_id);
    assert_eq!(reopened.list_workspaces("project").await.unwrap().len(), 2);
    assert!(resumed.parent_workspace_id.is_none());
}

#[tokio::test]
async fn allocation_rolls_back_task_and_receipt_when_run_binding_fails() {
    let (_directory, store, run) = prepared().await;
    sqlx::query("CREATE TRIGGER rejectTestAllocation BEFORE UPDATE OF dataJson ON automationRuns WHEN json_extract(NEW.dataJson, '$.ownedWorkspace') = 1 BEGIN SELECT RAISE(ABORT, 'injected persistence failure'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .allocate_automation_shared_workspace(
            &run,
            workspace("task", "local", "/repo", WorkspaceKind::Main)
        )
        .await
        .is_err());
    assert!(store.list_workspaces("project").await.unwrap().is_empty());
    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM automationSharedWorkspaceAllocations")
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(count, 0);
    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM workspaceCheckoutBindings WHERE workspaceId = 'task'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(count, 0);
    assert!(
        !store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .owned_workspace
    );
}

#[tokio::test]
async fn racing_allocations_bind_only_one_task_and_reject_stale_snapshots() {
    let (_directory, store, run) = prepared().await;
    let (first, second) = tokio::join!(
        store.allocate_automation_shared_workspace(
            &run,
            workspace("one", "local", "/repo", WorkspaceKind::Main)
        ),
        store.allocate_automation_shared_workspace(
            &run,
            workspace("two", "local", "/repo", WorkspaceKind::Main)
        ),
    );
    assert_eq!(usize::from(first.is_ok()) + usize::from(second.is_ok()), 1);
    assert_eq!(store.list_workspaces("project").await.unwrap().len(), 1);
    assert!(store
        .allocate_automation_shared_workspace(
            &run,
            workspace("stale", "local", "/repo", WorkspaceKind::Main)
        )
        .await
        .is_err());
}

#[tokio::test]
async fn removed_or_replaced_allocation_is_never_recreated_or_adopted() {
    let (_directory, store, run) = prepared().await;
    let (bound, task) = store
        .allocate_automation_shared_workspace(
            &run,
            workspace("owned", "local", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    store.remove_workspace(&task.id, true).await.unwrap();
    let candidate = workspace("replacement", "local", "/repo", WorkspaceKind::Main);
    assert!(store
        .allocate_automation_shared_workspace(&bound, candidate.clone())
        .await
        .is_err());
    assert!(store.list_workspaces("project").await.unwrap().is_empty());
    let mut replacement = task.clone();
    replacement.instance_id = "other-instance".into();
    store.insert_workspace(replacement).await.unwrap();
    assert!(store
        .allocate_automation_shared_workspace(&bound, candidate)
        .await
        .is_err());
    assert_eq!(
        store
            .find_workspace(&task.id)
            .await
            .unwrap()
            .unwrap()
            .instance_id,
        "other-instance"
    );
}

#[tokio::test]
async fn existing_task_and_unregistered_hosts_are_preserved() {
    let (_directory, store, initial) = prepared().await;
    let task = workspace("existing", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(task.clone()).await.unwrap();
    assert!(store
        .allocate_automation_shared_workspace(&initial, task.clone())
        .await
        .is_err());
    assert!(store
        .allocate_automation_shared_workspace(
            &initial,
            workspace("remote", "ssh", "/repo", WorkspaceKind::Main)
        )
        .await
        .is_err());
    assert!(
        !store
            .find_automation_run(&initial.id)
            .await
            .unwrap()
            .unwrap()
            .owned_workspace
    );
    assert_eq!(store.list_workspaces("project").await.unwrap().len(), 1);
    store
        .register_project_checkout("project", "ssh", "/repo")
        .await
        .unwrap();
    let remote_run = run(&store, "ssh").await;
    let (_, remote) = store
        .allocate_automation_shared_workspace(
            &remote_run,
            workspace("remote", "ssh", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    assert_eq!(remote.host_id, "ssh");
    assert_eq!(
        store
            .find_workspace(&task.id)
            .await
            .unwrap()
            .unwrap()
            .instance_id,
        task.instance_id
    );
}

#[tokio::test]
async fn cancelled_runs_and_inherited_task_state_cannot_allocate() {
    let (_directory, store, original) = prepared().await;
    let mut inherited = workspace("inherited", "local", "/repo", WorkspaceKind::Main);
    inherited.parent_workspace_id = Some("parent".into());
    assert!(store
        .allocate_automation_shared_workspace(&original, inherited)
        .await
        .is_err());
    let mut cancelled = original.clone();
    cancelled.cancel_requested_at = Some(Utc::now());
    let cancelled = store.save_automation_run(&cancelled).await.unwrap();
    for snapshot in [original, cancelled] {
        assert!(store
            .allocate_automation_shared_workspace(
                &snapshot,
                workspace("cancelled", "local", "/repo", WorkspaceKind::Main)
            )
            .await
            .is_err());
    }
    assert!(store.list_workspaces("project").await.unwrap().is_empty());
}

#[path = "automation_shared_workspace_cleanup_tests.rs"]
mod cleanup_tests;

#[path = "automation_cleanup_atomic_completion_tests.rs"]
mod atomic_completion;
