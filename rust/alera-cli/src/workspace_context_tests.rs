use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use super::{requested_workspace_id, WorkspaceContext};

fn workspace(status: WorkspaceStatus) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: "ws-1".to_string(),
        instance_id: "inst-1".to_string(),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: "proj-1".to_string(),
        name: "Feature".to_string(),
        branch: Some("feat/dark-mode".to_string()),
        path: "/tmp/ws-1".to_string(),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status,
        source_branch: Some("main".to_string()),
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

#[test]
fn context_prefers_the_current_branch_as_source() {
    let context = WorkspaceContext::from_workspace(workspace(WorkspaceStatus::Active)).unwrap();
    assert_eq!(context.project_id, "proj-1");
    assert_eq!(context.source_branch(), Some("feat/dark-mode"));
}

#[test]
fn context_rejects_removed_workspaces() {
    assert!(WorkspaceContext::from_workspace(workspace(WorkspaceStatus::Removed)).is_err());
}

#[test]
fn requested_id_prefers_the_explicit_flag_over_the_environment() {
    let _guard = EnvLock;
    std::env::set_var("ALERA_WORKSPACE_ID", "from-env");
    assert_eq!(
        requested_workspace_id(Some("from-flag")).as_deref(),
        Some("from-flag")
    );
    assert_eq!(requested_workspace_id(None).as_deref(), Some("from-env"));
    std::env::remove_var("ALERA_WORKSPACE_ID");
    assert_eq!(requested_workspace_id(None), None);
}

#[tokio::test]
async fn resolve_loads_the_workspace_from_the_runtime_store() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "proj-1".to_string(),
            name: "Project".to_string(),
            repo_path: "/tmp/repo".to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(workspace(WorkspaceStatus::Active))
        .await
        .unwrap();

    let runtime = crate::cli::RuntimeDirArgs {
        runtime_dir: Some(dir.path().to_string_lossy().into_owned()),
    };
    let context = super::resolve_workspace_context(&runtime, Some("ws-1"))
        .await
        .unwrap();
    assert_eq!(context.workspace_id, "ws-1");
    assert_eq!(context.project_id, "proj-1");
    assert_eq!(context.branch.as_deref(), Some("feat/dark-mode"));
}

struct EnvLock;

impl Drop for EnvLock {
    fn drop(&mut self) {
        std::env::remove_var("ALERA_WORKSPACE_ID");
    }
}
