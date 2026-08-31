use alera_core::runtime::*;
use alera_core::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};
use serde_json::json;

use super::*;

mod fixture;
mod regressions;
mod review_regressions;
use fixture::Fixture;

#[tokio::test]
async fn workflow_worktrees_freeze_source_isolate_attempts_and_replay_requests() {
    let fixture = Fixture::new("").await;
    std::fs::write(fixture.source.join("shared.txt"), "uncommitted source").unwrap();
    let integration = fixture.integration().await;
    assert_eq!(
        std::fs::read_to_string(Path::new(&integration.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "initial"
    );
    let first = fixture.task("fix").await;
    let second = fixture.task("other").await;
    assert_eq!(first.phase, Phase::Ready, "{first:?}");
    assert_eq!(second.phase, Phase::Ready, "{second:?}");
    assert_ne!(first.identity.workspace.id, second.identity.workspace.id);
    assert_eq!(first.identity.owner_workspace_id, "owner");
    assert_ne!(
        first.identity.workspace.id,
        first.identity.owner_workspace_id
    );
    std::fs::write(
        Path::new(&first.identity.workspace.path).join("shared.txt"),
        "first worker",
    )
    .unwrap();
    std::fs::write(
        Path::new(&second.identity.workspace.path).join("shared.txt"),
        "second worker",
    )
    .unwrap();
    let replay = fixture.task("fix").await;
    assert_eq!(first.identity.workspace.id, replay.identity.workspace.id);
    assert_eq!(
        std::fs::read_to_string(fixture.source.join("shared.txt")).unwrap(),
        "uncommitted source"
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&first.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "first worker"
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&second.identity.workspace.path).join("shared.txt"))
            .unwrap(),
        "second worker"
    );
    assert!(fixture.request(Some("verify"), None).await.is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationDispatchContexts")
        .fetch_one(fixture.store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    let owner: String =
        sqlx::query_scalar("SELECT workspace_id FROM orchestrationTasks WHERE id = ?")
            .bind(fixture.task_id("fix").await)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!(owner, "owner");
}

#[tokio::test]
async fn workflow_worktrees_failed_setup_retains_report_and_retry_is_fresh() {
    let fixture = Fixture::new("exit 7").await;
    let integration = fixture.integration().await;
    assert_eq!(integration.phase, Phase::Ready);
    assert!(integration.setup_report.is_none());
    let first = fixture.task("fix").await;
    assert_eq!(first.phase, Phase::Attention);
    assert_eq!(
        first
            .setup_report
            .as_ref()
            .unwrap()
            .steps
            .last()
            .unwrap()
            .exit_code,
        Some(7)
    );
    std::fs::write(
        Path::new(&first.identity.workspace.path).join("retained.txt"),
        "do not lose",
    )
    .unwrap();
    let second = fixture
        .request(Some("fix"), Some(&first.identity.workspace.id))
        .await
        .unwrap();
    assert_eq!(second.identity.attempt, 2);
    assert_ne!(first.identity.workspace.id, second.identity.workspace.id);
    assert_eq!(
        std::fs::read_to_string(Path::new(&first.identity.workspace.path).join("retained.txt"))
            .unwrap(),
        "do not lose"
    );
    assert!(crate::worktree_setup::run_workspace_setup(
        &fixture.store,
        &first.identity.workspace.id,
        false
    )
    .await
    .is_err());
    assert!(validate_managed_workspace_removal(
        &fixture.store,
        &ManagedWorkspaceRemoveRequest {
            id: first.identity.workspace.id.clone(),
            delete_branch: Some(true),
            active_workspace_id: None,
            close_sessions: true,
        }
    )
    .await
    .is_err());
}

#[tokio::test]
async fn workflow_worktrees_reconcile_git_before_persistence_and_interrupted_setup() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    let prepared = fixture.reserve("fix").await;
    let id = &prepared.identity.workspace.id;
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Reserved, Phase::Creating, None, None)
        .await
        .unwrap();
    let identity = &prepared.identity;
    core_git::ensure_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        id,
    )
    .unwrap();
    assert!(fixture.store.find_workspace(id).await.unwrap().is_none());
    let reopened = RuntimeStore::open(&fixture.runtime).await.unwrap();
    recovery::reconcile(&reopened, &fixture.runtime)
        .await
        .unwrap();
    let recovered = reopened.workflow_workspace(id).await.unwrap();
    assert_eq!(recovered.phase, Phase::Ready, "{recovered:?}");
    assert_eq!(recovered.identity.workspace.id, *id);
    assert_ne!(integration.identity.workspace.id, *id);
    let interrupted = fixture.reserve("other").await;
    let id = &interrupted.identity.workspace.id;
    let identity = &interrupted.identity;
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Reserved, Phase::Creating, None, None)
        .await
        .unwrap();
    core_git::ensure_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        id,
    )
    .unwrap();
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Creating, Phase::Created, None, None)
        .await
        .unwrap();
    fixture
        .store
        .transition_workflow_workspace(id, 1, Phase::Created, Phase::SetupRunning, None, None)
        .await
        .unwrap();
    recovery::reconcile(&reopened, &fixture.runtime)
        .await
        .unwrap();
    let failed = reopened.workflow_workspace(id).await.unwrap();
    assert_eq!(failed.phase, Phase::Attention);
    assert!(failed.error.unwrap().contains("will not run again"));
}

#[tokio::test]
async fn workflow_worktrees_reject_foreign_branches_and_preserve_partial_resources() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    let record = fixture.reserve("fix").await;
    let identity = &record.identity;
    let repo = git2::Repository::open(&identity.repo_path).unwrap();
    repo.branch(
        identity.workspace.branch.as_deref().unwrap(),
        &repo
            .find_commit(git2::Oid::from_str(&identity.base_sha).unwrap())
            .unwrap(),
        false,
    )
    .unwrap();
    let result = resume(&fixture.store, &fixture.runtime, &identity.workspace.id, 1)
        .await
        .unwrap();
    assert_eq!(result.phase, Phase::Attention);
    assert!(!Path::new(&identity.workspace.path).exists());
    assert!(repo
        .find_branch(
            identity.workspace.branch.as_deref().unwrap(),
            git2::BranchType::Local
        )
        .is_ok());
}

#[tokio::test]
async fn workflow_worktrees_stale_replay_does_not_poison_ready_integration() {
    let fixture = Fixture::new("").await;
    let integration = fixture.integration().await;
    assert!(resume(
        &fixture.store,
        &fixture.runtime,
        &integration.identity.workspace.id,
        99
    )
    .await
    .is_err());
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&integration.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        Phase::Ready
    );
    let lock = resource_lock(&fixture.runtime, &integration.identity.workspace.id).unwrap();
    assert!(resume(
        &fixture.store,
        &fixture.runtime,
        &integration.identity.workspace.id,
        1
    )
    .await
    .is_err());
    drop(lock);
    assert_eq!(fixture.integration().await.phase, Phase::Ready);
}
