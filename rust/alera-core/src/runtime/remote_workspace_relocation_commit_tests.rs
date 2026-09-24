use super::*;

#[tokio::test]
async fn remote_commit_preserves_identity_metadata_tabs_and_repository_origin() {
    let (_root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let neighbor = remote(&store, "neighbor", "ssh").await;
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    assert!(store
        .commit_remote_workspace_relocation(&pending.id)
        .await
        .is_err());
    let now = chrono::Utc::now();
    store.upsert_workspace_tab(crate::runtime::WorkspaceTabRecord {
        id: "editor".into(), workspace_id: source.id.clone(), kind: "editor".into(), title: "Notes".into(),
        created_at: now, updated_at: now,
        payload: serde_json::json!({"filePath":"/remote/project/notes.md", "terminalSessionId":"session", "custom":"retained"}),
    }).await.unwrap();
    let mut renamed = source.clone();
    renamed.name = "Updated task name".into();
    renamed.is_pinned = true;
    store.upsert_workspace(renamed.clone()).await.unwrap();
    store
        .record_remote_workspace_relocation_receipt(&pending.id, &owner_receipt(&pending))
        .await
        .unwrap();
    let moved = store
        .commit_remote_workspace_relocation(&pending.id)
        .await
        .unwrap();
    assert_eq!(moved.id, source.id);
    assert_eq!(moved.instance_id, source.instance_id);
    assert_eq!(moved.name, renamed.name);
    assert!(moved.is_pinned);
    assert_eq!(
        Some(moved.path.as_str()),
        pending.destination_path.as_deref()
    );
    assert_eq!(moved.host_id, "ssh");
    let binding = store
        .find_workspace_checkout(&source.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(binding.repository_path.as_deref(), Some("/remote/project"));
    let tab = store.find_workspace_tab("editor").await.unwrap().unwrap();
    assert_eq!(tab.payload["filePath"], "/remote/worktrees/task/notes.md");
    assert_eq!(tab.payload["terminalSessionId"], "session");
    assert_eq!(tab.payload["custom"], "retained");
    assert_eq!(
        store.find_workspace(&neighbor.id).await.unwrap().unwrap(),
        neighbor
    );
    assert!(store
        .pending_remote_workspace_relocation("project", "ssh")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .commit_remote_workspace_relocation(&pending.id)
            .await
            .unwrap(),
        moved
    );
    assert_eq!(
        store
            .find_workspace_relocation(&pending.id)
            .await
            .unwrap()
            .unwrap()
            .phase,
        crate::runtime::WorkspaceRelocationPhase::Completed
    );
}

#[tokio::test]
async fn failed_home_commit_keeps_owner_receipt_and_pending_location_for_retry() {
    let (_root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    store
        .record_remote_workspace_relocation_receipt(&pending.id, &owner_receipt(&pending))
        .await
        .unwrap();
    let now = chrono::Utc::now();
    store
        .upsert_workspace_tab(crate::runtime::WorkspaceTabRecord {
            id: "broken".into(),
            workspace_id: source.id.clone(),
            kind: "editor".into(),
            title: "Broken".into(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!([]),
        })
        .await
        .unwrap();
    assert!(store
        .commit_remote_workspace_relocation(&pending.id)
        .await
        .is_err());
    assert_eq!(
        store
            .find_workspace(&source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        source.path
    );
    assert!(store
        .find_workspace_relocation(&pending.id)
        .await
        .unwrap()
        .is_none());
    assert!(store
        .pending_remote_workspace_relocation("project", "ssh")
        .await
        .unwrap()
        .is_some());
    assert!(store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .is_some());
    assert!(store.remove_workspace(&source.id, true).await.is_err());
}

#[tokio::test]
async fn home_roundtrip_keeps_receipts_and_rejects_the_superseded_commit() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let off = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    store
        .record_remote_workspace_relocation_receipt(&off.id, &owner_receipt(&off))
        .await
        .unwrap();
    let linked = store
        .commit_remote_workspace_relocation(&off.id)
        .await
        .unwrap();
    let on = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &linked,
            WorkspaceRelocationIntent {
                workspace_id: linked.id.clone(),
                to_project_checkout: true,
                destination_path: None,
                branch: None,
                replacement_branch: None,
                move_changes: true,
                shared_impact_confirmed: true,
            },
        )
        .await
        .unwrap();
    store
        .record_remote_workspace_relocation_receipt(&on.id, &owner_receipt(&on))
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let returned = reopened
        .commit_remote_workspace_relocation(&on.id)
        .await
        .unwrap();
    assert_eq!(returned.path, source.path);
    assert_eq!(returned.id, source.id);
    assert_eq!(returned.instance_id, source.instance_id);
    assert_eq!(returned.kind, WorkspaceKind::Main);
    assert_eq!(returned.branch.as_deref(), Some("topic"));
    assert!(reopened
        .commit_remote_workspace_relocation(&off.id)
        .await
        .is_err());
    assert_eq!(
        reopened.find_workspace(&source.id).await.unwrap().unwrap(),
        returned
    );
    assert!(reopened
        .find_remote_workspace_relocation_receipt(&off.id)
        .await
        .unwrap()
        .is_some());
    assert!(reopened
        .find_remote_workspace_relocation_receipt(&on.id)
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        reopened
            .commit_remote_workspace_relocation(&on.id)
            .await
            .unwrap(),
        returned
    );
}
