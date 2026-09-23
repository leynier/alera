use std::path::Path;

#[path = "workspace_relocation_request_retry_tests.rs"]
mod request_retry_tests;

use chrono::Utc;
use git2::{Repository, RepositoryInitOptions, Signature};
use serde_json::json;

use super::checkout_store_tests::workspace;
use super::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceRelocation,
    WorkspaceRelocationPhase as Phase, WorkspaceTabRecord,
};
use crate::git;

async fn fixture() -> (tempfile::TempDir, RuntimeStore, WorkspaceRelocation) {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("repo");
    let mut options = RepositoryInitOptions::new();
    options.initial_head("main");
    let repo = Repository::init_opts(&path, &options).unwrap();
    repo.config()
        .unwrap()
        .set_bool("core.autocrlf", false)
        .unwrap();
    std::fs::write(path.join("tracked.txt"), "original\n").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = Signature::now("Test", "test@example.com").unwrap();
    repo.commit(Some("HEAD"), &signature, &signature, "initial", &tree, &[])
        .unwrap();
    let path = path.to_string_lossy().to_string();
    let store = RuntimeStore::open(&directory.path().join("state"))
        .await
        .unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: path.clone(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let source = store
        .insert_workspace(workspace("task", "local", &path, WorkspaceKind::Main))
        .await
        .unwrap();
    let mut destination = source.clone();
    destination.kind = WorkspaceKind::Linked;
    destination.path = directory
        .path()
        .join("linked/task")
        .to_string_lossy()
        .to_string();
    destination.branch = Some("task".into());
    let journal = WorkspaceRelocation {
        id: uuid::Uuid::new_v4().to_string(),
        source,
        destination,
        repository_path: path.clone(),
        original_branch: "main".into(),
        source_commit: git::checkout_commit(&path).unwrap(),
        replacement_branch: None,
        replacement_commit: None,
        destination_original_branch: None,
        destination_original_commit: None,
        move_changes: true,
        recovery_stash_oid: None,
        phase: Phase::Prepared,
    };
    (directory, store, journal)
}

#[tokio::test]
async fn relocation_executor_moves_the_same_task_and_returns_to_an_empty_project_checkout() {
    let (_directory, store, journal) = fixture().await;
    std::fs::write(
        Path::new(&journal.source.path).join("tracked.txt"),
        "task edit\n",
    )
    .unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "editor".into(),
            workspace_id: "task".into(),
            kind: "editor".into(),
            title: "Tracked".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"filePath": format!("{}/tracked.txt", journal.source.path)}),
        })
        .await
        .unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    let linked = store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    assert_eq!(linked.id, journal.source.id);
    assert_eq!(linked.instance_id, journal.source.instance_id);
    assert_eq!(git::current_branch(&journal.source.path).unwrap(), "main");
    assert!(git::is_worktree_clean(&journal.source.path).unwrap());
    assert_eq!(store.list_workspaces("project").await.unwrap().len(), 1);
    assert_eq!(
        std::fs::read_to_string(Path::new(&linked.path).join("tracked.txt")).unwrap(),
        "task edit\n"
    );

    let mut returning = journal.clone();
    returning.id = uuid::Uuid::new_v4().to_string();
    returning.source = linked.clone();
    returning.destination = Workspace {
        path: store
            .find_project_checkout("project", "local")
            .await
            .unwrap()
            .unwrap()
            .path,
        kind: WorkspaceKind::Main,
        ..linked.clone()
    };
    returning.original_branch = "task".into();
    returning.destination_original_branch = Some("main".into());
    returning.destination_original_commit = Some(journal.source_commit.clone());
    store.begin_workspace_relocation(&returning).await.unwrap();
    let returned = store
        .resume_local_workspace_relocation(&returning.id, || Ok(()))
        .await
        .unwrap();
    assert_eq!(returned.id, journal.source.id);
    assert_eq!(returned.instance_id, journal.source.instance_id);
    assert_eq!(
        std::fs::canonicalize(&returned.path).unwrap(),
        std::fs::canonicalize(&journal.source.path).unwrap()
    );
    assert!(!Path::new(&linked.path).exists());
    assert!(git::branch_exists(&returned.path, "task").unwrap());
    assert_eq!(
        std::fs::read_to_string(Path::new(&returned.path).join("tracked.txt")).unwrap(),
        "task edit\n"
    );
    assert_eq!(
        store
            .find_workspace_tab("editor")
            .await
            .unwrap()
            .unwrap()
            .payload["filePath"],
        Path::new(&returned.path)
            .join("tracked.txt")
            .to_str()
            .unwrap()
    );
}

#[tokio::test]
async fn relocation_executor_leaves_shared_changes_when_requested_and_preserves_siblings() {
    let (_directory, store, mut journal) = fixture().await;
    journal.move_changes = false;
    let sibling = store
        .insert_workspace(workspace(
            "sibling",
            "local",
            &journal.source.path,
            WorkspaceKind::Main,
        ))
        .await
        .unwrap();
    std::fs::write(
        Path::new(&journal.source.path).join("shared.txt"),
        "leave here",
    )
    .unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    let linked = store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    assert_eq!(
        store.find_workspace("sibling").await.unwrap(),
        Some(sibling)
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&journal.source.path).join("shared.txt")).unwrap(),
        "leave here"
    );
    assert!(!Path::new(&linked.path).join("shared.txt").exists());
    assert_eq!(git::current_branch(&journal.source.path).unwrap(), "main");
}

#[tokio::test]
async fn relocation_executor_moves_current_branch_only_with_the_recorded_replacement() {
    let (_directory, store, mut journal) = fixture().await;
    git::create_and_checkout_branch(&journal.source.path, "feature").unwrap();
    journal.original_branch = "feature".into();
    journal.destination.branch = Some("feature".into());
    journal.replacement_branch = Some("main".into());
    journal.replacement_commit = Some(journal.source_commit.clone());
    std::fs::write(
        Path::new(&journal.source.path).join("task.txt"),
        "transfer me",
    )
    .unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    let linked = store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    assert_eq!(linked.id, journal.source.id);
    assert_eq!(git::current_branch(&journal.source.path).unwrap(), "main");
    assert_eq!(git::current_branch(&linked.path).unwrap(), "feature");
    assert_eq!(
        std::fs::read_to_string(Path::new(&linked.path).join("task.txt")).unwrap(),
        "transfer me"
    );
}

#[tokio::test]
async fn relocation_executor_recovers_a_completed_apply_after_restart() {
    let (directory, store, journal) = fixture().await;
    std::fs::write(
        Path::new(&journal.source.path).join("task.txt"),
        "already transferred",
    )
    .unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    let mut recovery = store
        .advance_workspace_relocation(&journal, Phase::Snapshotting, None)
        .await
        .unwrap();
    let snapshot = git::stash_for_workspace_relocation(&journal.source.path, &journal.id).unwrap();
    recovery = store
        .advance_workspace_relocation(&recovery, Phase::Snapshotted, snapshot.clone())
        .await
        .unwrap();
    recovery = store
        .advance_workspace_relocation(&recovery, Phase::PreparingDestination, snapshot.clone())
        .await
        .unwrap();
    git::create_workspace_relocation_worktree(
        &journal.repository_path,
        &journal.id,
        &journal.destination.path,
        "task",
        &journal.source_commit,
        false,
    )
    .unwrap();
    recovery = store
        .advance_workspace_relocation(&recovery, Phase::DestinationReady, snapshot.clone())
        .await
        .unwrap();
    store
        .advance_workspace_relocation(&recovery, Phase::ApplyingChanges, snapshot.clone())
        .await
        .unwrap();
    git::apply_workspace_relocation_snapshot(
        &journal.destination.path,
        snapshot.as_deref().unwrap(),
    )
    .unwrap();
    assert_eq!(
        store.find_workspace("task").await.unwrap().unwrap().path,
        journal.source.path
    );
    let reopened = RuntimeStore::open(&directory.path().join("state"))
        .await
        .unwrap();
    let moved = reopened
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    assert_eq!(moved.path, journal.destination.path);
    assert_eq!(
        std::fs::read_to_string(Path::new(&moved.path).join("task.txt")).unwrap(),
        "already transferred"
    );
    assert_eq!(
        reopened
            .find_workspace_relocation(&journal.id)
            .await
            .unwrap()
            .unwrap()
            .recovery_stash_oid,
        snapshot
    );
}

#[tokio::test]
async fn relocation_executor_retries_interruption_at_each_persisted_boundary() {
    use std::cell::Cell;

    for permitted_checks in 1..=18 {
        let (_directory, store, journal) = fixture().await;
        std::fs::write(
            Path::new(&journal.source.path).join("pending.txt"),
            "never lose this",
        )
        .unwrap();
        store.begin_workspace_relocation(&journal).await.unwrap();
        let checks = Cell::new(0);
        let _ = store
            .resume_local_workspace_relocation(&journal.id, || {
                checks.set(checks.get() + 1);
                if checks.get() > permitted_checks {
                    anyhow::bail!("Simulated disconnection");
                }
                Ok(())
            })
            .await;
        let moved = store
            .resume_local_workspace_relocation(&journal.id, || Ok(()))
            .await
            .unwrap_or_else(|error| panic!("boundary {permitted_checks}: {error:#}"));
        assert_eq!(moved.id, journal.source.id);
        assert_eq!(moved.instance_id, journal.source.instance_id);
        assert_eq!(
            std::fs::read_to_string(Path::new(&moved.path).join("pending.txt")).unwrap(),
            "never lose this"
        );
        assert_eq!(git::current_branch(&journal.source.path).unwrap(), "main");
    }
}

#[tokio::test]
async fn relocation_preparation_records_live_state_and_reuses_only_matching_intent() {
    let (_directory, store, template) = fixture().await;
    let intent = super::WorkspaceRelocationIntent {
        workspace_id: template.source.id.clone(),
        to_project_checkout: false,
        destination_path: Some(template.destination.path.clone()),
        branch: Some("task".into()),
        replacement_branch: None,
        move_changes: true,
        shared_impact_confirmed: true,
    };
    let journal = store
        .prepare_local_workspace_relocation(intent.clone())
        .await
        .unwrap();
    assert_eq!(journal.source_commit, template.source_commit);
    assert_eq!(journal.original_branch, "main");
    assert!(!Path::new(&journal.destination.path).exists());
    assert_eq!(
        store.find_workspace("task").await.unwrap(),
        Some(template.source)
    );
    assert_eq!(
        store
            .prepare_local_workspace_relocation(intent.clone())
            .await
            .unwrap()
            .id,
        journal.id
    );
    let mut incompatible = intent.clone();
    incompatible.move_changes = false;
    assert!(store
        .prepare_local_workspace_relocation(incompatible)
        .await
        .is_err());
    store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    let returning = store
        .prepare_local_workspace_relocation(super::WorkspaceRelocationIntent {
            workspace_id: "task".into(),
            to_project_checkout: true,
            destination_path: None,
            branch: None,
            replacement_branch: None,
            move_changes: true,
            shared_impact_confirmed: true,
        })
        .await
        .unwrap();
    assert_eq!(
        std::fs::canonicalize(&returning.destination.path).unwrap(),
        std::fs::canonicalize(&template.repository_path).unwrap()
    );
    assert_eq!(
        returning.destination_original_branch.as_deref(),
        Some("main")
    );
}

#[tokio::test]
async fn invalid_relocation_choices_do_not_stash_or_persist_an_unusable_intent() {
    let (_directory, store, template) = fixture().await;
    std::fs::write(
        Path::new(&template.source.path).join("pending.txt"),
        "keep here",
    )
    .unwrap();
    let mut intent = super::WorkspaceRelocationIntent {
        workspace_id: template.source.id.clone(),
        to_project_checkout: false,
        destination_path: Some(template.destination.path.clone()),
        branch: Some("task".into()),
        replacement_branch: None,
        move_changes: true,
        shared_impact_confirmed: false,
    };
    assert!(store
        .prepare_local_workspace_relocation(intent.clone())
        .await
        .is_err());
    intent.shared_impact_confirmed = true;
    intent.branch = Some("main".into());
    assert!(store
        .prepare_local_workspace_relocation(intent.clone())
        .await
        .is_err());
    intent.branch = Some("task".into());
    intent.destination_path = Some("relative/path".into());
    assert!(store
        .prepare_local_workspace_relocation(intent)
        .await
        .is_err());
    assert!(store
        .active_workspace_relocation("project", "local")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        std::fs::read_to_string(Path::new(&template.source.path).join("pending.txt")).unwrap(),
        "keep here"
    );
    assert_eq!(git::current_branch(&template.source.path).unwrap(), "main");
}

#[tokio::test]
async fn relocation_executor_preserves_the_journal_when_safety_verification_fails() {
    let (_directory, store, journal) = fixture().await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    assert!(store
        .resume_local_workspace_relocation(&journal.id, || anyhow::bail!("Editor disconnected"))
        .await
        .is_err());
    assert_eq!(
        store.find_workspace("task").await.unwrap(),
        Some(journal.source.clone())
    );
    assert!(!Path::new(&journal.destination.path).exists());
    assert_eq!(
        store
            .find_workspace_relocation(&journal.id)
            .await
            .unwrap()
            .unwrap()
            .phase,
        Phase::Prepared
    );
    store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
}
