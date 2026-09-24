use alera_core::child_process::windowless_command;
use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceRelocationIntent, WorkspaceTabRecord};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

fn cli(state: &Path, group: &str, args: &[&str]) -> Value {
    let output = windowless_command(env!("CARGO_BIN_EXE_alera"))
        .arg(group)
        .arg("--runtime-dir")
        .arg(state)
        .arg("--json")
        .args(args)
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_TERMINAL_HANDLE")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

struct HostGuard(PathBuf);
impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args(["runtime", "--runtime-dir"])
            .arg(&self.0)
            .args(["stop", "--force"])
            .output();
    }
}

#[tokio::test]
async fn restarting_home_preserves_pending_remote_terminal_without_launching_it() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    git2::Repository::init(&folder).unwrap();
    let state = root.path().join("home");
    let _guard = HostGuard(state.clone());
    let registered = cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Task",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    );
    let mut workspace: Workspace =
        serde_json::from_value(registered["initialWorkspace"].clone()).unwrap();
    let store = RuntimeStore::open(&state).await.unwrap();
    workspace.host_id = "isolated-ssh".into();
    store
        .register_project_checkout(&workspace.project_id, &workspace.host_id, &workspace.path)
        .await
        .unwrap();
    store.upsert_workspace(workspace.clone()).await.unwrap();
    let now = chrono::Utc::now();
    let tab = WorkspaceTabRecord {
        id: "retained-terminal".into(),
        workspace_id: workspace.id.clone(),
        kind: "terminal".into(),
        title: "Retained".into(),
        created_at: now,
        updated_at: now,
        payload: json!({"spawnOnCreate":true,"terminalSessionId":"retained-session","initialCommand":"preserve this command","initialCommandOnce":true}),
    };
    store.upsert_workspace_tab(tab.clone()).await.unwrap();
    let tab = store.find_workspace_tab(&tab.id).await.unwrap().unwrap();
    let relocation_id = uuid::Uuid::new_v4().to_string();
    store
        .begin_remote_workspace_relocation(
            &relocation_id,
            &workspace,
            WorkspaceRelocationIntent {
                workspace_id: workspace.id.clone(),
                to_project_checkout: false,
                destination_path: Some(root.path().join("linked").to_string_lossy().into_owned()),
                branch: Some("topic".into()),
                replacement_branch: None,
                move_changes: false,
                shared_impact_confirmed: true,
            },
        )
        .await
        .unwrap();
    for _ in 0..2 {
        cli(&state, "runtime", &["start"]);
        assert_eq!(
            store.find_workspace_tab(&tab.id).await.unwrap().unwrap(),
            tab
        );
        assert_eq!(
            store
                .workspace_terminal_launch_attempted(&workspace.id, &workspace.instance_id)
                .await
                .unwrap(),
            Some(false)
        );
        assert_eq!(
            store
                .pending_workspace_checkout_relocation(&workspace.id)
                .await
                .unwrap()
                .as_deref(),
            Some(relocation_id.as_str())
        );
        cli(&state, "runtime", &["stop", "--force"]);
    }
    assert_eq!(
        store
            .find_workspace(&workspace.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        workspace.path
    );
}
