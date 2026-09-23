use super::*;
use alera_core::runtime::Workspace;

async fn store_with_workspace(path: &str) -> (tempfile::TempDir, RuntimeStore) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = chrono::Utc::now();
    let project: alera_core::runtime::Project = serde_json::from_value(json!({
        "id": "project-1", "name": "Project", "repoPath": path, "kind": "folder",
        "createdAt": now, "updatedAt": now,
    }))
    .unwrap();
    store.upsert_project(project).await.unwrap();
    let workspace = Workspace {
        id: "ws-1".into(),
        instance_id: "instance".into(),
        host_id: alera_core::runtime::LOCAL_HOST_ID.into(),
        project_id: "project-1".into(),
        name: "main".into(),
        branch: None,
        path: path.to_string(),
        created_at: now,
        updated_at: now,
        kind: alera_core::runtime::WorkspaceKind::Main,
        status: alera_core::runtime::WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    };
    store.upsert_workspace(workspace).await.unwrap();
    (directory, store)
}

#[cfg(unix)]
#[tokio::test]
async fn runs_the_tool_in_the_workspace_with_stdin_and_environment() {
    let checkout = tempfile::tempdir().unwrap();
    std::fs::create_dir(checkout.path().join("sub")).unwrap();
    let (_dir, store) = store_with_workspace(checkout.path().to_str().unwrap()).await;

    let result = handle_host_process_run(
        &store,
        &json!({
            "workspaceId": "ws-1",
            "executable": "sh",
            "arguments": ["-c", "pwd; cat; printf '%s' \"$ALERA_PROBE\"; echo err >&2; exit 3"],
            "cwd": checkout.path().join("sub").to_str().unwrap(),
            "environment": { "ALERA_PROBE": "probe-value" },
            "stdin": "from stdin\n",
        }),
    )
    .await
    .unwrap();

    assert_eq!(result["exitCode"], 3);
    let stdout = result["stdout"].as_str().unwrap();
    let expected_cwd = std::fs::canonicalize(checkout.path().join("sub")).unwrap();
    let reported_cwd = std::fs::canonicalize(stdout.lines().next().unwrap()).unwrap();
    assert_eq!(reported_cwd, expected_cwd);
    assert!(stdout.contains("from stdin\n"), "{stdout}");
    assert!(stdout.ends_with("probe-value"), "{stdout}");
    assert_eq!(result["stderr"], "err\n");
}

#[tokio::test]
async fn refuses_a_working_directory_outside_the_workspace() {
    let checkout = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let (_dir, store) = store_with_workspace(checkout.path().to_str().unwrap()).await;

    let error = handle_host_process_run(
        &store,
        &json!({
            "workspaceId": "ws-1",
            "executable": "sh",
            "arguments": ["-c", "true"],
            "cwd": outside.path().to_str().unwrap(),
        }),
    )
    .await
    .unwrap_err();

    assert!(error.to_string().contains("outside workspace"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn a_tool_that_outlives_its_budget_is_reported_as_timed_out() {
    let checkout = tempfile::tempdir().unwrap();
    let (_dir, store) = store_with_workspace(checkout.path().to_str().unwrap()).await;

    let error = handle_host_process_run(
        &store,
        &json!({
            "workspaceId": "ws-1",
            "executable": "sleep",
            "arguments": ["30"],
            "timeoutMs": 200,
        }),
    )
    .await
    .unwrap_err();

    assert!(error.to_string().contains("timed out"), "{error}");
}

#[tokio::test]
async fn arguments_must_be_strings() {
    let checkout = tempfile::tempdir().unwrap();
    let (_dir, store) = store_with_workspace(checkout.path().to_str().unwrap()).await;

    let error = handle_host_process_run(
        &store,
        &json!({ "workspaceId": "ws-1", "executable": "sh", "arguments": [1] }),
    )
    .await
    .unwrap_err();

    assert!(error.to_string().contains("list of strings"), "{error}");
}
