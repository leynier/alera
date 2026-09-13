use super::*;
use alera_core::runtime::{AutomationPrecheck, ProjectKind};
use chrono::Utc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

fn fixture() -> (tempfile::TempDir, OwnerPrecheckEnvelope) {
    let directory = tempfile::tempdir().unwrap();
    let repo = directory.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    let path = repo.canonicalize().unwrap().to_str().unwrap().to_string();
    let project = Project {
        id: "project".into(),
        name: "Project".into(),
        repo_path: path.clone(),
        kind: ProjectKind::Folder,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };
    let request = OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        workspace: None,
        origin_id: "home".into(),
        run_id: "run".into(),
        project_id: project.id.clone(),
        path,
        precheck: AutomationPrecheck {
            command: "exit 1".into(),
            timeout_seconds: 10,
        },
    };
    (
        directory,
        OwnerPrecheckEnvelope {
            project,
            request,
            workspace: None,
        },
    )
}

fn args(
    directory: &std::path::Path,
    envelope: &OwnerPrecheckEnvelope,
    action: OwnerPrecheckAction,
) -> RemoteOwnerPrecheckArgs {
    RemoteOwnerPrecheckArgs {
        state_dir: directory.to_path_buf(),
        metadata_base64: base64::engine::general_purpose::STANDARD
            .encode(serde_json::to_vec(envelope).unwrap()),
        action,
    }
}

#[tokio::test]
async fn owner_precheck_cancel_uses_retained_identity_without_rewriting_project_metadata() {
    let (directory, mut envelope) = fixture();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    register_for_action(&store, &envelope, OwnerPrecheckAction::Cancel)
        .await
        .unwrap();
    store
        .cancel_owner_automation_precheck(&envelope.request)
        .await
        .unwrap();
    // A changed Home project must not prevent cancellation of retained work.
    envelope.project.kind = ProjectKind::GitRepository;
    assert!(register_project(&store, &envelope).await.is_err());
    register_for_action(&store, &envelope, OwnerPrecheckAction::Cancel)
        .await
        .unwrap();
    let project = store
        .find_project(&envelope.project.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(project.kind, ProjectKind::Folder);
    assert!(store.list_workspaces(&project.id).await.unwrap().is_empty());
}

#[tokio::test]
async fn owner_precheck_status_and_cancel_never_start_an_unavailable_runtime() {
    let (directory, envelope) = fixture();
    let state = directory.path().join("missing-owner");
    for action in [OwnerPrecheckAction::Status, OwnerPrecheckAction::Cancel] {
        let error = run(args(&state, &envelope, action)).await.unwrap_err();
        assert!(error
            .to_string()
            .contains("no replacement runtime was started"));
        assert!(!state.exists());
    }
}

#[tokio::test]
async fn owner_precheck_completed_receipt_is_readable_after_runtime_idle_shutdown() {
    let (directory, envelope) = fixture();
    let state = directory.path().join("owner");
    let store = RuntimeStore::open(&state).await.unwrap();
    register_project(&store, &envelope).await.unwrap();
    store
        .register_owner_automation_precheck(&envelope.request)
        .await
        .unwrap();
    for action in [OwnerPrecheckAction::Status, OwnerPrecheckAction::Cancel] {
        assert!(run(args(&state, &envelope, action))
            .await
            .unwrap_err()
            .to_string()
            .contains("closure remains unverified"));
    }
    store
        .cancel_owner_automation_precheck(&envelope.request)
        .await
        .unwrap();
    store
        .finish_owner_automation_precheck(
            &envelope.request,
            &alera_core::runtime::OwnerAutomationPrecheckOutcome::Cancelled,
        )
        .await
        .unwrap();
    store.pool().close().await;
    for action in [OwnerPrecheckAction::Status, OwnerPrecheckAction::Cancel] {
        let receipt = run(args(&state, &envelope, action)).await.unwrap();
        assert_eq!(receipt["job"]["outcome"]["kind"], "cancelled");
        assert_eq!(receipt["processes"], serde_json::json!([]));
        assert!(!state.join("host.json").exists());
    }
    let mut wrong = envelope.clone();
    wrong.request.origin_id = "another-home".into();
    assert!(run(args(&state, &wrong, OwnerPrecheckAction::Status))
        .await
        .is_err());
}

#[tokio::test]
async fn owner_precheck_invalid_scope_and_missing_declaration_do_not_create_state() {
    let (directory, envelope) = fixture();
    let state = directory.path().join("missing-owner");
    let mut wrong = envelope.clone();
    wrong.request.project_id = "another-project".into();
    assert!(run(args(&state, &wrong, OwnerPrecheckAction::Start))
        .await
        .is_err());
    let error = run(args(&state, &envelope, OwnerPrecheckAction::Start))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("automation declaration"));
    assert!(!state.exists());
}

#[tokio::test]
async fn owner_precheck_project_registration_preserves_identity_without_creating_tasks() {
    let (directory, envelope) = fixture();
    let store = RuntimeStore::open(&directory.path().join("owner"))
        .await
        .unwrap();
    register_project(&store, &envelope).await.unwrap();
    let mut retry = envelope.clone();
    retry.project.name = "Renamed by a different client".into();
    register_project(&store, &retry).await.unwrap();
    assert_eq!(
        store.find_project("project").await.unwrap().unwrap().name,
        "Project"
    );
    assert!(store.list_workspaces("project").await.unwrap().is_empty());
    assert_eq!(
        store
            .find_project_checkout("project", LOCAL_HOST_ID)
            .await
            .unwrap()
            .unwrap()
            .path,
        envelope.request.path
    );
    retry.project.repo_path.push_str("-other");
    assert!(register_project(&store, &retry).await.is_err());
    assert_eq!(
        store
            .find_project("project")
            .await
            .unwrap()
            .unwrap()
            .repo_path,
        envelope.request.path
    );
}

#[tokio::test]
async fn owner_precheck_missing_capability_preserves_the_live_host_and_does_not_register_project() {
    let (directory, envelope) = fixture();
    std::fs::write(
        std::path::Path::new(&envelope.request.path).join("alera.toml"),
        "[automation]\ndeclared = true\n",
    )
    .unwrap();
    let state = directory.path().join("owner");
    assert_missing_capability(&state, &envelope, "ownerAutomationPrecheckV1", vec![]).await;
}

async fn assert_missing_capability(
    state: &std::path::Path,
    envelope: &OwnerPrecheckEnvelope,
    required: &str,
    capabilities: Vec<&str>,
) {
    std::fs::create_dir(state).unwrap();
    let listener = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
        .await
        .unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (reader, mut writer) = socket.into_split();
        let mut lines = BufReader::new(reader).lines();
        let hello: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(hello["type"], "hello");
        let reply = serde_json::json!({"id":hello["id"],"ok":true,"payload":{}});
        writer
            .write_all(format!("{reply}\n").as_bytes())
            .await
            .unwrap();
        assert!(lines.next_line().await.unwrap().is_none());
    });
    let control = serde_json::to_string(&serde_json::json!({
        "protocolVersion":crate::terminal_host::protocol::PROTOCOL_VERSION,
        "port":port,"token":"fixture-token",
        "runtimeCapabilities":capabilities
    }))
    .unwrap();
    std::fs::write(state.join("host.json"), &control).unwrap();
    let result = run(args(state, envelope, OwnerPrecheckAction::Start)).await;
    tokio::time::timeout(std::time::Duration::from_secs(5), server)
        .await
        .unwrap()
        .unwrap();
    assert!(result.unwrap_err().to_string().contains(required));
    assert_eq!(
        std::fs::read_to_string(state.join("host.json")).unwrap(),
        control
    );
    assert!(!state
        .join(alera_core::runtime::RUNTIME_DATABASE_FILE_NAME)
        .exists());
}

#[tokio::test]
async fn linked_precheck_enrollment_preserves_legacy_origin_without_registering_main() {
    use alera_core::runtime::{
        AutomationPrecheckWorkspace, Workspace, WorkspaceKind, WorkspaceStatus,
    };
    let (directory, mut envelope) = fixture();
    let origin = directory.path().canonicalize().unwrap().join("legacy.git");
    let repo = git2::Repository::init_bare(&origin).unwrap();
    repo.set_head("refs/heads/main").unwrap();
    let tree = repo.treebuilder(None).unwrap().write().unwrap();
    let signature = git2::Signature::now("Test", "test@example.test").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "Initial",
        &repo.find_tree(tree).unwrap(),
        &[],
    )
    .unwrap();
    let path = origin.parent().unwrap().join("linked");
    alera_core::git::create_worktree(
        origin.to_str().unwrap(),
        "task",
        path.to_str().unwrap(),
        "main",
        false,
    )
    .unwrap();
    std::fs::write(path.join("alera.toml"), "[automation]\ndeclared = true\n").unwrap();
    envelope.project.kind = ProjectKind::GitRepository;
    envelope.project.repo_path = origin.to_str().unwrap().into();
    envelope.request.path = path.to_str().unwrap().into();
    envelope.request.workspace = Some(AutomationPrecheckWorkspace {
        workspace_id: "task".into(),
        instance_id: "instance".into(),
        kind: WorkspaceKind::Linked,
        repository_path: Some(origin.to_str().unwrap().into()),
    });
    envelope.workspace = Some(Workspace {
        id: "task".into(),
        instance_id: "instance".into(),
        host_id: "ssh".into(),
        project_id: envelope.project.id.clone(),
        name: "Home Task".into(),
        branch: Some("task".into()),
        path: envelope.request.path.clone(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: Some("main".into()),
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    });
    let state = directory.path().join("owner");
    assert_missing_capability(
        &directory.path().join("old-owner"),
        &envelope,
        "linkedOwnerAutomationPrecheckV1",
        vec!["ownerAutomationPrecheckV1"],
    )
    .await;
    let store = RuntimeStore::open(&state).await.unwrap();
    let mut changed = envelope.clone();
    changed.workspace.as_mut().unwrap().instance_id = "wrong".into();
    assert!(parse(&args(&state, &changed, OwnerPrecheckAction::Start)).is_err());
    assert!(store.list_all_workspaces().await.unwrap().is_empty());
    parse(&args(&state, &envelope, OwnerPrecheckAction::Start)).unwrap();
    register_project(&store, &envelope).await.unwrap();
    assert!(store
        .find_project_checkout(&envelope.project.id, LOCAL_HOST_ID)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .find_workspace_checkout("task")
            .await
            .unwrap()
            .unwrap()
            .repository_path,
        Some(origin.to_str().unwrap().into())
    );
    store.pool().close().await;
    let store = RuntimeStore::open(&state).await.unwrap();
    assert!(store
        .find_project_checkout(&envelope.project.id, LOCAL_HOST_ID)
        .await
        .unwrap()
        .is_none());
    let mut task = store.find_workspace("task").await.unwrap().unwrap();
    task.name = "Owner Name".into();
    store.upsert_workspace(task).await.unwrap();
    register_project(&store, &envelope).await.unwrap();
    assert_eq!(
        store.find_workspace("task").await.unwrap().unwrap().name,
        "Owner Name"
    );
    changed = envelope.clone();
    changed.workspace.as_mut().unwrap().instance_id = "replacement".into();
    changed.request.workspace.as_mut().unwrap().instance_id = "replacement".into();
    assert!(register_project(&store, &changed).await.is_err());
    assert_eq!(store.list_all_workspaces().await.unwrap().len(), 1);
    let principal = origin.parent().unwrap().join("principal");
    git2::Repository::init(&principal).unwrap();
    let mut project = envelope.project.clone();
    project.repo_path = principal.to_str().unwrap().into();
    let mut main_task = envelope.workspace.clone().unwrap();
    main_task.id = "principal-task".into();
    main_task.instance_id = "principal-instance".into();
    main_task.kind = WorkspaceKind::Main;
    main_task.path = project.repo_path.clone();
    crate::remote_workspace_owner::register(
        &store,
        crate::remote_workspace_owner::RemoteWorkspaceOwnerRegistration {
            project: project.clone(),
            workspace: main_task,
            repository_path: None,
        },
    )
    .await
    .unwrap();
    assert_eq!(
        store
            .find_project_checkout(&project.id, LOCAL_HOST_ID)
            .await
            .unwrap()
            .unwrap()
            .path,
        project.repo_path
    );
    assert_eq!(
        store
            .find_workspace_checkout("task")
            .await
            .unwrap()
            .unwrap()
            .repository_path,
        Some(origin.to_str().unwrap().into())
    );
    register_project(&store, &envelope).await.unwrap();
    assert_eq!(
        store
            .find_project(&project.id)
            .await
            .unwrap()
            .unwrap()
            .repo_path,
        project.repo_path
    );

    assert_eq!(
        alera_core::git::current_branch(origin.to_str().unwrap()).unwrap(),
        "main"
    );
    assert_eq!(
        alera_core::git::current_branch(path.to_str().unwrap()).unwrap(),
        "task"
    );
}

#[tokio::test]
async fn owner_precheck_probe_checks_support_without_creating_a_runtime_or_reservation() {
    let (directory, envelope) = fixture();
    std::fs::write(
        std::path::Path::new(&envelope.request.path).join("alera.toml"),
        "[automation]\ndeclared = true\n",
    )
    .unwrap();
    let state = directory.path().join("not-started");
    let result = run(args(&state, &envelope, OwnerPrecheckAction::Probe))
        .await
        .unwrap();
    assert_eq!(result["version"], 1);
    assert_eq!(result["capability"], "ownerAutomationPrecheckV1");
    assert_eq!(result["runtimeRunning"], false);
    assert_eq!(
        result["request"],
        serde_json::to_value(&envelope.request).unwrap()
    );
    assert!(!state.exists());
}
