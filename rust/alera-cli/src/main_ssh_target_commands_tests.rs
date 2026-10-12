use super::*;
use alera_core::runtime::SshBootstrapStatus;

fn saved_target() -> SshTarget {
    let created = chrono::DateTime::parse_from_rfc3339("2026-09-01T10:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    SshTarget {
        id: "build-mac".into(),
        alias: "Build Mac".into(),
        host: "mac.example.test".into(),
        port: 22,
        username: "alera".into(),
        platform: Some("macos".into()),
        arch: Some("arm64".into()),
        auth_kind: SshAuthKind::Agent,
        created_at: created,
        updated_at: created,
        last_status: Some("ready".into()),
        install_dir: Some("/Users/alera/.alera/runtime".into()),
        projects_dir: Some("~/code".into()),
        identity_file: None,
        runtime_version: Some("0.105.0".into()),
        runtime_platform: Some("macos".into()),
        runtime_arch: Some("arm64".into()),
        bootstrap_status: SshBootstrapStatus::Installed,
        last_bootstrap_at: Some(created),
        last_checked_at: Some(created),
        last_error: None,
    }
}

fn no_changes() -> SshTargetUpdateArgs {
    SshTargetUpdateArgs {
        id: "build-mac".into(),
        alias: None,
        host: None,
        port: None,
        username: None,
        platform: None,
        arch: None,
        auth_kind: None,
        projects_dir: None,
        identity_file: None,
    }
}

#[test]
fn an_update_changes_only_the_given_fields_and_keeps_the_installed_runtime() {
    let now = Utc::now();
    let updated = apply_ssh_target_update(
        saved_target(),
        SshTargetUpdateArgs {
            host: Some("mac.lan".into()),
            port: Some(2222),
            ..no_changes()
        },
        now,
    );
    let saved = saved_target();
    assert_eq!(updated.host, "mac.lan");
    assert_eq!(updated.port, 2222);
    assert_eq!(updated.updated_at, now);
    assert_eq!(updated.alias, saved.alias);
    assert_eq!(updated.username, saved.username);
    assert_eq!(updated.platform, saved.platform);
    assert_eq!(updated.projects_dir, saved.projects_dir);
    assert_eq!(updated.install_dir, saved.install_dir);
    assert_eq!(updated.last_status, saved.last_status);
    assert_eq!(updated.runtime_version, saved.runtime_version);
    assert_eq!(updated.bootstrap_status, saved.bootstrap_status);
    assert_eq!(updated.created_at, saved.created_at);
}

#[test]
fn an_empty_value_clears_an_optional_field() {
    let updated = apply_ssh_target_update(
        saved_target(),
        SshTargetUpdateArgs {
            projects_dir: Some("  ".into()),
            identity_file: None,
            platform: Some(String::new()),
            auth_kind: Some(SshAuthKindArg::Key),
            ..no_changes()
        },
        Utc::now(),
    );
    assert_eq!(updated.projects_dir, None);
    assert_eq!(updated.platform, None);
    assert_eq!(updated.arch.as_deref(), Some("arm64"));
    assert_eq!(updated.auth_kind, SshAuthKind::Key);
}

#[tokio::test]
async fn an_offline_remove_refuses_a_host_that_still_has_checkouts() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.upsert_ssh_target(saved_target()).await.unwrap();
    let project: alera_core::runtime::Project = serde_json::from_value(json!({
        "id": "app", "name": "app", "repoPath": "/srv/app", "kind": "folder",
        "createdAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
    }))
    .unwrap();
    store.upsert_project(project).await.unwrap();
    store
        .register_project_checkout("app", "build-mac", "/srv/app")
        .await
        .unwrap();

    let error = remove_unused_ssh_target(&store, "build-mac")
        .await
        .unwrap_err()
        .to_string();
    assert_eq!(
        error,
        "Build Mac still has 1 project and 0 workspaces. Remove them first."
    );
    assert!(store.find_ssh_target("build-mac").await.unwrap().is_some());

    store
        .remove_project_checkout("app", "build-mac")
        .await
        .unwrap();
    remove_unused_ssh_target(&store, "build-mac").await.unwrap();
    assert!(store.find_ssh_target("build-mac").await.unwrap().is_none());
}
