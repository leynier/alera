use std::path::{Path, PathBuf};
use std::process::Output;

use alera_core::child_process::windowless_command;
use serde_json::Value;

struct RuntimeGuard {
    runtime_dir: PathBuf,
}

impl Drop for RuntimeGuard {
    fn drop(&mut self) {
        let _ = windowless_command(env!("CARGO_BIN_EXE_alera"))
            .args([
                "runtime",
                "--runtime-dir",
                self.runtime_dir.to_str().unwrap(),
                "stop",
                "--force",
            ])
            .output();
    }
}

fn run(runtime_dir: &Path, args: &[&str]) -> Output {
    windowless_command(env!("CARGO_BIN_EXE_alera"))
        .arg("agent-profile")
        .arg("--runtime-dir")
        .arg(runtime_dir)
        .arg("--json")
        .args(args)
        .output()
        .expect("failed to run alera agent-profile")
}

fn success_json(runtime_dir: &Path, args: &[&str]) -> Value {
    let output = run(runtime_dir, args);
    assert!(
        output.status.success(),
        "command failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("command did not return JSON")
}

#[test]
fn agent_profile_cli_manages_the_complete_catalog() {
    let temp = tempfile::tempdir().unwrap();
    let _guard = RuntimeGuard {
        runtime_dir: temp.path().to_path_buf(),
    };

    let first = success_json(
        temp.path(),
        &[
            "create",
            "--name",
            "Codex Sol",
            "--agent-type",
            "codex",
            "--launch-mode",
            "command",
            "--command",
            "codex --search",
            "--quota-group",
            "personal",
        ],
    );
    let first_id = first["id"].as_str().unwrap().to_string();
    assert_eq!(first["revision"], 0);

    let risky = run(
        temp.path(),
        &[
            "create",
            "--name",
            "Managed Codex",
            "--agent-type",
            "codex",
            "--launch-mode",
            "managed",
            "--managed-config",
            r#"{"approvalPolicy":"never"}"#,
        ],
    );
    assert!(!risky.status.success());
    assert!(String::from_utf8_lossy(&risky.stderr).contains("--confirm-reduced-protections"));

    let second = success_json(
        temp.path(),
        &[
            "create",
            "--name",
            "Managed Codex",
            "--agent-type",
            "codex",
            "--launch-mode",
            "managed",
            "--managed-config",
            r#"{"approvalPolicy":"never"}"#,
            "--confirm-reduced-protections",
        ],
    );
    let second_id = second["id"].as_str().unwrap().to_string();

    let updated = success_json(
        temp.path(),
        &[
            "update",
            "--profile-name",
            "codex sol",
            "--expected-revision",
            "0",
            "--description",
            "Backend implementation",
            "--clear-quota-group",
        ],
    );
    assert_eq!(updated["revision"], 1);
    assert_eq!(updated["description"], "Backend implementation");
    assert!(updated["quotaGroup"].is_null());

    let stale = run(
        temp.path(),
        &[
            "update",
            "--profile-id",
            &first_id,
            "--expected-revision",
            "0",
            "--description",
            "Stale update",
        ],
    );
    assert!(!stale.status.success());
    assert!(String::from_utf8_lossy(&stale.stderr).contains("revision conflict"));

    let reordered = success_json(
        temp.path(),
        &["reorder", "--id", &second_id, "--id", &first_id],
    );
    assert_eq!(reordered["items"][0]["id"], second_id);
    assert_eq!(reordered["items"][1]["id"], first_id);

    let first_revision = reordered["items"][1]["revision"].as_i64().unwrap();
    let first_revision_text = first_revision.to_string();
    let impact = success_json(
        temp.path(),
        &[
            "removal-impact",
            "--profile-id",
            &first_id,
            "--expected-revision",
            &first_revision_text,
        ],
    );
    assert_eq!(impact["blockingReferenceCount"], 0);

    let removed = success_json(
        temp.path(),
        &[
            "remove",
            "--profile-id",
            &first_id,
            "--expected-revision",
            &first_revision_text,
            "--confirm",
        ],
    );
    assert_eq!(removed["removed"], true);

    let listed = success_json(temp.path(), &["list"]);
    assert_eq!(listed["items"].as_array().unwrap().len(), 1);
    assert_eq!(listed["items"][0]["id"], second_id);
}
