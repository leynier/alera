use alera_core::runtime::{
    AgentNativeSessionRecord, Project, ProjectKind, WorkspaceStatus, WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;

use super::*;
use crate::managed_workspace::ManagedWorkspaceRemoveRequest;

fn workspace(id: &str, host_id: &str, path: &str, kind: WorkspaceKind) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.into(),
        instance_id: format!("{id}-instance"),
        host_id: host_id.into(),
        project_id: "project-1".into(),
        name: id.into(),
        branch: None,
        path: path.into(),
        created_at: now,
        updated_at: now,
        kind,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

fn session(workspace_id: &str, agent_type: &str, session_id: &str) -> AgentNativeSessionRecord {
    AgentNativeSessionRecord {
        workspace_id: workspace_id.into(),
        agent_type: agent_type.into(),
        session_id: session_id.into(),
        ccs_profile: None,
        cwd: None,
        tab_id: None,
        settings: None,
        first_seen_at: Utc::now(),
        last_seen_at: Utc::now(),
    }
}

fn removal(id: &str) -> RuntimeMutationRequest {
    RuntimeMutationRequest::RemoveManagedWorkspace {
        request: ManagedWorkspaceRemoveRequest {
            id: id.into(),
            delete_branch: None,
            active_workspace_id: None,
            close_sessions: true,
        },
    }
}

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "project-1".into(),
            name: "Project".into(),
            repo_path: "/repo".into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    for (id, host, path, kind) in [
        ("main", LOCAL_HOST_ID, "/repo", WorkspaceKind::Main),
        (
            "feature",
            LOCAL_HOST_ID,
            "/repo-feature",
            WorkspaceKind::Linked,
        ),
        (
            "remote",
            "ssh-a",
            "/srv/repo-feature",
            WorkspaceKind::Linked,
        ),
    ] {
        store
            .insert_workspace(workspace(id, host, path, kind))
            .await
            .unwrap();
    }
    (directory, store)
}

#[tokio::test]
async fn nothing_is_planned_while_the_setting_is_off() {
    let (_dir, store) = store().await;
    store
        .record_agent_native_session(&session("feature", "claude", "sess-1"))
        .await
        .unwrap();
    assert!(capture_agent_session_cleanup(&store, &removal("feature"))
        .await
        .is_none());
}

#[tokio::test]
async fn a_linked_worktree_plans_its_path_and_keeps_sessions_used_elsewhere() {
    let (_dir, store) = store().await;
    store
        .set_delete_agent_sessions_on_workspace_removal(true)
        .await
        .unwrap();
    for record in [
        session("feature", "claude", "sess-1"),
        session("feature", "codex", "shared"),
        session("main", "codex", "shared"),
    ] {
        store.record_agent_native_session(&record).await.unwrap();
    }
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: "feature".into(),
            kind: "terminal".into(),
            title: "Pi".into(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({"agentNativeSessionId": "sess-pi", "agentNativeSessionAgent": "pi"}),
        })
        .await
        .unwrap();
    let pending = capture_agent_session_cleanup(&store, &removal("feature"))
        .await
        .unwrap();
    assert_eq!(pending.workspace_id, "feature");
    assert_eq!(pending.plan.workspace_path, "/repo-feature");
    assert_eq!(pending.plan.scope, NativeSessionCleanupScope::WorkspacePath);
    let planned = pending
        .plan
        .sessions
        .iter()
        .map(|session| (session.agent_type.as_str(), session.session_id.as_str()))
        .collect::<Vec<_>>();
    assert_eq!(planned, [("claude", "sess-1"), ("pi", "sess-pi")]);
    let preserved = pending
        .plan
        .preserved
        .iter()
        .map(|session| (session.agent_type.as_str(), session.session_id.as_str()))
        .collect::<Vec<_>>();
    assert_eq!(preserved, [("codex", "shared")]);
}

#[tokio::test]
async fn the_main_checkout_only_plans_its_own_sessions() {
    let (_dir, store) = store().await;
    store
        .set_delete_agent_sessions_on_workspace_removal(true)
        .await
        .unwrap();
    store
        .record_agent_native_session(&session("main", "claude", "sess-1"))
        .await
        .unwrap();
    let pending = capture_agent_session_cleanup(&store, &removal("main"))
        .await
        .unwrap();
    assert_eq!(
        pending.plan.scope,
        NativeSessionCleanupScope::RegisteredSessions
    );
    assert_eq!(pending.plan.sessions.len(), 1);
}

#[tokio::test]
async fn a_remote_workspace_or_another_mutation_plans_nothing() {
    let (_dir, store) = store().await;
    store
        .set_delete_agent_sessions_on_workspace_removal(true)
        .await
        .unwrap();
    store
        .record_agent_native_session(&session("remote", "claude", "sess-1"))
        .await
        .unwrap();
    assert!(capture_agent_session_cleanup(&store, &removal("remote"))
        .await
        .is_none());
    assert!(capture_agent_session_cleanup(
        &store,
        &RuntimeMutationRequest::RemoveWorkspace {
            workspace_id: "feature".into(),
            cascade_tabs: true,
        }
    )
    .await
    .is_none());
}
