use super::*;
use alera_core::runtime::{
    AutomationPrecheck, AutomationPrecheckWorkspace, Project, ProjectKind, Workspace,
    WorkspaceKind, WorkspaceStatus,
};
use chrono::Utc;

#[tokio::test]
async fn linked_envelope_preserves_scope_with_or_without_owner_principal() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: "/home-only".into(),
            kind: ProjectKind::GitRepository,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        })
        .await
        .unwrap();
    let workspace = Workspace {
        id: "task".into(),
        instance_id: "instance".into(),
        host_id: "ssh".into(),
        project_id: "project".into(),
        name: "Task".into(),
        branch: Some("task".into()),
        path: "/linked".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    };
    let workspace = store
        .insert_workspace_with_repository(workspace, "/legacy.git")
        .await
        .unwrap();
    let intent = AutomationPrecheckProcess {
        id: uuid::Uuid::new_v4().to_string(),
        run_id: "run".into(),
        attempt_count: 0,
        project_id: "project".into(),
        host_id: "ssh".into(),
        path: "/linked".into(),
        precheck: AutomationPrecheck {
            command: "not executed".into(),
            timeout_seconds: 10,
        },
        workspace: Some(AutomationPrecheckWorkspace {
            workspace_id: "task".into(),
            instance_id: "instance".into(),
            kind: WorkspaceKind::Linked,
            repository_path: Some("/legacy.git".into()),
        }),
        phase: WorkspaceProcessJobPhase::LaunchIntent,
        platform: "linux".into(),
        boot_id: None,
        pid: None,
        start_marker: None,
        closure_boot_id: None,
    };
    let envelope = owner_envelope(&store, &intent).await.unwrap();
    assert_eq!(envelope.project.repo_path, "/legacy.git");
    assert_eq!(envelope.workspace, Some(workspace.clone()));
    assert!(store
        .find_project_checkout("project", "ssh")
        .await
        .unwrap()
        .is_none());
    store
        .register_project_checkout("project", "ssh", "/principal")
        .await
        .unwrap();
    let envelope = owner_envelope(&store, &intent).await.unwrap();
    assert_eq!(envelope.project.repo_path, "/principal");
    assert_eq!(envelope.request.workspace, intent.workspace);
    assert_eq!(envelope.workspace, Some(workspace));
    let mut changed = intent.clone();
    changed.workspace.as_mut().unwrap().instance_id = "replacement".into();
    assert!(owner_envelope(&store, &changed).await.is_err());
    changed = intent.clone();
    changed.workspace.as_mut().unwrap().repository_path = Some("/another.git".into());
    assert!(owner_envelope(&store, &changed).await.is_err());
    changed = intent.clone();
    changed.host_id = "another-host".into();
    assert!(owner_envelope(&store, &changed).await.is_err());
    changed = intent;
    changed.workspace = None;
    changed.path = "/principal".into();
    let envelope = owner_envelope(&store, &changed).await.unwrap();
    assert!(envelope.workspace.is_none());
    assert!(envelope.request.workspace.is_none());
    assert_eq!(envelope.project.repo_path, "/principal");
}
