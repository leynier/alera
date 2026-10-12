use chrono::Utc;

use super::{RuntimeStore, SshAuthKind, SshBootstrapStatus, SshTarget};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn ssh_target(id: &str, alias: &str) -> SshTarget {
    let now = Utc::now();
    SshTarget {
        id: id.to_string(),
        alias: alias.to_string(),
        host: format!("{id}.example.test"),
        port: 22,
        username: "alera".to_string(),
        platform: None,
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        projects_dir: None,
        identity_file: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::NotInstalled,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

fn assert_duplicate_alias(error: impl std::fmt::Display, alias: &str) {
    let text = error.to_string();
    assert_eq!(
        text,
        format!("ssh target alias already exists: {alias}"),
        "unexpected error: {text}"
    );
    assert!(
        !text.contains("UNIQUE")
            && !text.contains("2067")
            && !text.to_lowercase().contains("sqlite"),
        "product error leaked a SQLite unique-constraint: {text}"
    );
}

#[tokio::test]
async fn upsert_ssh_target_rejects_duplicate_alias_exact_and_nocase() {
    let (_dir, store) = store().await;
    let created = store
        .upsert_ssh_target(ssh_target("remote-1", "audit-637-mac"))
        .await
        .unwrap();
    assert_eq!(created.alias, "audit-637-mac");
    assert_eq!(store.list_ssh_targets().await.unwrap().len(), 1);

    let exact = store
        .upsert_ssh_target(ssh_target("remote-2", "audit-637-mac"))
        .await
        .unwrap_err();
    assert_duplicate_alias(exact, "audit-637-mac");

    let nocase = store
        .upsert_ssh_target(ssh_target("remote-3", "Audit-637-mac"))
        .await
        .unwrap_err();
    assert_duplicate_alias(nocase, "Audit-637-mac");

    assert_eq!(store.list_ssh_targets().await.unwrap().len(), 1);
}

#[tokio::test]
async fn upsert_ssh_target_keeps_own_alias_and_accepts_a_free_alias() {
    let (_dir, store) = store().await;
    store
        .upsert_ssh_target(ssh_target("remote-1", "audit-637-mac"))
        .await
        .unwrap();
    store
        .upsert_ssh_target(ssh_target("remote-2", "build-linux"))
        .await
        .unwrap();

    let mut same = ssh_target("remote-1", "audit-637-mac");
    same.host = "renamed.example.test".to_string();
    let updated = store.upsert_ssh_target(same).await.unwrap();
    assert_eq!(updated.host, "renamed.example.test");
    assert_eq!(updated.alias, "audit-637-mac");

    let mut own_case = ssh_target("remote-1", "AUDIT-637-MAC");
    own_case.host = "renamed.example.test".to_string();
    let recased = store.upsert_ssh_target(own_case).await.unwrap();
    assert_eq!(recased.alias, "AUDIT-637-MAC");

    let stolen = store
        .upsert_ssh_target(ssh_target("remote-1", "build-linux"))
        .await
        .unwrap_err();
    assert_duplicate_alias(stolen, "build-linux");
}

#[tokio::test]
async fn upsert_keeps_the_checked_status_and_stores_the_identity_file() {
    let (_dir, store) = store().await;
    store
        .upsert_ssh_target(ssh_target("remote", "Lab"))
        .await
        .unwrap();
    store
        .mark_ssh_target_checked("remote", super::SshTargetLastStatus::RuntimeReady)
        .await
        .unwrap();

    let mut edited = ssh_target("remote", "Lab");
    edited.last_status = Some("unreachable".into());
    edited.identity_file = Some("~/.ssh/lab_ed25519".into());
    let stored = store.upsert_ssh_target(edited).await.unwrap();

    assert_eq!(stored.last_status.as_deref(), Some("runtimeReady"));
    assert_eq!(stored.identity_file.as_deref(), Some("~/.ssh/lab_ed25519"));

    let mut cleared = stored.clone();
    cleared.identity_file = None;
    let stored = store.upsert_ssh_target(cleared).await.unwrap();
    assert_eq!(stored.identity_file, None);
}

#[tokio::test]
async fn an_attach_records_the_runtime_that_answered() {
    let (_dir, store) = store().await;
    store
        .upsert_ssh_target(ssh_target("remote", "Lab"))
        .await
        .unwrap();

    let attached = store
        .mark_ssh_target_attached("remote", Some("1.4.0"), Some("macos"), Some("arm64"))
        .await
        .unwrap();
    assert_eq!(attached.runtime_version.as_deref(), Some("1.4.0"));
    assert_eq!(attached.runtime_platform.as_deref(), Some("macos"));
    assert_eq!(attached.runtime_arch.as_deref(), Some("arm64"));

    let unknown_version = store
        .mark_ssh_target_attached("remote", Some(""), None, Some("x64"))
        .await
        .unwrap();
    assert_eq!(unknown_version.runtime_version.as_deref(), Some("1.4.0"));
    assert_eq!(unknown_version.runtime_platform.as_deref(), Some("macos"));
    assert_eq!(unknown_version.runtime_arch.as_deref(), Some("x64"));

    assert!(store
        .mark_ssh_target_attached("missing", None, None, None)
        .await
        .is_err());
}

#[tokio::test]
async fn references_count_active_workspaces_and_project_checkouts_on_a_host() {
    let (dir, store) = store().await;
    for id in ["p1", "p2"] {
        let project: super::Project = serde_json::from_value(serde_json::json!({
            "id": id, "name": id, "repoPath": dir.path().join(id), "kind": "folder",
            "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z"
        }))
        .unwrap();
        store.upsert_project(project).await.unwrap();
    }
    assert!(store.ssh_target_references("lab").await.unwrap().is_empty());

    store
        .register_project_checkout("p1", "lab", "/srv/p1")
        .await
        .unwrap();
    store
        .register_project_checkout("p2", "other", "/srv/p2")
        .await
        .unwrap();
    let workspace: super::Workspace = serde_json::from_value(serde_json::json!({
        "id": "w1", "instanceId": "w1-instance", "hostId": "lab", "projectId": "p2",
        "name": "Task", "branch": null, "path": "/srv/p2-task",
        "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
        "kind": "main", "status": "active", "sourceBranch": null,
        "reusesExistingBranch": false, "isPinned": false, "tagIds": [], "tagNames": [],
        "parentWorkspaceId": null, "childCount": 0
    }))
    .unwrap();
    store.insert_workspace(workspace).await.unwrap();

    let references = store.ssh_target_references("lab").await.unwrap();
    assert_eq!(
        references,
        super::SshTargetReferences {
            workspace_count: 1,
            // A main workspace on a host records that host's checkout too.
            checkout_count: 2,
            project_ids: vec!["p1".into(), "p2".into()],
        }
    );
    assert!(!references.is_empty());
}
