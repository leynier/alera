use super::*;

#[test]
fn repeated_workspace_start_defaults_to_independent_tasks_on_the_project_folder() {
    let temp = tempfile::tempdir().unwrap();
    let runtime_dir = temp.path().join("runtime");
    std::fs::create_dir(&runtime_dir).unwrap();
    let _guard = RuntimeGuard {
        runtime_dir: runtime_dir.clone(),
    };
    let repo = temp.path().join("repo");
    std::fs::create_dir(&repo).unwrap();
    init_git_repo(&repo);
    std::fs::write(repo.join("README.md"), "retained uncommitted content\n").unwrap();
    let marker = temp.path().join("launches.txt");
    let recorder = write_recorder(temp.path(), &marker);
    let project = success_json(
        &runtime_dir,
        &[
            "project",
            "add",
            "--name",
            "Shared Project",
            "--repo-path",
            repo.to_str().unwrap(),
            "--kind",
            "git-repository",
        ],
    );
    let project_id = project["project"]["id"].as_str().unwrap();
    success_json(
        &runtime_dir,
        &[
            "agent-profile",
            "create",
            "--name",
            "Recorder",
            "--agent-type",
            "codex",
            "--launch-mode",
            "command",
            "--command",
            recorder.to_str().unwrap(),
        ],
    );
    let start = |name| {
        success_json(
            &runtime_dir,
            &[
                "workspace",
                "start",
                "--profile",
                "Recorder",
                "--prompt",
                "Inspect current files",
                "--project-id",
                project_id,
                "--name",
                name,
            ],
        )
    };
    let first = start("First task");
    let second = start("Second task");
    for task in [&first, &second] {
        assert_eq!(task["path"], repo.canonicalize().unwrap().to_str().unwrap());
        assert_eq!(task["branch"], "main");
        assert_eq!(task["workspace"]["kind"], "main");
        assert!(task["workspace"]["parentWorkspaceId"].is_null());
        assert_eq!(task["profileName"], "Recorder");
        assert!(!task["tabId"].as_str().unwrap().is_empty());
    }
    assert_ne!(first["workspaceId"], second["workspaceId"]);
    assert_ne!(
        first["workspace"]["instanceId"],
        second["workspace"]["instanceId"]
    );
    assert_ne!(first["tabId"], second["tabId"]);
    assert_eq!(
        std::fs::read_to_string(repo.join("README.md")).unwrap(),
        "retained uncommitted content\n"
    );
    let branch = windowless_command("git")
        .args(["branch", "--show-current"])
        .current_dir(&repo)
        .output()
        .unwrap();
    assert!(branch.status.success());
    assert_eq!(String::from_utf8(branch.stdout).unwrap().trim(), "main");
}
