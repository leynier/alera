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
