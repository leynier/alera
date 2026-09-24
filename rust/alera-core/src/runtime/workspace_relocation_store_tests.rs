use chrono::Utc;
use serde_json::json;

#[path = "checkout_relocation_reservations_tests.rs"]
mod reservation_tests;

#[path = "relocation_setup_recovery_tests.rs"]
mod setup_recovery_tests;

use super::checkout_store_tests::{fixture, workspace};
use super::{
    RuntimeStore, WorkbenchLayoutRecord, WorkspaceKind, WorkspaceRelocation,
    WorkspaceRelocationPhase as Phase, WorkspaceTabRecord,
};

async fn prepared(store: &RuntimeStore) -> WorkspaceRelocation {
    let source = store
        .insert_workspace(workspace("task", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    let mut destination = source.clone();
    destination.kind = WorkspaceKind::Linked;
    destination.path = "/worktrees/task".into();
    destination.branch = Some("topic".into());
    WorkspaceRelocation {
        id: "relocation".into(),
        source,
        destination,
        repository_path: "/repo".into(),
        original_branch: "main".into(),
        source_commit: "1111111111111111111111111111111111111111".into(),
        replacement_branch: None,
        replacement_commit: None,
        destination_original_branch: None,
        destination_original_commit: None,
        move_changes: true,
        recovery_stash_oid: None,
        phase: Phase::Prepared,
    }
}

async fn ready(store: &RuntimeStore, mut journal: WorkspaceRelocation) -> WorkspaceRelocation {
    for phase in [
        Phase::Snapshotting,
        Phase::Snapshotted,
        Phase::PreparingDestination,
        Phase::DestinationReady,
        Phase::ApplyingChanges,
        Phase::ChangesApplied,
    ] {
        journal = store
            .advance_workspace_relocation(&journal, phase, None)
            .await
            .unwrap();
    }
    journal
}

#[tokio::test]
async fn cancellation_winning_before_result_commit_cannot_be_reported_as_success() {
    let (_directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let receipt = store
        .prepare_relocation_setup(&journal.id, &super::ProjectConfig::default())
        .await
        .unwrap();
    let ready = ready(&store, journal).await;
    store.commit_workspace_relocation(&ready).await.unwrap();
    let committed = store
        .find_workspace_relocation(&ready.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    let claimed = store.claim_relocation_setup(&receipt).await.unwrap();
    let attempt = claimed.attempt_id.as_deref().unwrap();
    store
        .request_relocation_setup_cancellation("task", &ready.id, attempt)
        .await
        .unwrap();
    let report = store
        .finish_relocation_setup(&claimed, &super::WorktreeSetupReport::empty())
        .await
        .unwrap();
    assert!(report
        .steps
        .iter()
        .any(|step| !step.succeeded && step.label == "Setup Cancellation"));
    assert_eq!(
        store
            .find_relocation_setup(&ready.id)
            .await
            .unwrap()
            .unwrap()
            .report,
        Some(report)
    );
    assert!(store
        .request_relocation_setup_cancellation("task", &ready.id, attempt)
        .await
        .is_err());
}

#[tokio::test]
async fn setup_receipt_pins_recipe_and_does_not_repeat_an_uncertain_attempt_after_restart() {
    let (directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let mut config = super::ProjectConfig::default();
    config.worktree.setup.push("original command".into());
    let receipt = store
        .prepare_relocation_setup(&journal.id, &config)
        .await
        .unwrap();
    assert!(store.claim_relocation_setup(&receipt).await.is_err());
    config.worktree.setup = vec!["changed command".into()];
    assert_eq!(
        store
            .prepare_relocation_setup(&journal.id, &config)
            .await
            .unwrap(),
        receipt
    );
    let ready = ready(&store, journal).await;
    store.commit_workspace_relocation(&ready).await.unwrap();
    let committed = store
        .find_workspace_relocation(&ready.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    let claimed = store.claim_relocation_setup(&receipt).await.unwrap();
    let starting = store
        .begin_setup_root_process(&claimed, 0, "test", Some("boot-one"))
        .await
        .unwrap();
    assert!(store
        .begin_setup_root_process(&claimed, 0, "test", Some("boot-one"))
        .await
        .is_err());
    assert!(store
        .finish_relocation_setup(&claimed, &super::WorktreeSetupReport::empty())
        .await
        .is_err());
    let started = super::RelocationSetupProcess {
        pid: Some(123),
        start_marker: Some(456),
        phase: super::SetupRootProcessPhase::Started,
        ..starting.clone()
    };
    store
        .update_setup_root_process(&claimed, &starting, &started)
        .await
        .unwrap();
    let descendant = store
        .record_setup_descendant(&claimed, &started, 124, 457)
        .await
        .unwrap();
    assert!(store
        .update_setup_root_process(&claimed, &starting, &started)
        .await
        .is_err());
    assert!(store.validate_workspace_setup_idle("task").await.is_err());
    let mut moved = store.find_workspace("task").await.unwrap().unwrap();
    moved.path = "/worktrees/unsafe-move".into();
    assert!(store.upsert_workspace(moved).await.is_err());
    assert!(store.claim_relocation_setup(&receipt).await.is_err());
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened.find_relocation_setup(&ready.id).await.unwrap(),
        Some(claimed.clone())
    );
    let recovery = reopened
        .list_workspace_relocation_recovery("task", 20)
        .await
        .unwrap();
    assert_eq!(recovery.len(), 1);
    assert_eq!(recovery[0].relocation.phase, Phase::Completed);
    assert_eq!(recovery[0].setup, Some(claimed.clone()));
    assert_eq!(recovery[0].setup_root_processes, vec![started.clone()]);
    assert!(reopened
        .list_workspace_relocation_recovery("different-task", 20)
        .await
        .unwrap()
        .is_empty());
    assert!(reopened.claim_relocation_setup(&claimed).await.is_err());
    let report = super::WorktreeSetupReport::empty();
    assert!(reopened
        .finish_relocation_setup(&claimed, &report)
        .await
        .is_err());
    let exited = super::RelocationSetupProcess {
        phase: super::SetupRootProcessPhase::RootExitedOutputPending,
        ..started.clone()
    };
    let mut different_boot = exited.clone();
    different_boot.boot_id = Some("different boot".into());
    assert!(reopened
        .update_setup_root_process(&claimed, &started, &different_boot)
        .await
        .is_err());
    reopened
        .update_setup_root_process(&claimed, &started, &exited)
        .await
        .unwrap();
    assert!(reopened
        .finish_relocation_setup(&claimed, &report)
        .await
        .is_err());
    reopened
        .update_setup_root_process(
            &claimed,
            &exited,
            &super::RelocationSetupProcess {
                phase: super::SetupRootProcessPhase::RootExited,
                ..exited.clone()
            },
        )
        .await
        .unwrap();
    assert!(reopened
        .finish_relocation_setup(&claimed, &report)
        .await
        .is_err());
    reopened
        .verify_setup_descendant_exit(&claimed, &descendant)
        .await
        .unwrap();
    let mut stale = claimed.clone();
    stale.attempt_id = Some("different attempt".into());
    assert!(reopened
        .finish_relocation_setup(&stale, &report)
        .await
        .is_err());
    reopened
        .finish_relocation_setup(&claimed, &report)
        .await
        .unwrap();
    reopened
        .validate_workspace_setup_idle("task")
        .await
        .unwrap();
    assert!(reopened
        .finish_relocation_setup(&claimed, &report)
        .await
        .is_err());
    assert_eq!(
        reopened
            .find_relocation_setup(&ready.id)
            .await
            .unwrap()
            .unwrap()
            .report,
        Some(report)
    );
}

#[tokio::test]
async fn setup_receipt_rejects_a_task_that_moved_again() {
    let (_directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let receipt = store
        .prepare_relocation_setup(&journal.id, &super::ProjectConfig::default())
        .await
        .unwrap();
    let ready = ready(&store, journal).await;
    store.commit_workspace_relocation(&ready).await.unwrap();
    let committed = store
        .find_workspace_relocation(&ready.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    let mut task = store.find_workspace("task").await.unwrap().unwrap();
    task.path = "/worktrees/elsewhere".into();
    store.upsert_workspace(task).await.unwrap();
    assert!(store.claim_relocation_setup(&receipt).await.is_err());
    assert!(store
        .find_relocation_setup(&ready.id)
        .await
        .unwrap()
        .unwrap()
        .attempt_id
        .is_none());
}

#[tokio::test]
async fn relocation_preserves_identity_organization_and_history_across_restart() {
    let (directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    let sibling = store
        .insert_workspace(workspace("sibling", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    let now = Utc::now();
    store.upsert_workspace_tab(WorkspaceTabRecord {
        id: "editor".into(), workspace_id: "task".into(), kind: "editor".into(), title: "Notes".into(),
        created_at: now, updated_at: now,
        payload: json!({"filePath": "/repo/notes.md", "terminalSessionId": "session", "outside": "/repo/untouched"}),
    }).await.unwrap();
    let layout = WorkbenchLayoutRecord {
        workspace_id: "task".into(),
        data: json!({"tabIds": ["editor"]}),
    };
    store.upsert_workbench_layout(layout.clone()).await.unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    assert_eq!(
        store.find_workspace("task").await.unwrap(),
        Some(journal.source.clone())
    );
    assert!(store.commit_workspace_relocation(&journal).await.is_err());
    let ready = ready(&store, journal).await;
    let mut renamed = store.find_workspace("task").await.unwrap().unwrap();
    renamed.name = "Renamed While Preparing".into();
    store.upsert_workspace(renamed).await.unwrap();
    let moved = store.commit_workspace_relocation(&ready).await.unwrap();
    assert_eq!(moved.id, ready.source.id);
    assert_eq!(moved.instance_id, ready.source.instance_id);
    assert_eq!(moved.created_at, ready.source.created_at);
    assert_eq!(moved.name, "Renamed While Preparing");
    assert_eq!(moved.path, "/worktrees/task");
    assert_eq!(
        store.find_workspace("sibling").await.unwrap(),
        Some(sibling)
    );
    assert_eq!(
        store
            .find_workbench_layout("task")
            .await
            .unwrap()
            .unwrap()
            .data,
        layout.data
    );
    let editor = store.find_workspace_tab("editor").await.unwrap().unwrap();
    assert_eq!(editor.workspace_id, "task");
    assert_eq!(editor.payload["filePath"], "/worktrees/task/notes.md");
    assert_eq!(editor.payload["outside"], "/repo/untouched");
    assert_eq!(editor.payload["terminalSessionId"], "session");
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    let committed = reopened
        .active_workspace_relocation("project", "local")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(committed.phase, Phase::Committed);
    assert_eq!(reopened.find_workspace("task").await.unwrap(), Some(moved));
    reopened
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    assert!(reopened
        .active_workspace_relocation("project", "local")
        .await
        .unwrap()
        .is_none());
    assert!(reopened
        .find_workspace_relocation("relocation")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn competing_and_stale_relocations_cannot_replace_recovery_state() {
    let (_directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let mut competing = journal.clone();
    competing.id = "other".into();
    assert!(store.begin_workspace_relocation(&competing).await.is_err());
    let snapshotting = store
        .advance_workspace_relocation(&journal, Phase::Snapshotting, None)
        .await
        .unwrap();
    assert!(store
        .advance_workspace_relocation(&journal, Phase::Snapshotting, None)
        .await
        .is_err());
    let stashed = store
        .advance_workspace_relocation(
            &snapshotting,
            Phase::Snapshotted,
            Some("immutable-oid".into()),
        )
        .await
        .unwrap();
    assert!(store
        .advance_workspace_relocation(&stashed, Phase::PreparingDestination, None)
        .await
        .is_err());
    assert_eq!(
        store
            .find_workspace_relocation(&journal.id)
            .await
            .unwrap()
            .unwrap()
            .recovery_stash_oid
            .as_deref(),
        Some("immutable-oid")
    );
}

#[tokio::test]
async fn unfinished_relocation_reserves_identity_and_location_against_ordinary_writes() {
    let (_directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let now = Utc::now();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "editor".into(),
            workspace_id: "task".into(),
            kind: "editor".into(),
            title: "Notes".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"filePath": "/repo/notes.md"}),
        })
        .await
        .unwrap();
    assert!(store.remove_workspace("task", true).await.is_err());
    assert!(store.find_workspace_tab("editor").await.unwrap().is_some());
    assert!(store
        .upsert_workspace(journal.destination.clone())
        .await
        .is_err());
    let mut changed = journal.source.clone();
    changed.instance_id = "replacement".into();
    assert!(store.upsert_workspace(changed).await.is_err());
    let mut retired = journal.source.clone();
    retired.status = super::WorkspaceStatus::Removed;
    assert!(store.upsert_workspace(retired).await.is_err());
    assert_eq!(
        store.find_workspace("task").await.unwrap(),
        Some(journal.source.clone())
    );
    let ready = ready(&store, journal).await;
    store.commit_workspace_relocation(&ready).await.unwrap();
    assert!(store.remove_workspace("task", true).await.is_err());
    let committed = store
        .find_workspace_relocation(&ready.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    store.remove_workspace("task", true).await.unwrap();
}

#[tokio::test]
async fn invalid_tab_payload_rolls_back_location_binding_and_journal_together() {
    let (_directory, store, _) = fixture().await;
    let journal = prepared(&store).await;
    let original = journal.source.clone();
    let binding = store.find_workspace_checkout("task").await.unwrap();
    store.begin_workspace_relocation(&journal).await.unwrap();
    let ready = ready(&store, journal).await;
    sqlx::query("INSERT INTO workspaceTabs(id, workspaceId, kind, title, createdAt, updatedAt, payloadJson) VALUES ('broken', 'task', 'editor', 'Broken', '', '', '[]')").execute(store.pool()).await.unwrap();
    assert!(store.commit_workspace_relocation(&ready).await.is_err());
    assert_eq!(store.find_workspace("task").await.unwrap(), Some(original));
    assert_eq!(
        store.find_workspace_checkout("task").await.unwrap(),
        binding
    );
    assert_eq!(
        store
            .find_workspace_relocation("relocation")
            .await
            .unwrap()
            .unwrap()
            .phase,
        Phase::ChangesApplied
    );
}
