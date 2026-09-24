use super::*;

fn inspect(state: &Path, workspace: &Value) -> std::process::Output {
    cli(
        state,
        "project",
        &[
            "inspect-owner-recovery",
            "--state-dir",
            state.to_str().unwrap(),
            "--workspace-id",
            workspace["id"].as_str().unwrap(),
            "--instance-id",
            workspace["instanceId"].as_str().unwrap(),
            "--project-id",
            workspace["projectId"].as_str().unwrap(),
        ],
    )
}

#[test]
fn absent_owner_inspection_does_not_create_a_runtime_or_database() {
    let root = tempfile::tempdir().unwrap();
    let state = root.path().join("absent");
    let result = inspect(
        &state,
        &json!({"id":"task","instanceId":"instance","projectId":"project"}),
    );
    assert!(!result.status.success());
    assert!(!state.exists());
}

#[tokio::test]
async fn stopped_owner_inspection_retains_journal_files_and_runtime_state() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let state = root.path().join("owner");
    let _guard = HostGuard(state.clone());
    let registration = success(cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Recovery",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ));
    let workspace = registration["initialWorkspace"].clone();
    success(cli(&state, "runtime", &["stop", "--force"]));
    let store = alera_core::runtime::RuntimeStore::open(&state)
        .await
        .unwrap();
    let journal = store
        .prepare_local_workspace_relocation_with_id(
            alera_core::runtime::WorkspaceRelocationIntent {
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
    store.pool().close().await;
    let before = std::fs::read(state.join("runtime.sqlite")).unwrap();
    let result = success(inspect(&state, &workspace));
    assert_eq!(result["version"], 1);
    assert_eq!(result["workspace"]["instanceId"], workspace["instanceId"]);
    assert_eq!(result["items"][0]["relocation"]["id"], journal.id);
    assert_eq!(result["items"][0]["relocation"]["phase"], "prepared");
    assert_eq!(result["platform"], std::env::consts::OS);
    assert_eq!(std::fs::read(state.join("runtime.sqlite")).unwrap(), before);
    assert!(!state.join("runtime-host.json").exists());
    assert!(!root.path().join("linked").exists());
    assert_eq!(
        std::fs::read_to_string(folder.join("retained.txt")).unwrap(),
        "original\n"
    );
    let mut wrong = workspace.clone();
    wrong["instanceId"] = json!("another-instance");
    assert!(!inspect(&state, &wrong).status.success());
    wrong = workspace.clone();
    wrong["projectId"] = json!("another-project");
    assert!(!inspect(&state, &wrong).status.success());
    assert_eq!(std::fs::read(state.join("runtime.sqlite")).unwrap(), before);
    assert!(!state.join("runtime-host.json").exists());
    let read_only = alera_core::runtime::RuntimeStore::open_read_only(&state)
        .await
        .unwrap();
    assert!(read_only
        .set_workspace_directory(Some("/must-not-write"))
        .await
        .is_err());
}
