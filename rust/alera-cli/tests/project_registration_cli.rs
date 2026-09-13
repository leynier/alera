use alera_core::child_process::windowless_command;
use alera_core::runtime::RuntimeStore;
use serde_json::Value;
use std::path::Path;

fn cli(root: &Path, group: &str, args: &[&str]) -> std::process::Output {
    windowless_command(env!("CARGO_BIN_EXE_alera"))
        .arg(group)
        .arg("--runtime-dir")
        .arg(root)
        .arg("--json")
        .args(args)
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_TERMINAL_HANDLE")
        .output()
        .unwrap()
}

fn register(root: &Path, folder: &Path, id: &str) -> Value {
    let output = cli(
        root,
        "project",
        &[
            "add",
            "--id",
            id,
            "--name",
            "Task project",
            "--repo-path",
            folder.to_str().unwrap(),
            "--kind",
            "folder",
        ],
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

struct HostGuard(std::path::PathBuf);
impl Drop for HostGuard {
    fn drop(&mut self) {
        let _ = cli(&self.0, "runtime", &["stop", "--force"]);
    }
}

#[tokio::test]
async fn registration_creates_initial_task_once_with_and_without_a_live_host() {
    for live in [false, true] {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().join("state");
        let folder = directory.path().join("project");
        std::fs::create_dir(&folder).unwrap();
        let _guard = HostGuard(root.clone());
        if live {
            assert!(cli(&root, "runtime", &["start"]).status.success());
        }
        let result = register(&root, &folder, "explicit-project");
        assert_eq!(result["project"]["id"], "explicit-project");
        assert_eq!(result["created"], true);
        let task_id = result["initialWorkspace"]["id"].as_str().unwrap();
        let store = RuntimeStore::open(&root).await.unwrap();
        assert_eq!(
            store
                .list_workspaces("explicit-project")
                .await
                .unwrap()
                .len(),
            1
        );
        assert!(store
            .find_project_checkout("explicit-project", "local")
            .await
            .unwrap()
            .is_some());
        store.remove_workspace(task_id, true).await.unwrap();
        let again = register(&root, &folder, "explicit-project");
        assert_eq!(again["created"], false);
        assert!(again["initialWorkspace"].is_null());
        assert!(store
            .list_workspaces("explicit-project")
            .await
            .unwrap()
            .is_empty());
    }
}

#[tokio::test]
async fn registration_rejects_reusing_an_id_for_another_folder() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("state");
    let first = directory.path().join("first");
    let second = directory.path().join("second");
    std::fs::create_dir(&first).unwrap();
    std::fs::create_dir(&second).unwrap();
    register(&root, &first, "retained");
    let output = cli(
        &root,
        "project",
        &[
            "add",
            "--id",
            "retained",
            "--name",
            "Replacement",
            "--repo-path",
            second.to_str().unwrap(),
            "--kind",
            "folder",
        ],
    );
    assert!(!output.status.success());
    let store = RuntimeStore::open(&root).await.unwrap();
    assert_eq!(store.list_projects().await.unwrap().len(), 1);
    assert_eq!(store.list_workspaces("retained").await.unwrap().len(), 1);
    assert_eq!(
        store.find_project("retained").await.unwrap().unwrap().name,
        "Task project"
    );
}
