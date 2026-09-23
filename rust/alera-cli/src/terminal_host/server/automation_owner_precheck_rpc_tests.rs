use super::*;
use crate::terminal_host::server::ServerCommand;
use alera_core::runtime::{
    OwnerAutomationPrecheckOutcome, OwnerAutomationPrecheckRequest, WorkspaceProcessJobPhase,
};

#[tokio::test]
async fn owner_precheck_rpc_cancel_before_start_prevents_a_delayed_command() {
    let (mut fixture, _) = empty_project().await;
    let request = request(&fixture, "must never execute".into());
    let payload = serde_json::to_value(&request).unwrap();
    let cancelled = fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.cancel", &payload)
        .await
        .unwrap();
    assert_eq!(cancelled["job"]["outcome"]["kind"], "cancelled");
    assert_eq!(cancelled["processes"], serde_json::json!([]));
    for _ in 0..2 {
        let delayed = fixture
            .actor
            .handle_request(1, "automation.ownerPrecheck.start", &payload)
            .await
            .unwrap();
        assert_eq!(delayed, cancelled);
    }
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
}

fn request(fixture: &Harness, command: String) -> OwnerAutomationPrecheckRequest {
    OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        workspace: None,
        origin_id: "fixture-home".into(),
        run_id: "fixture-run".into(),
        project_id: "project-1".into(),
        path: fixture
            .repo_path
            .canonicalize()
            .unwrap()
            .to_str()
            .unwrap()
            .into(),
        precheck: alera_core::runtime::AutomationPrecheck {
            command,
            timeout_seconds: 30,
        },
    }
}

async fn drain(
    fixture: &mut Harness,
    inbox: &mut tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
) {
    let completed = tokio::time::timeout(Duration::from_secs(15), inbox.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        completed,
        ServerCommand::OwnerAutomationPrecheckFinished { .. }
    ));
    fixture.actor.handle(completed).await;
}

#[tokio::test]
async fn owner_precheck_rpc_requires_declaration_and_retries_without_duplicating_execution() {
    let (mut fixture, _) = empty_project().await;
    let marker = fixture.repo_path.join("rpc-count");
    let request = request(
        &fixture,
        format!(
            "printf x >> {}; exit 1",
            crate::ssh_bootstrap::shell_quote(marker.to_str().unwrap())
        ),
    );
    let payload = serde_json::to_value(&request).unwrap();
    let (sender, mut inbox) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = sender;
    fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.start", &payload)
        .await
        .unwrap();
    drain(&mut fixture, &mut inbox).await;
    let rejected = fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.status", &payload)
        .await
        .unwrap();
    assert!(rejected["job"]["attention"]
        .as_str()
        .unwrap()
        .contains("declaration"));
    assert!(rejected["job"]["processId"].is_null());
    assert!(!marker.exists());
    declare(&fixture.repo_path);
    fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.start", &payload)
        .await
        .unwrap();
    drain(&mut fixture, &mut inbox).await;
    let completed = fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.status", &payload)
        .await
        .unwrap();
    assert_eq!(completed["job"]["outcome"]["kind"], "rejected");
    assert!(completed["job"]["attention"].is_null());
    assert_eq!(
        fixture
            .actor
            .handle_request(1, "automation.ownerPrecheck.start", &payload)
            .await
            .unwrap(),
        completed
    );
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
    assert_eq!(std::fs::read_to_string(marker).unwrap(), "x");
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn owner_precheck_rpc_keeps_running_after_disconnect_and_cancels_with_verified_closure() {
    let (mut fixture, _) = empty_project().await;
    declare(&fixture.repo_path);
    let marker = fixture.repo_path.join("rpc-child");
    let request = request(
        &fixture,
        format!(
            "sleep 60 & printf %s \"$!\" > {}; wait",
            crate::ssh_bootstrap::shell_quote(marker.to_str().unwrap())
        ),
    );
    let payload = serde_json::to_value(&request).unwrap();
    let (sender, mut inbox) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = sender;
    fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.start", &payload)
        .await
        .unwrap();
    let started = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if let Some(pid) = std::fs::read_to_string(&marker)
                .ok()
                .and_then(|text| text.parse::<u32>().ok())
            {
                return pid;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;
    fixture.actor.dispose_client(1).await;
    let (handle, _events) = ClientHandle::test_channels();
    fixture.actor.clients.insert(2, local_client(handle));
    let status = tokio::time::timeout(
        Duration::from_secs(1),
        fixture
            .actor
            .handle_request(2, "automation.ownerPrecheck.status", &payload),
    )
    .await;
    fixture
        .actor
        .handle_request(2, "automation.ownerPrecheck.cancel", &payload)
        .await
        .unwrap();
    drain(&mut fixture, &mut inbox).await;
    let job = fixture
        .actor
        .runtime_store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert!(status.unwrap().unwrap()["job"]["outcome"].is_null());
    assert_eq!(job.outcome, Some(OwnerAutomationPrecheckOutcome::Cancelled));
    use crate::process_identity::{
        ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe,
    };
    assert!(matches!(
        SystemProcessIdentityProbe.lookup(started.unwrap()),
        ProcessLookup::Exited
    ));
    let processes = fixture
        .actor
        .runtime_store
        .automation_precheck_processes(job.process_id.as_deref().unwrap())
        .await
        .unwrap();
    assert_eq!(
        processes[0].phase,
        WorkspaceProcessJobPhase::ClosureVerified
    );
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
    assert!(fixture
        .actor
        .runtime_store
        .list_workspaces("project-1")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn owner_precheck_rpc_rejects_mobile_and_unauthenticated_clients() {
    let (mut fixture, _) = empty_project().await;
    let request = request(&fixture, "exit 1".into());
    let payload = serde_json::to_value(&request).unwrap();
    for mobile in [false, true] {
        let client = fixture.actor.clients.get_mut(&1).unwrap();
        client.authenticated = mobile;
        if mobile {
            client.kind = crate::terminal_host::server::ClientKind::Mobile;
        }
        for verb in [
            "automation.ownerPrecheck.start",
            "automation.ownerPrecheck.status",
            "automation.ownerPrecheck.cancel",
        ] {
            assert!(fixture
                .actor
                .handle_request(1, verb, &payload)
                .await
                .is_err());
        }
    }
    assert!(fixture
        .actor
        .runtime_store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .unwrap()
        .is_none());
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
}

#[tokio::test]
async fn linked_owner_rpc_retains_storage_until_verified_command_closure() {
    use alera_core::runtime::AutomationPrecheckWorkspace;
    let mut fixture = harness().await;
    let store = fixture.actor.runtime_store.clone();
    let repo = git2::Repository::init(&fixture.repo_path).unwrap();
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
    let linked = fixture.repo_path.parent().unwrap().join("linked");
    alera_core::git::create_worktree(
        fixture.repo_path.to_str().unwrap(),
        "linked-task",
        linked.to_str().unwrap(),
        "main",
        false,
    )
    .unwrap();
    let linked = linked.canonicalize().unwrap();
    let origin = fixture.repo_path.canonicalize().unwrap();
    let mut task = store.find_workspace("workspace-1").await.unwrap().unwrap();
    task.id = "linked-task".into();
    task.instance_id = "linked-instance".into();
    task.kind = WorkspaceKind::Linked;
    task.path = linked.to_str().unwrap().into();
    store
        .insert_workspace_with_repository(task.clone(), origin.to_str().unwrap())
        .await
        .unwrap();
    declare(&linked);
    let marker = linked.join("count");
    let release = linked.join("release");
    let mut request = request(
        &fixture,
        format!(
            "printf x >> {}; while [ ! -f {} ]; do sleep 0.05; done; exit 1",
            crate::ssh_bootstrap::shell_quote(marker.to_str().unwrap()),
            crate::ssh_bootstrap::shell_quote(release.to_str().unwrap())
        ),
    );
    request.path = task.path.clone();
    request.workspace = Some(AutomationPrecheckWorkspace {
        workspace_id: task.id.clone(),
        instance_id: task.instance_id.clone(),
        kind: task.kind,
        repository_path: Some(origin.to_str().unwrap().into()),
    });
    let payload = serde_json::to_value(&request).unwrap();
    let (sender, mut inbox) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = sender;
    fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.start", &payload)
        .await
        .unwrap();
    let removal = crate::terminal_host::server::runtime_mutations::RuntimeMutationRequest::RemoveManagedWorkspace {
        request: crate::managed_workspace::ManagedWorkspaceRemoveRequest { id: task.id.clone(), delete_branch: Some(false), active_workspace_id: None, close_sessions: true },
    };
    let error = fixture.actor.prepare_runtime_mutation(&removal).await.err();
    let storage_preserved = linked.exists();
    std::fs::write(&release, "continue").unwrap();
    drain(&mut fixture, &mut inbox).await;
    let error = error.expect("active precheck must prevent retirement");
    assert!(error.to_string().contains("precheck"), "{error}");
    assert!(storage_preserved);
    let result = fixture
        .actor
        .handle_request(1, "automation.ownerPrecheck.status", &payload)
        .await
        .unwrap();
    assert_eq!(result["job"]["outcome"]["kind"], "rejected");
    assert_eq!(result["processes"][0]["phase"], "closureVerified");
    assert_eq!(
        result["processes"][0]["workspace"]["instanceId"],
        task.instance_id
    );
    assert_eq!(
        fixture
            .actor
            .handle_request(1, "automation.ownerPrecheck.start", &payload)
            .await
            .unwrap(),
        result
    );
    assert_eq!(std::fs::read_to_string(marker).unwrap(), "x");
    store
        .require_workspace_process_closure(&task.id)
        .await
        .unwrap();
    assert!(store.find_workspace(&task.id).await.unwrap().is_some());
    assert!(store.find_workspace("workspace-1").await.unwrap().is_some());
    assert_eq!(
        alera_core::git::current_branch(origin.to_str().unwrap()).unwrap(),
        "main"
    );
}

#[tokio::test]
async fn owner_rpc_recovers_closed_claims_but_retains_same_boot_uncertainty() {
    for cancel in [false, true] {
        let (mut fixture, _) = empty_project().await;
        let store = fixture.actor.runtime_store.clone();
        let request = request(&fixture, "must not execute".into());
        store
            .register_owner_automation_precheck(&request)
            .await
            .unwrap();
        let boot = crate::relocation_setup_process::current_boot_id().unwrap();
        let process = store
            .claim_owner_automation_precheck(&request, std::env::consts::OS, boot)
            .await
            .unwrap()
            .unwrap();
        let payload = serde_json::to_value(&request).unwrap();
        let verb = if cancel {
            "automation.ownerPrecheck.cancel"
        } else {
            "automation.ownerPrecheck.status"
        };
        let result = fixture
            .actor
            .handle_request(1, verb, &payload)
            .await
            .unwrap();
        assert!(result["job"]["outcome"].is_null());
        assert!(result["job"]["attention"]
            .as_str()
            .unwrap()
            .contains("closure is unverified"));
        assert_eq!(result["processes"][0]["phase"], "launchIntent");
        assert!(fixture.actor.automation_precheck_jobs.is_empty());
        store
            .record_automation_precheck_phase(&process, WorkspaceProcessJobPhase::SpawnFailed)
            .await
            .unwrap();
        let result = fixture
            .actor
            .handle_request(1, "automation.ownerPrecheck.status", &payload)
            .await
            .unwrap();
        assert_eq!(
            result["job"]["outcome"]["kind"],
            if cancel { "cancelled" } else { "failed" }
        );
        assert!(result["job"]["attention"].is_null());
        assert_eq!(
            fixture
                .actor
                .handle_request(1, "automation.ownerPrecheck.start", &payload)
                .await
                .unwrap(),
            result
        );
        assert!(fixture.actor.automation_precheck_jobs.is_empty());
    }
}

#[tokio::test]
async fn owner_rpc_recovers_persisted_native_closure_without_inventing_a_result() {
    let (mut fixture, _) = empty_project().await;
    let store = fixture.actor.runtime_store.clone();
    let request = request(&fixture, "exit 1".into());
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    let completed = crate::terminal_host::server::automation_dispatch::automation_local_precheck::run_owner_precheck(&store, &request).await.unwrap();
    let evidence = store
        .automation_precheck_processes(completed.process_id.as_deref().unwrap())
        .await
        .unwrap();
    assert_eq!(evidence[0].phase, WorkspaceProcessJobPhase::ClosureVerified);
    // Model interruption after closure persisted but before the outcome committed.
    sqlx::query("UPDATE ownerAutomationPrechecks SET resultJson = NULL WHERE id = ?")
        .bind(&request.operation_id)
        .execute(store.pool())
        .await
        .unwrap();
    let result = fixture
        .actor
        .handle_request(
            1,
            "automation.ownerPrecheck.status",
            &serde_json::to_value(&request).unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(result["job"]["outcome"]["kind"], "failed");
    assert!(result["job"]["attention"].is_null());
    assert_eq!(result["processes"], serde_json::to_value(evidence).unwrap());
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
}
