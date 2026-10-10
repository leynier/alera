use std::sync::{Arc, Mutex};

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use super::*;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
};

type Requests = Arc<Mutex<Vec<Value>>>;

/// A host that answers a fixed sequence of requests and records them. Any
/// request out of order, or any request after the script, fails the test.
async fn scripted_host(
    sequence: Vec<(&'static str, Value)>,
) -> (tempfile::TempDir, RuntimeHostRpcClient, Requests) {
    let directory = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::write(
        directory.path().join("host.json"),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION, "port": port, "token": "fixture-token",
            "runtimeCapabilities": [RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY],
        }))
        .unwrap(),
    )
    .unwrap();
    let requests: Requests = Arc::default();
    let recorded = requests.clone();
    tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        for (expected, payload) in std::iter::once(("hello", json!({}))).chain(sequence) {
            let line = lines.next_line().await.unwrap().unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(request["type"], expected, "{request}");
            recorded.lock().unwrap().push(request.clone());
            let response = json!({"id": request["id"], "ok": true, "payload": payload});
            write
                .write_all(format!("{response}\n").as_bytes())
                .await
                .unwrap();
        }
        assert!(
            lines.next_line().await.unwrap().is_none(),
            "unexpected request after the script"
        );
    });
    let client = RuntimeHostRpcClient::connect(directory.path())
        .await
        .unwrap()
        .unwrap();
    (directory, client, requests)
}

fn workspace(kind: &str, reuses_existing_branch: bool) -> Value {
    json!({
        "id": "task", "instanceId": "instance", "hostId": "local", "projectId": "project",
        "name": "Task", "branch": "feature/task", "path": "/worktrees/task",
        "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-10T00:00:00Z",
        "kind": kind, "status": "active", "sourceBranch": "main",
        "reusesExistingBranch": reuses_existing_branch, "parentWorkspaceId": null,
    })
}

fn args(keep_branch: bool) -> WorkspaceRemoveArgs {
    WorkspaceRemoveArgs {
        id: "task".into(),
        delete_branch: false,
        keep_branch,
        close_sessions: false,
        pause_automations_and_cancel_runs: false,
        editor_buffers: Some(EditorBuffersArg::Save),
    }
}

fn dependency(requires_pause: bool) -> Value {
    json!([{"id": "nightly", "name": "Nightly Review", "activeRuns": 1, "requiresPause": requires_pause}])
}

fn request<'a>(requests: &'a [Value], kind: &str) -> &'a Value {
    requests
        .iter()
        .find(|request| request["type"] == kind)
        .unwrap_or_else(|| panic!("no {kind} request"))
}

#[tokio::test]
async fn the_app_flow_pauses_saves_removes_and_reports_the_branch() {
    let mut child = workspace("linked", false);
    child["id"] = json!("child");
    child["parentWorkspaceId"] = json!("task");
    let (_directory, mut client, requests) = scripted_host(vec![
        ("workspace.find", workspace("linked", false)),
        ("workspace.removalDependencies", dependency(true)),
        (
            "workspace.storageImpact",
            json!({"sizeBytes": 10, "entryCount": 2, "safeToClean": false,
                "blockers": ["Workspace is owned by an active automation"]}),
        ),
        (
            "workspace.listAll",
            json!([workspace("linked", false), child]),
        ),
        (
            "orchestration.terminals",
            json!({"items": [{"running": true}, {"running": false}]}),
        ),
        ("workspace.removalDependencies", dependency(true)),
        ("automation.pause", json!({})),
        ("workspace.removalDependencies", dependency(false)),
        (
            "workspace.bufferGuard.acquire",
            json!({"guardId": "guard", "ready": true, "blockers": [], "disconnectedClients": 0}),
        ),
        ("workspace.removeManaged", workspace("linked", false)),
        ("workspace.bufferGuard.release", json!({})),
        (
            "project.branches.list",
            json!({"branches": ["main"], "localBranches": ["main"]}),
        ),
    ])
    .await;

    let removed = remove_like_app(&mut client, &args(false), EditorBuffersArg::Save)
        .await
        .unwrap();

    assert_eq!(
        removed,
        json!({
            "removed": true,
            "workspaceId": "task",
            "branch": {"name": "feature/task", "deleted": true},
            "pausedAutomations": [{"id": "nightly", "name": "Nightly Review"}],
            "unlinkedChildren": [{"id": "child", "name": "Task"}],
            "closedSessions": 1,
        })
    );
    let requests = requests.lock().unwrap();
    let guard = &request(&requests, "workspace.bufferGuard.acquire")["payload"];
    assert_eq!(guard["resolution"], "save");
    assert_eq!(guard["operation"], "removeManaged");
    let removal = &request(&requests, "workspace.removeManaged")["payload"];
    assert_eq!(removal["deleteBranch"], true);
    assert_eq!(removal["closeSessions"], true);
    assert_eq!(removal["bufferGuardId"], "guard");
    assert_eq!(
        request(&requests, "workspace.storageImpact")["payload"]["closeSessions"],
        true
    );
}

#[tokio::test]
async fn cleanup_blockers_refuse_before_anything_changes() {
    let (_directory, mut client, requests) = scripted_host(vec![
        ("workspace.find", workspace("linked", false)),
        ("workspace.removalDependencies", json!([])),
        (
            "workspace.storageImpact",
            json!({"sizeBytes": 10, "entryCount": 2, "safeToClean": false,
                "blockers": ["Workspace path is outside Alera-managed storage"]}),
        ),
    ])
    .await;

    let error = remove_like_app(&mut client, &args(false), EditorBuffersArg::Discard)
        .await
        .unwrap_err()
        .to_string();

    assert!(error.starts_with("blocked: Cleanup Unavailable"), "{error}");
    assert!(error.contains("outside Alera-managed storage"), "{error}");
    assert_eq!(requests.lock().unwrap().len(), 4);
}

#[tokio::test]
async fn a_kept_or_reused_branch_is_reported_without_deleting() {
    for (keep, reused, reason) in [
        (true, false, "Kept as requested."),
        (false, true, "reused an existing branch"),
    ] {
        let (_directory, mut client, requests) = scripted_host(vec![
            ("workspace.find", workspace("linked", reused)),
            ("workspace.removalDependencies", json!([])),
            (
                "workspace.storageImpact",
                json!({"safeToClean": true, "blockers": []}),
            ),
            ("workspace.listAll", json!([])),
            ("orchestration.terminals", json!({"items": []})),
            ("workspace.removalDependencies", json!([])),
            (
                "workspace.bufferGuard.acquire",
                json!({"guardId": "g", "ready": true, "blockers": [], "disconnectedClients": 0}),
            ),
            ("workspace.removeManaged", workspace("linked", reused)),
            ("workspace.bufferGuard.release", json!({})),
        ])
        .await;

        let removed = remove_like_app(&mut client, &args(keep), EditorBuffersArg::Discard)
            .await
            .unwrap();

        assert_eq!(removed["branch"]["deleted"], false);
        let retained = removed["branch"]["retainedReason"].as_str().unwrap();
        assert!(retained.contains(reason), "{retained}");
        let requests = requests.lock().unwrap();
        assert_eq!(
            request(&requests, "workspace.removeManaged")["payload"]["deleteBranch"],
            false
        );
        assert_eq!(
            request(&requests, "workspace.bufferGuard.acquire")["payload"]["resolution"],
            "discard"
        );
    }
}

#[tokio::test]
async fn unsaved_editors_block_with_a_hint_to_discard() {
    let (_directory, mut client, _requests) = scripted_host(vec![
        ("workspace.find", workspace("main", false)),
        ("workspace.removalDependencies", json!([])),
        ("workspace.listAll", json!([])),
        ("orchestration.terminals", json!({"items": []})),
        ("workspace.removalDependencies", json!([])),
        (
            "workspace.bufferGuard.acquire",
            json!({"guardId": "g", "ready": false, "disconnectedClients": 0, "blockers": [
                {"path": "src/main.rs", "reason": "Could not save the changes: disk full"}]}),
        ),
        ("workspace.bufferGuard.release", json!({})),
    ])
    .await;

    let error = remove_like_app(&mut client, &args(false), EditorBuffersArg::Save)
        .await
        .unwrap_err()
        .to_string();

    assert!(error.starts_with("blocked: "), "{error}");
    assert!(error.contains("editorBuffers discard"), "{error}");
    assert!(error.contains("src/main.rs"), "{error}");
}

#[test]
fn only_a_branch_the_workspace_created_can_be_deleted() {
    let parse = |value: Value| serde_json::from_value::<Workspace>(value).unwrap();
    assert!(can_delete_branch(&parse(workspace("linked", false))));
    assert!(!can_delete_branch(&parse(workspace("linked", true))));
    assert!(!can_delete_branch(&parse(workspace("main", false))));
    let mut empty = workspace("linked", false);
    empty["branch"] = json!("");
    assert!(!can_delete_branch(&parse(empty)));
}
