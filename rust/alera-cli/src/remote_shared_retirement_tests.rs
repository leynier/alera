use super::*;
use alera_core::runtime::SshTarget;
use serde_json::json;
use std::sync::Mutex;

struct Remote {
    receipt: Value,
    online: bool,
    scripts: Mutex<Vec<String>>,
}

impl RemoteHostExecutor for Remote {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        self.online.then_some(false)
    }
    async fn run(&self, _: &SshTarget, _: bool, script: &str) -> Result<String> {
        self.scripts.lock().unwrap().push(script.into());
        Ok(self.receipt.to_string())
    }
}

async fn fixture() -> (tempfile::TempDir, RuntimeStore, Workspace, Value) {
    let directory = tempfile::tempdir().unwrap();
    let folder = directory.path().join("folder");
    std::fs::create_dir(&folder).unwrap();
    std::fs::write(folder.join("keep"), "shared files").unwrap();
    let store = RuntimeStore::open(&directory.path().join("state"))
        .await
        .unwrap();
    let project =
        crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
            .await
            .unwrap()
            .project;
    let mut workspace = store.list_workspaces(&project.id).await.unwrap().remove(0);
    workspace.id = "remote-task".into();
    workspace.instance_id = "remote-instance".into();
    workspace.host_id = "ssh".into();
    store
        .register_project_checkout(&project.id, "ssh", &workspace.path)
        .await
        .unwrap();
    store.insert_workspace(workspace.clone()).await.unwrap();
    let target: SshTarget = serde_json::from_value(json!({
        "id":"ssh", "alias":"Test", "host":"test.invalid", "port":22,
        "username":"test", "authKind":"agent", "createdAt":chrono::Utc::now(),
        "updatedAt":chrono::Utc::now(), "installDir":"/test/sidecar", "bootstrapStatus":"installed",
    }))
    .unwrap();
    store.upsert_ssh_target(target).await.unwrap();
    let mut owner = workspace.clone();
    owner.host_id = LOCAL_HOST_ID.into();
    let receipt = json!({"version":1,"workspace":owner,"processClosureVerified":true});
    (directory, store, workspace, receipt)
}

#[tokio::test]
async fn verified_receipt_retires_only_matching_home_identity() {
    let (directory, store, workspace, receipt) = fixture().await;
    let remote = Remote {
        receipt,
        online: true,
        scripts: Mutex::new(vec![]),
    };
    let proof = retire(&store, &workspace, &remote).await.unwrap();
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
    let mut changed = workspace.clone();
    changed.instance_id = "replacement".into();
    assert!(proof.verify(&changed).is_err());
    let removed = crate::shared_workspace_removal::remove_after_remote_retirement(
        &store,
        &crate::managed_workspace::ManagedWorkspaceRemoveRequest {
            id: workspace.id.clone(),
            delete_branch: Some(false),
            active_workspace_id: None,
            close_sessions: true,
        },
        &proof,
    )
    .await
    .unwrap();
    assert_eq!(removed.id, workspace.id);
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_none());
    assert_eq!(
        store
            .list_workspaces(&workspace.project_id)
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        std::fs::read_to_string(directory.path().join("folder/keep")).unwrap(),
        "shared files"
    );
    let scripts = remote.scripts.lock().unwrap();
    assert!(scripts[0].contains("retire-owner-workspace --workspace-id 'remote-task' --instance-id 'remote-instance' --close-sessions"));
}

#[tokio::test]
async fn unavailable_or_mismatched_owner_preserves_home_records() {
    let (_directory, store, workspace, receipt) = fixture().await;
    let mut cases = vec![(false, receipt.clone())];
    for (path, value) in [
        ("/version", json!(2)),
        ("/processClosureVerified", json!(false)),
        ("/workspace/instanceId", json!("other")),
        ("/workspace/path", json!("/other")),
        ("/workspace/hostId", json!("ssh")),
    ] {
        let mut invalid = receipt.clone();
        *invalid.pointer_mut(path).unwrap() = value;
        cases.push((true, invalid));
    }
    for (online, receipt) in cases {
        let remote = Remote {
            receipt,
            online,
            scripts: Mutex::new(vec![]),
        };
        assert!(retire(&store, &workspace, &remote).await.is_err());
        assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
        assert!(store
            .workspace_retirement_receipt(&workspace.id, &workspace.instance_id)
            .await
            .unwrap()
            .is_none());
    }
}

#[tokio::test]
async fn automation_scope_is_carried_in_the_owner_command_with_local_identity() {
    let (_directory, store, workspace, receipt) = fixture().await;
    let remote = Remote {
        receipt,
        online: true,
        scripts: Mutex::new(vec![]),
    };
    let mut owner = workspace.clone();
    owner.host_id = LOCAL_HOST_ID.into();
    let scope = alera_core::runtime::RemoteAutomationCleanup {
        run_id: "run'with quote".into(),
        workspace: owner,
        tab_ids: vec!["owned-tab".into()],
    };
    retire_scoped(&store, &workspace, &remote, Some(&scope), false)
        .await
        .unwrap();
    let encoded =
        base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&scope).unwrap());
    {
        let scripts = remote.scripts.lock().unwrap();
        assert_eq!(scripts.len(), 1);
        assert!(scripts[0].contains(&format!("--automation-cleanup-base64 '{}'", encoded)));
        assert!(!scripts[0].contains("run'with quote"));
    }
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
}

#[tokio::test]
async fn linked_retirement_requires_owner_receipt_before_home_removal() {
    let (directory, store, mut workspace, _) = fixture().await;
    let origin = workspace.path.clone();
    workspace.id = "linked-task".into();
    workspace.instance_id = "linked-instance".into();
    let path = directory.path().join("linked-task");
    std::fs::create_dir(&path).unwrap();
    workspace.path = path.to_string_lossy().into_owned();
    workspace.kind = WorkspaceKind::Linked;
    store
        .insert_workspace_with_repository(workspace.clone(), &origin)
        .await
        .unwrap();
    assert!(
        crate::remote_managed_workspace_remove::has_registered_remote_checkout(&store, &workspace)
            .await
            .unwrap()
    );
    let mut owner = workspace.clone();
    owner.host_id = LOCAL_HOST_ID.into();
    let remote = Remote {
        receipt: json!({"version":1,"workspace":owner,"processClosureVerified":false}),
        online: true,
        scripts: Mutex::default(),
    };
    let mut request = crate::managed_workspace::ManagedWorkspaceRemoveRequest {
        id: workspace.id.clone(),
        delete_branch: Some(false),
        active_workspace_id: None,
        close_sessions: false,
    };
    let unconfirmed =
        crate::remote_managed_workspace_remove::remove_remote_managed_workspace_request(
            &store, &request, &workspace, &remote,
        )
        .await
        .unwrap_err();
    assert!(unconfirmed.to_string().contains("--close-sessions"));
    assert!(remote.scripts.lock().unwrap().is_empty());
    request.close_sessions = true;
    assert!(
        crate::remote_managed_workspace_remove::remove_remote_managed_workspace_request(
            &store, &request, &workspace, &remote
        )
        .await
        .is_err()
    );
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
    let remote = Remote {
        receipt: json!({"version":1,"workspace":owner,"processClosureVerified":true}),
        online: true,
        scripts: Mutex::default(),
    };
    crate::remote_managed_workspace_remove::remove_remote_managed_workspace_request(
        &store, &request, &workspace, &remote,
    )
    .await
    .unwrap();
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_none());
    let scripts = remote.scripts.lock().unwrap();
    assert_eq!(scripts.len(), 1);
    assert!(scripts[0].contains("retire-owner-workspace"));
    assert!(!scripts[0].contains("--delete-branch"));
    assert!(!scripts[0].contains("worktree remove"));
}
