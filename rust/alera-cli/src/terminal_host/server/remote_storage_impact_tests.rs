use std::sync::Arc;

use alera_core::runtime::{
    Project, ProjectKind, SshAuthKind, SshBootstrapStatus, SshTarget, Workspace, WorkspaceStatus,
};
use chrono::Utc;

use super::*;
use crate::terminal_host::host_link::HostLinkLauncher;

/// A satellite that registers the mirrored workspace and measures it: the
/// worktree is clean unless the hub asked to keep its sessions running.
const SATELLITE: &str = r#"
printf '%s\n' '{"event":"hostLink.attached","payload":{"runtimeDir":"/sat","platform":"linux","arch":"x86_64","hostVersion":"9.9.9","runtimeCapabilities":["remoteSatelliteV1"]}}'
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"type":"workspace.storageImpact"'*'"closeSessions":true'*|*'"closeSessions":true'*'"type":"workspace.storageImpact"'*)
      printf '{"id":%s,"ok":true,"payload":{"workspaceId":"task","path":"/remote/task","sizeBytes":42,"entryCount":3,"measuredAt":"2026-10-10T00:00:00Z","lastActivityAt":"2026-10-10T00:00:00Z","safeToClean":true,"blockers":[]}}\n' "$id" ;;
    *'"type":"workspace.storageImpact"'*)
      printf '{"id":%s,"ok":true,"payload":{"workspaceId":"task","path":"/remote/task","sizeBytes":42,"entryCount":3,"measuredAt":"2026-10-10T00:00:00Z","lastActivityAt":"2026-10-10T00:00:00Z","safeToClean":false,"blockers":["Workspace has a live terminal session or process"]}}\n' "$id" ;;
    *) printf '{"id":%s,"ok":true,"payload":{"id":"task"}}\n' "$id" ;;
  esac
done
"#;

fn launcher() -> Arc<HostLinkLauncher> {
    Arc::new(|_target: &SshTarget| {
        let mut command = alera_core::child_process::windowless_async_command("sh");
        command.arg("-c").arg(SATELLITE);
        Ok(command)
    })
}

fn workspace(id: &str, host_id: &str, kind: WorkspaceKind) -> Workspace {
    Workspace {
        id: id.into(),
        instance_id: format!("{id}-instance"),
        host_id: host_id.into(),
        project_id: "project".into(),
        name: id.into(),
        branch: Some(id.into()),
        path: "/remote/task".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    }
}

async fn remote_fixture(directory: &tempfile::TempDir) -> (RuntimeStore, HostLinkRegistry) {
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_ssh_target(SshTarget {
            id: "ssh".into(),
            alias: "Lab".into(),
            host: "lab.local".into(),
            port: 22,
            username: "dev".into(),
            platform: Some("linux".into()),
            arch: None,
            auth_kind: SshAuthKind::Agent,
            created_at: now,
            updated_at: now,
            last_status: None,
            install_dir: Some("~/.alera/sidecar".into()),
            projects_dir: None,
            runtime_version: None,
            runtime_platform: Some("linux".into()),
            runtime_arch: None,
            bootstrap_status: SshBootstrapStatus::Installed,
            last_bootstrap_at: None,
            last_checked_at: None,
            last_error: None,
        })
        .await
        .unwrap();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: "/home-only".into(),
            kind: ProjectKind::GitRepository,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    store
        .register_project_checkout("project", "ssh", "/remote/project")
        .await
        .unwrap();
    store
        .insert_workspace_with_repository(
            workspace("task", "ssh", WorkspaceKind::Linked),
            "/remote/project",
        )
        .await
        .unwrap();
    let (inbox, _rx) = crate::terminal_host::ServerInbox::channel();
    let links = HostLinkRegistry::with_launcher(store.clone(), inbox, launcher());
    (store, links)
}

#[tokio::test]
async fn a_remote_linked_workspace_is_measured_by_its_satellite() {
    let directory = tempfile::tempdir().unwrap();
    let (store, links) = remote_fixture(&directory).await;

    let impact = measure_on_owner(&store, &links, "task", true, &[])
        .await
        .unwrap()
        .expect("a remote linked workspace is measured remotely");

    assert_eq!(impact["workspaceId"], "task");
    assert_eq!(impact["sizeBytes"], 42);
    assert_eq!(impact["safeToClean"], true, "{impact}");
    assert_eq!(impact["blockers"], json!([]));
}

#[tokio::test]
async fn hub_and_satellite_blockers_are_merged() {
    let directory = tempfile::tempdir().unwrap();
    let (store, links) = remote_fixture(&directory).await;
    let hub = vec!["Workspace is owned by an active automation".to_string()];

    let impact = measure_on_owner(&store, &links, "task", false, &hub)
        .await
        .unwrap()
        .unwrap();

    assert_eq!(impact["safeToClean"], false);
    assert_eq!(
        impact["blockers"],
        json!([
            "Workspace is owned by an active automation",
            "Workspace has a live terminal session or process",
        ])
    );
}

#[tokio::test]
async fn local_and_unknown_workspaces_stay_on_the_hub() {
    let directory = tempfile::tempdir().unwrap();
    let (store, links) = remote_fixture(&directory).await;
    store
        .upsert_workspace(workspace("local", "local", WorkspaceKind::Linked))
        .await
        .unwrap();

    for id in ["local", "missing"] {
        assert!(measure_on_owner(&store, &links, id, true, &[])
            .await
            .unwrap()
            .is_none());
    }
}
