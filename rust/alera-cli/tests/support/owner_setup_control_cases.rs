use super::*;
use alera_core::runtime::{
    ProjectConfig, RelocationSetupReceipt, RuntimeStore, WorkspaceRelocationIntent,
};

async fn fixture() -> (
    tempfile::TempDir,
    HostGuard,
    RuntimeStore,
    Value,
    RelocationSetupReceipt,
) {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let state = root.path().join("owner");
    let guard = HostGuard(state.clone());
    let workspace = success(cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Setup",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ))["initialWorkspace"]
        .clone();
    let store = RuntimeStore::open(&state).await.unwrap();
    let journal = store
        .prepare_local_workspace_relocation_with_id(
            WorkspaceRelocationIntent {
                workspace_id: workspace["id"].as_str().unwrap().into(),
                to_project_checkout: false,
                destination_path: Some(root.path().join("linked").to_str().unwrap().into()),
                branch: Some("topic".into()),
                replacement_branch: None,
                move_changes: false,
                shared_impact_confirmed: true,
            },
            Some(uuid::Uuid::new_v4().to_string()),
        )
        .await
        .unwrap();
    let receipt = store
        .prepare_relocation_setup(&journal.id, &ProjectConfig::default())
        .await
        .unwrap();
    let moved = store
        .resume_local_workspace_relocation(&journal.id, || Ok(()))
        .await
        .unwrap();
    (
        root,
        guard,
        store,
        serde_json::to_value(moved).unwrap(),
        receipt,
    )
}

fn start_runtime(state: &Path) {
    success(cli(state, "runtime", &["start"]));
}

fn control(
    state: &Path,
    workspace: &Value,
    receipt: &RelocationSetupReceipt,
    action: &str,
) -> std::process::Output {
    let mut args = vec![
        "control-owner-setup",
        "--state-dir",
        state.to_str().unwrap(),
        "--workspace-id",
        workspace["id"].as_str().unwrap(),
        "--instance-id",
        workspace["instanceId"].as_str().unwrap(),
        "--project-id",
        workspace["projectId"].as_str().unwrap(),
        "--relocation-id",
        &receipt.relocation_id,
        "--action",
        action,
    ];
    if let Some(attempt) = &receipt.attempt_id {
        args.extend(["--attempt-id", attempt]);
    }
    cli(state, "project", &args)
}

#[tokio::test]
async fn owner_setup_run_replays_its_receipt_and_rejects_another_identity() {
    let (_root, guard, store, workspace, receipt) = fixture().await;
    start_runtime(&guard.0);
    let completed = success(control(&guard.0, &workspace, &receipt, "run"));
    assert_eq!(completed["action"], "run");
    assert!(completed["setup"]["attemptId"].is_string());
    assert_eq!(
        success(control(&guard.0, &workspace, &receipt, "run"))["setup"],
        completed["setup"]
    );
    for field in ["instanceId", "projectId"] {
        let mut wrong = workspace.clone();
        wrong[field] = json!("other");
        assert!(!control(&guard.0, &wrong, &receipt, "run").status.success());
    }
    assert_eq!(
        serde_json::to_value(
            store
                .find_relocation_setup(&receipt.relocation_id)
                .await
                .unwrap()
                .unwrap()
        )
        .unwrap(),
        completed["setup"]
    );
}

#[tokio::test]
async fn owner_setup_cancel_and_recover_require_a_live_owner_and_exact_attempt() {
    let (_root, guard, store, workspace, receipt) = fixture().await;
    let claimed = store.claim_relocation_setup(&receipt).await.unwrap();
    assert!(!control(&guard.0, &workspace, &claimed, "cancel")
        .status
        .success());
    assert!(!guard.0.join("runtime-host.json").exists());
    assert!(!store.setup_cancellation_requested(&claimed).await.unwrap());
    start_runtime(&guard.0);
    let mut wrong = claimed.clone();
    wrong.attempt_id = Some(uuid::Uuid::new_v4().to_string());
    assert!(!control(&guard.0, &workspace, &wrong, "cancel")
        .status
        .success());
    assert!(!store.setup_cancellation_requested(&claimed).await.unwrap());
    let cancelled = success(control(&guard.0, &workspace, &claimed, "cancel"));
    assert_eq!(cancelled["result"]["cancellationRequested"], true);
    assert_eq!(cancelled["result"]["processesClosed"], false);
    let recovered = success(control(&guard.0, &workspace, &claimed, "recover"));
    assert!(recovered["setup"]["report"].is_object());
    assert_eq!(
        success(control(&guard.0, &workspace, &claimed, "recover"))["setup"],
        recovered["setup"]
    );
}

#[tokio::test]
async fn owner_setup_recovery_cannot_clear_unknown_process_closure() {
    let (_root, guard, store, workspace, receipt) = fixture().await;
    start_runtime(&guard.0);
    let claimed = store.claim_relocation_setup(&receipt).await.unwrap();
    let boot = if cfg!(target_os = "linux") {
        Some(
            std::fs::read_to_string("/proc/sys/kernel/random/boot_id")
                .unwrap()
                .trim()
                .to_string(),
        )
    } else {
        None
    };
    store
        .begin_setup_root_process(&claimed, 0, std::env::consts::OS, boot.as_deref())
        .await
        .unwrap();
    assert!(!control(&guard.0, &workspace, &claimed, "recover")
        .status
        .success());
    assert!(store
        .find_relocation_setup(&receipt.relocation_id)
        .await
        .unwrap()
        .unwrap()
        .report
        .is_none());
    assert!(!control(&guard.0, &workspace, &claimed, "run")
        .status
        .success());
}
