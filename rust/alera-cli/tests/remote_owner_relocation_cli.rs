use alera_core::child_process::windowless_command;
use base64::Engine;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

fn cli(state: &Path, group: &str, args: &[&str]) -> std::process::Output {
    windowless_command(env!("CARGO_BIN_EXE_alera"))
        .arg(group)
        .arg("--runtime-dir")
        .arg(state)
        .arg("--json")
        .args(args)
        .env_remove("ALERA_WORKSPACE_ID")
        .env_remove("ALERA_TERMINAL_HANDLE")
        .output()
        .unwrap()
}

fn success(output: std::process::Output) -> Value {
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
        let _ = cli(&self.0, "runtime", &["stop", "--force"]);
    }
}

fn relocate(state: &Path, payload: &Value) -> std::process::Output {
    let encoded =
        base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(payload).unwrap());
    cli(
        state,
        "project",
        &[
            "relocate-owner-workspace",
            "--state-dir",
            state.to_str().unwrap(),
            "--request-base64",
            &encoded,
        ],
    )
}

fn repository(path: &Path) {
    let mut options = git2::RepositoryInitOptions::new();
    options.initial_head("main");
    let repository = git2::Repository::init_opts(path, &options).unwrap();
    std::fs::write(path.join("retained.txt"), "original\n").unwrap();
    let mut index = repository.index().unwrap();
    index.add_path(Path::new("retained.txt")).unwrap();
    index.write().unwrap();
    let tree = repository.find_tree(index.write_tree().unwrap()).unwrap();
    let signature = git2::Signature::now("Fixture", "fixture@example.invalid").unwrap();
    repository
        .commit(Some("HEAD"), &signature, &signature, "fixture", &tree, &[])
        .unwrap();
}

#[tokio::test]
async fn owner_relocation_keeps_identity_retries_and_rejects_superseded_receipts() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let state = root.path().join("owner");
    let managed_root = root.path().join("managed");
    std::fs::create_dir(&managed_root).unwrap();
    alera_core::runtime::RuntimeStore::open(&state)
        .await
        .unwrap()
        .set_workspace_directory(Some(managed_root.to_str().unwrap()))
        .await
        .unwrap();
    let _guard = HostGuard(state.clone());
    success(cli(&state, "runtime", &["start"]));
    let registration = success(cli(
        &state,
        "project",
        &[
            "add",
            "--name",
            "Task",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ));
    let workspace = registration["initialWorkspace"].clone();
    let project_id = registration["project"]["id"].as_str().unwrap();
    let sibling = success(cli(
        &state,
        "workspace",
        &["add", "--project-id", project_id, "--name", "Neighbor"],
    ));
    let linked = managed_root.join("linked");
    std::fs::write(folder.join("retained.txt"), "shared pending content\n").unwrap();
    let request = json!({
        "workspace":workspace,"relocationId":uuid::Uuid::new_v4(),
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":false,
            "destinationPath":linked,"branch":"topic","replacementBranch":null,
            "moveChanges":false,"sharedImpactConfirmed":true},
    });
    let off = success(relocate(&state, &request));
    assert_eq!(off["version"], 1);
    assert_eq!(off["relocation"]["phase"], "completed");
    for field in ["id", "instanceId", "name"] {
        assert_eq!(off["workspace"][field], workspace[field]);
    }
    assert_eq!(
        std::fs::read_to_string(folder.join("retained.txt")).unwrap(),
        "shared pending content\n"
    );
    assert_eq!(
        std::fs::read_to_string(linked.join("retained.txt")).unwrap(),
        "original\n"
    );
    assert_eq!(
        alera_core::git::current_branch(folder.to_str().unwrap()).unwrap(),
        "main"
    );
    let owner_metadata = base64::engine::general_purpose::STANDARD.encode(
        serde_json::to_vec(
            &json!({"project":registration["project"],"workspace":off["workspace"]}),
        )
        .unwrap(),
    );
    let reconnected = success(cli(
        &state,
        "project",
        &[
            "register-owner-workspace",
            "--state-dir",
            state.to_str().unwrap(),
            "--metadata-base64",
            &owner_metadata,
        ],
    ));
    assert_eq!(reconnected["id"], workspace["id"]);
    assert_eq!(reconnected["instanceId"], workspace["instanceId"]);
    let repeated = success(relocate(&state, &request));
    assert_eq!(repeated["relocation"], off["relocation"]);
    let mut different_choices = request.clone();
    different_choices["intent"]["branch"] = json!("other-topic");
    assert!(!relocate(&state, &different_choices).status.success());

    std::fs::write(folder.join("retained.txt"), "original\n").unwrap();
    std::fs::write(linked.join("retained.txt"), "return pending content\n").unwrap();
    let on_request = json!({
        "workspace":off["workspace"],"relocationId":uuid::Uuid::new_v4(),
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":true,
            "destinationPath":null,"branch":null,"replacementBranch":null,
            "moveChanges":true,"sharedImpactConfirmed":true},
    });
    let on = success(relocate(&state, &on_request));
    for field in ["id", "instanceId", "name", "path"] {
        assert_eq!(on["workspace"][field], workspace[field]);
    }
    assert_eq!(on["relocation"]["phase"], "completed");
    assert!(!linked.exists());
    assert_eq!(
        std::fs::read_to_string(folder.join("retained.txt")).unwrap(),
        "return pending content\n"
    );
    assert_eq!(
        alera_core::git::current_branch(folder.to_str().unwrap()).unwrap(),
        "topic"
    );
    assert_eq!(
        success(relocate(&state, &on_request))["relocation"],
        on["relocation"]
    );
    assert!(!relocate(&state, &request).status.success());
    let tasks = success(cli(
        &state,
        "workspace",
        &["list", "--project-id", project_id],
    ));
    let sibling = sibling.get("workspace").unwrap_or(&sibling);
    let retained = tasks["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["id"] == sibling["id"])
        .unwrap();
    assert_eq!(retained["instanceId"], sibling["instanceId"]);
    assert_eq!(retained["path"], sibling["path"]);
}

#[tokio::test]
async fn never_started_enrollment_starts_only_a_verified_owner_and_survives_a_retry() {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("project");
    repository(&folder);
    let source_state = root.path().join("source");
    let registration = success(cli(
        &source_state,
        "project",
        &[
            "add",
            "--name",
            "Unopened",
            "--repo-path",
            folder.to_str().unwrap(),
        ],
    ));
    let workspace = registration["initialWorkspace"].clone();
    let state = root.path().join("owner");
    let managed = root.path().join("managed");
    std::fs::create_dir(&managed).unwrap();
    let owner = alera_core::runtime::RuntimeStore::open(&state)
        .await
        .unwrap();
    owner
        .set_workspace_directory(Some(managed.to_str().unwrap()))
        .await
        .unwrap();
    let _guard = HostGuard(state.clone());
    let metadata = base64::engine::general_purpose::STANDARD.encode(
        serde_json::to_vec(&json!({"project":registration["project"],"workspace":workspace}))
            .unwrap(),
    );
    let request = json!({"workspace":workspace,"relocationId":uuid::Uuid::new_v4(),
        "intent":{"workspaceId":workspace["id"],"toProjectCheckout":false,"destinationPath":managed.join("task"),"branch":"enrolled-topic","replacementBranch":null,"moveChanges":false,"sharedImpactConfirmed":true}});
    let encoded =
        base64::engine::general_purpose::STANDARD.encode(serde_json::to_vec(&request).unwrap());
    let perform = || {
        cli(
            &state,
            "project",
            &[
                "relocate-owner-workspace",
                "--state-dir",
                state.to_str().unwrap(),
                "--request-base64",
                &encoded,
                "--enroll-never-started-base64",
                &metadata,
            ],
        )
    };
    let first = success(perform());
    assert_eq!(first["workspace"]["instanceId"], workspace["instanceId"]);
    success(cli(&state, "runtime", &["stop", "--force"]));
    assert_eq!(success(perform())["relocation"], first["relocation"]);
    owner
        .record_workspace_terminal_launch(workspace["id"].as_str().unwrap())
        .await
        .unwrap();
    success(cli(&state, "runtime", &["stop", "--force"]));
    let rejected = perform();
    assert!(!rejected.status.success());
    assert!(String::from_utf8_lossy(&rejected.stderr).contains("earlier terminal launch"));
    assert_eq!(
        owner
            .find_workspace(workspace["id"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .path,
        managed.join("task").to_str().unwrap()
    );
}

#[path = "support/owner_relocation_preparation_cases.rs"]
mod preparation_cases;

#[path = "support/owner_recovery_inspection_cases.rs"]
mod recovery_inspection_cases;

#[path = "support/owner_setup_control_cases.rs"]
mod setup_control_cases;
