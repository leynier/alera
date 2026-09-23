use super::*;
use alera_core::runtime::{
    Project, ProjectKind, SshTarget, WorkspaceKind, WorkspaceRelocationIntent,
    WorkspaceRelocationPhase, WorkspaceStatus,
};
use std::collections::VecDeque;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};

struct Remote {
    responses: Mutex<VecDeque<Result<Value>>>,
    scripts: Mutex<Vec<String>>,
}

impl RemoteHostExecutor for Remote {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(&self, _: &SshTarget, _: bool, script: &str) -> Result<String> {
        self.scripts.lock().unwrap().push(script.into());
        self.responses
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected remote command")
            .map(|response| response.to_string())
    }
}

pub(crate) async fn fixture() -> (
    tempfile::TempDir,
    RuntimeStore,
    RemoteWorkspaceRelocationIntent,
    Value,
    Value,
) {
    let root = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(root.path()).await.unwrap();
    let now = chrono::Utc::now();
    store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: "/home/project".into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .register_project_checkout("project", "ssh", "/owner/project")
        .await
        .unwrap();
    let source = Workspace {
        id: "task".into(),
        instance_id: "task-instance".into(),
        project_id: "project".into(),
        host_id: "ssh".into(),
        name: "Task".into(),
        path: "/owner/project".into(),
        branch: Some("main".into()),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Main,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: true,
        is_archived: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    };
    store.insert_workspace(source.clone()).await.unwrap();
    let target: SshTarget = serde_json::from_value(json!({"id":"ssh","alias":"Fixture","host":"test.invalid","port":22,"username":"fixture","authKind":"agent","createdAt":now,"updatedAt":now,"installDir":"/owner/sidecar","bootstrapStatus":"installed"})).unwrap();
    store.upsert_ssh_target(target).await.unwrap();
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            WorkspaceRelocationIntent {
                workspace_id: source.id.clone(),
                to_project_checkout: false,
                destination_path: None,
                branch: Some("topic".into()),
                replacement_branch: None,
                move_changes: false,
                shared_impact_confirmed: true,
            },
        )
        .await
        .unwrap();
    let mut source = source;
    source.host_id = LOCAL_HOST_ID.into();
    let mut destination = source.clone();
    destination.kind = WorkspaceKind::Linked;
    destination.path = "/owner/managed/topic".into();
    destination.branch = Some("topic".into());
    let mut journal = WorkspaceRelocation {
        id: pending.id.clone(),
        source: source.clone(),
        destination: destination.clone(),
        repository_path: source.path.clone(),
        original_branch: "main".into(),
        source_commit: "1111111111111111111111111111111111111111".into(),
        replacement_branch: None,
        replacement_commit: None,
        destination_original_branch: None,
        destination_original_commit: None,
        move_changes: false,
        recovery_stash_oid: None,
        phase: WorkspaceRelocationPhase::Prepared,
    };
    let preparation = json!({"version":1,"prepared":true,"workspace":source,"relocation":journal});
    journal.phase = WorkspaceRelocationPhase::Completed;
    let completion = json!({"version":1,"workspace":destination,"relocation":journal,"result":{"workspace":destination,"setupReport":null,"deferredSetupCommand":null}});
    (root, store, pending, preparation, completion)
}

#[tokio::test]
async fn lost_owner_response_retains_preparation_and_retries_after_reopen() {
    let (root, store, pending, preparation, completion) = fixture().await;
    let remote = Remote {
        responses: Mutex::new(VecDeque::from([
            Ok(preparation),
            Err(anyhow::anyhow!("connection lost")),
            Ok(completion),
        ])),
        scripts: Mutex::new(vec![]),
    };
    assert!(execute(&store, pending.clone(), &remote, || Ok(()))
        .await
        .is_err());
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let retained = reopened
        .find_remote_workspace_relocation_intent(&pending.id)
        .await
        .unwrap()
        .unwrap();
    assert!(retained.owner_preparation.is_some());
    assert_eq!(
        reopened.find_workspace("task").await.unwrap().unwrap().path,
        "/owner/project"
    );
    let result = execute(&reopened, retained, &remote, || Ok(()))
        .await
        .unwrap();
    assert_eq!(result["workspace"]["hostId"], "ssh");
    assert_eq!(result["workspace"]["path"], "/owner/managed/topic");
    let scripts = remote.scripts.lock().unwrap();
    assert_eq!(scripts.len(), 3);
    assert!(scripts[0].contains("--prepare-only"));
    assert!(!scripts[2].contains("--prepare-only"));
    assert_eq!(scripts[1], scripts[2]);
}

#[tokio::test]
async fn disconnected_home_buffer_proof_retains_owner_receipt_without_moving_home() {
    let (_root, store, pending, preparation, completion) = fixture().await;
    let remote = Remote {
        responses: Mutex::new(VecDeque::from([
            Ok(preparation),
            Ok(completion.clone()),
            Ok(completion),
        ])),
        scripts: Mutex::new(vec![]),
    };
    let verifications = AtomicUsize::new(0);
    assert!(execute(&store, pending.clone(), &remote, || {
        if verifications.fetch_add(1, Ordering::SeqCst) == 2 {
            bail!("buffer client disconnected");
        }
        Ok(())
    })
    .await
    .is_err());
    assert!(store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        store.find_workspace("task").await.unwrap().unwrap().path,
        "/owner/project"
    );
    let retained = store
        .find_remote_workspace_relocation_intent(&pending.id)
        .await
        .unwrap()
        .unwrap();
    execute(&store, retained, &remote, || Ok(())).await.unwrap();
    assert_eq!(
        store.find_workspace("task").await.unwrap().unwrap().path,
        "/owner/managed/topic"
    );
}

#[tokio::test]
async fn preparation_cannot_impersonate_completion() {
    let (_root, store, pending, preparation, mut completion) = fixture().await;
    completion["prepared"] = json!(true);
    let remote = Remote {
        responses: Mutex::new(VecDeque::from([Ok(preparation), Ok(completion)])),
        scripts: Mutex::new(vec![]),
    };
    assert!(execute(&store, pending.clone(), &remote, || Ok(()))
        .await
        .is_err());
    assert!(store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store.find_workspace("task").await.unwrap().unwrap().path,
        "/owner/project"
    );
}
