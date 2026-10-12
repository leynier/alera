use alera_core::runtime::SshAuthKind;

use super::*;

fn agent_target(id: &str) -> SshTarget {
    let now = chrono::Utc::now();
    SshTarget {
        id: id.to_string(),
        alias: id.to_string(),
        host: "build.local".to_string(),
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

async fn store_with(id: &str, status: SshBootstrapStatus) -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.upsert_ssh_target(agent_target(id)).await.unwrap();
    store
        .update_ssh_target_bootstrap_state(
            id,
            SshTargetBootstrapStateUpdate {
                status,
                install_dir: Some("~/.alera/sidecar"),
                runtime_version: Some("1.4.0"),
                runtime_platform: Some("linux"),
                runtime_arch: Some("x86_64"),
                last_error: None,
            },
        )
        .await
        .unwrap();
    (dir, store)
}

async fn stored_status(store: &RuntimeStore, id: &str) -> SshBootstrapStatus {
    store
        .find_ssh_target(id)
        .await
        .unwrap()
        .unwrap()
        .bootstrap_status
}

#[test]
fn interrupted_update_keeps_an_installed_host_installed() {
    for outcome in [SshBootstrapStatus::Failed, SshBootstrapStatus::Cancelled] {
        assert_eq!(
            status_after_interrupted_install(SshBootstrapStatus::Installed, outcome),
            SshBootstrapStatus::Installed
        );
    }
}

#[test]
fn interrupted_first_install_records_the_outcome() {
    for previous in [
        SshBootstrapStatus::NotInstalled,
        SshBootstrapStatus::Failed,
        SshBootstrapStatus::Cancelled,
        SshBootstrapStatus::Installing,
    ] {
        assert_eq!(
            status_after_interrupted_install(previous, SshBootstrapStatus::Failed),
            SshBootstrapStatus::Failed
        );
    }
}

#[tokio::test]
async fn update_of_installed_host_never_stores_installing_or_cancelled() {
    let (_dir, store) = store_with("mac", SshBootstrapStatus::Installed).await;

    mark_ssh_bootstrap_installing(&store, "mac").await.unwrap();
    assert_eq!(
        stored_status(&store, "mac").await,
        SshBootstrapStatus::Installed
    );

    cancel_ssh_bootstrap(&store, "mac").await.unwrap();
    assert_eq!(
        stored_status(&store, "mac").await,
        SshBootstrapStatus::Installed
    );
}

#[tokio::test]
async fn first_install_stores_installing_then_cancelled() {
    let (_dir, store) = store_with("mac", SshBootstrapStatus::NotInstalled).await;

    mark_ssh_bootstrap_installing(&store, "mac").await.unwrap();
    assert_eq!(
        stored_status(&store, "mac").await,
        SshBootstrapStatus::Installing
    );

    cancel_ssh_bootstrap(&store, "mac").await.unwrap();
    assert_eq!(
        stored_status(&store, "mac").await,
        SshBootstrapStatus::Cancelled
    );
}

#[test]
fn a_running_install_keeps_an_installed_host_installed() {
    assert_eq!(
        status_while_installing(SshBootstrapStatus::Installed),
        SshBootstrapStatus::Installed
    );
    assert_eq!(
        status_while_installing(SshBootstrapStatus::Failed),
        SshBootstrapStatus::Installing
    );
}
