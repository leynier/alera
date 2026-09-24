use super::*;
use crate::runtime::{AutomationActor, AutomationCleanupPolicy};

async fn allocated(
    policy: Option<AutomationCleanupPolicy>,
) -> (
    tempfile::TempDir,
    RuntimeStore,
    AutomationRun,
    Workspace,
    AutomationActor,
) {
    let (directory, store, run) = prepared().await;
    let mut definition = store
        .find_automation(&run.automation_id)
        .await
        .unwrap()
        .unwrap();
    definition.cleanup_policy = policy;
    let actor = definition.modified_by.clone();
    store
        .upsert_automation(definition, actor.clone())
        .await
        .unwrap();
    let (run, workspace) = store
        .allocate_automation_shared_workspace(
            &run,
            workspace("owned", "local", "/repo", WorkspaceKind::Main),
        )
        .await
        .unwrap();
    (directory, store, run, workspace, actor)
}

#[tokio::test]
async fn successful_completion_and_cleanup_intent_commit_together_and_survive_restart() {
    let (directory, store, run, workspace, actor) =
        allocated(Some(AutomationCleanupPolicy::OnSuccess)).await;
    let saved = store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("Finished".into()),
            None,
            actor.clone(),
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    let attempt = reopened
        .claim_automation_shared_cleanup(&run.id, Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(attempt.run, saved);
    assert_eq!(attempt.workspace.instance_id, workspace.instance_id);
    reopened
        .require_automation_shared_workspace_cleanup(&attempt.run, &attempt.workspace)
        .await
        .unwrap();
    assert!(reopened
        .find_workspace(&workspace.id)
        .await
        .unwrap()
        .is_some());
    let repeated = reopened
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("Retry".into()),
            None,
            actor,
        )
        .await
        .unwrap();
    assert_eq!(repeated, saved);
    assert!(reopened
        .claim_automation_shared_cleanup(&run.id, Utc::now())
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn failed_intent_insert_rolls_back_success_and_allows_completion_retry() {
    let (_directory, store, run, workspace, actor) =
        allocated(Some(AutomationCleanupPolicy::OnSuccess)).await;
    sqlx::query("CREATE TRIGGER rejectCleanupIntent BEFORE INSERT ON automationSharedCleanupIntents BEGIN SELECT RAISE(ABORT, 'injected intent failure'); END")
        .execute(store.pool()).await.unwrap();
    let error = store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("Finished".into()),
            None,
            actor.clone(),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("injected intent failure"));
    let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
    assert_eq!(current.status, AutomationRunStatus::Dispatching);
    assert!(current.finished_at.is_none());
    assert!(store
        .due_automation_shared_cleanups(Utc::now())
        .await
        .unwrap()
        .is_empty());
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
    sqlx::query("DROP TRIGGER rejectCleanupIntent")
        .execute(store.pool())
        .await
        .unwrap();
    store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("Finished".into()),
            None,
            actor,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .due_automation_shared_cleanups(Utc::now())
            .await
            .unwrap(),
        vec![run.id]
    );
}

#[tokio::test]
async fn preserve_policy_and_unsuccessful_runs_do_not_schedule_cleanup() {
    for (policy, status) in [
        (None, AutomationRunStatus::Success),
        (
            Some(AutomationCleanupPolicy::OnSuccess),
            AutomationRunStatus::Failure,
        ),
        (
            Some(AutomationCleanupPolicy::OnSuccess),
            AutomationRunStatus::Blocked,
        ),
    ] {
        let (_directory, store, run, workspace, actor) = allocated(policy).await;
        store
            .complete_automation_run(&run.id, status, Some("Finished".into()), None, actor)
            .await
            .unwrap();
        assert!(store
            .due_automation_shared_cleanups(Utc::now())
            .await
            .unwrap()
            .is_empty());
        assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
    }
}

#[tokio::test]
async fn completion_journals_original_allocation_without_adopting_user_changes() {
    let (_directory, store, run, mut workspace, actor) =
        allocated(Some(AutomationCleanupPolicy::OnSuccess)).await;
    let original_name = workspace.name.clone();
    workspace.name = "User task".into();
    store.upsert_workspace(workspace.clone()).await.unwrap();
    store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("Finished".into()),
            None,
            actor,
        )
        .await
        .unwrap();
    let attempt = store
        .claim_automation_shared_cleanup(&run.id, Utc::now())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(attempt.workspace.name, original_name);
    assert!(store
        .require_automation_shared_workspace_cleanup(&attempt.run, &attempt.workspace)
        .await
        .is_err());
    assert_eq!(
        store
            .find_workspace(&workspace.id)
            .await
            .unwrap()
            .unwrap()
            .name,
        "User task"
    );
}
