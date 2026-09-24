use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};
use crate::runtime::WorkspaceKind;

#[tokio::test]
async fn process_evidence_survives_reopen_and_rejects_stale_updates() {
    let (directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    let intent = store
        .begin_workspace_process_job(&owner, "speech", "linux", Some("boot".into()))
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    let records = reopened.workspace_process_jobs(&owner.id).await.unwrap();
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].phase, WorkspaceProcessJobPhase::LaunchIntent);
    assert_eq!(records[0].workspace.instance_id, owner.instance_id);
    let running = reopened
        .record_workspace_process_spawn(&intent, 123, Some(456))
        .await
        .unwrap();
    assert!(store
        .record_workspace_process_phase(&intent, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .is_err());
    assert!(store
        .record_workspace_process_phase(&running, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .is_err());
    let exited = store
        .record_workspace_process_phase(&running, WorkspaceProcessJobPhase::RootExited)
        .await
        .unwrap();
    assert_eq!(exited.pid, Some(123));
    assert_eq!(exited.start_marker, Some(456));
    let records = reopened.workspace_process_jobs(&owner.id).await.unwrap();
    assert_eq!(records[0].phase, WorkspaceProcessJobPhase::RootExited);
    assert_eq!(records[0].boot_id.as_deref(), Some("boot"));
}

#[tokio::test]
async fn changed_identity_or_location_cannot_record_a_launch() {
    let (_directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    for change in ["instance", "host", "path", "project"] {
        let mut stale = owner.clone();
        match change {
            "instance" => stale.instance_id = "other".into(),
            "host" => stale.host_id = "other".into(),
            "path" => stale.path = "/other".into(),
            _ => stale.project_id = "other".into(),
        }
        assert!(store
            .begin_workspace_process_job(&stale, "speech", "linux", None)
            .await
            .is_err());
    }
    assert!(store
        .workspace_process_jobs(&owner.id)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn repeated_operation_ids_and_shared_paths_keep_separate_execution_history() {
    let (_directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    let sibling = workspace("sibling", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    store.insert_workspace(sibling.clone()).await.unwrap();
    let first = store
        .begin_workspace_process_job(&owner, "speech", "linux", None)
        .await
        .unwrap();
    let second = store
        .begin_workspace_process_job(&owner, "speech", "linux", None)
        .await
        .unwrap();
    assert_ne!(first.id, second.id);
    assert!(store
        .workspace_process_jobs(&sibling.id)
        .await
        .unwrap()
        .is_empty());
    store
        .record_workspace_process_phase(&first, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .unwrap();
    let records = store.workspace_process_jobs(&owner.id).await.unwrap();
    assert_eq!(records.len(), 2);
    assert_eq!(
        records
            .iter()
            .filter(|job| job.phase == WorkspaceProcessJobPhase::LaunchIntent)
            .count(),
        1
    );
}

#[tokio::test]
async fn unresolved_jobs_protect_records_and_location_after_restart() {
    let (directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    let intent = store
        .begin_workspace_process_job(&owner, "speech", "linux", None)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened.remove_workspace(&owner.id, true).await.is_err());
    assert!(reopened
        .retire_verified_shared_workspace(&owner)
        .await
        .is_err());
    assert!(reopened
        .workspace_retirement_receipt(&owner.id, &owner.instance_id)
        .await
        .unwrap()
        .is_none());
    assert!(reopened.remove_project(&owner.project_id).await.is_err());
    assert!(reopened
        .find_project(&owner.project_id)
        .await
        .unwrap()
        .is_some());
    let mut renamed = owner.clone();
    renamed.name = "New task name".into();
    reopened.upsert_workspace(renamed.clone()).await.unwrap();
    let mut relocated = renamed.clone();
    relocated.path = "/other".into();
    assert!(reopened.upsert_workspace(relocated).await.is_err());
    let current = reopened.find_workspace(&owner.id).await.unwrap().unwrap();
    assert_eq!(current.name, renamed.name);
    assert_eq!(current.path, owner.path);
    let running = reopened
        .record_workspace_process_spawn(&intent, 123, None)
        .await
        .unwrap();
    let exited = reopened
        .record_workspace_process_phase(&running, WorkspaceProcessJobPhase::RootExited)
        .await
        .unwrap();
    assert!(reopened
        .require_workspace_process_closure(&owner.id)
        .await
        .is_err());
    assert!(reopened.remove_workspace(&owner.id, true).await.is_err());
    // This fixture has no OS process; simulate the owner's independent closure proof.
    reopened
        .record_workspace_process_phase(&exited, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .unwrap();
    reopened
        .require_workspace_process_closure(&owner.id)
        .await
        .unwrap();
    reopened
        .retire_verified_shared_workspace(&current)
        .await
        .unwrap();
    assert_eq!(
        reopened
            .workspace_process_jobs(&owner.id)
            .await
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn failed_spawn_does_not_prevent_retirement_or_remove_a_siblings_evidence() {
    let (_directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    let sibling = workspace("sibling", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    store.insert_workspace(sibling.clone()).await.unwrap();
    let failed = store
        .begin_workspace_process_job(&owner, "speech", "linux", None)
        .await
        .unwrap();
    let neighbor = store
        .begin_workspace_process_job(&sibling, "speech", "linux", None)
        .await
        .unwrap();
    store
        .record_workspace_process_phase(&failed, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .unwrap();
    store
        .retire_verified_shared_workspace(&owner)
        .await
        .unwrap();
    assert_eq!(
        store.workspace_process_jobs(&sibling.id).await.unwrap()[0].id,
        neighbor.id
    );
    assert!(store.find_workspace(&sibling.id).await.unwrap().is_some());
    assert!(store
        .begin_workspace_process_job(&owner, "late", "linux", None)
        .await
        .is_err());
}

#[tokio::test]
async fn concurrent_launch_and_retirement_cannot_both_commit() {
    let (_directory, store, _) = fixture().await;
    let owner = workspace("task", "local", "/repo", WorkspaceKind::Main);
    store.insert_workspace(owner.clone()).await.unwrap();
    let (launch, removal) = tokio::join!(
        store.begin_workspace_process_job(&owner, "speech", "linux", None),
        store.retire_verified_shared_workspace(&owner),
    );
    assert!(!(launch.is_ok() && removal.is_ok()));
    if launch.is_ok() {
        assert!(store.find_workspace(&owner.id).await.unwrap().is_some());
    }
    if removal.is_ok() {
        assert!(store
            .workspace_process_jobs(&owner.id)
            .await
            .unwrap()
            .is_empty());
    }
}
