use super::host_link_mirror_case::hub_and_satellite_with_kind;
use super::*;

/// The hub forwards the desktop `git.*` surface to the satellite that owns
/// the checkout, and the satellite answers with the core source-control
/// types and the typed `gitError` conflict the Dart backend rebuilds.
#[test]
fn hub_forwards_git_verbs_for_a_remote_workspace_to_its_satellite() {
    let fixture = hub_and_satellite_with_kind("gitRepository");
    let remote = &fixture.remote;
    let (mut writer, mut reader) = connect(fixture.hub_port, "hub-token");
    let mut next_id = 0;
    let mut request = |request_type: &str, payload: Value| {
        next_id += 1;
        send(
            &mut writer,
            json!({"id": next_id, "type": request_type, "payload": payload}),
        );
        read_response(&mut reader, next_id)
    };

    let is_repository = request("git.isRepository", json!({"workspaceId": "task"}));
    assert_eq!(is_repository["ok"], true, "{is_repository}");
    assert_eq!(is_repository["payload"], true);

    let status = request("git.status", json!({"workspaceId": "task"}));
    assert_eq!(status["ok"], true, "{status}");
    let mut untracked: Vec<&str> = status["payload"]["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["path"].as_str().unwrap())
        .collect();
    untracked.sort_unstable();
    assert_eq!(untracked, ["readme.md", "src/main.rs"], "{status}");
    assert_eq!(status["payload"]["entries"][0]["area"], "untracked");

    let staged = request(
        "git.stage",
        json!({"workspaceId": "task", "filePath": "readme.md"}),
    );
    assert_eq!(staged["ok"], true, "{staged}");
    let committed = request(
        "git.commit",
        json!({"workspaceId": "task", "message": "docs: add readme"}),
    );
    assert_eq!(committed["ok"], true, "{committed}");
    assert_eq!(committed["payload"]["oid"].as_str().unwrap().len(), 40);

    let state = request("git.repositoryState", json!({"workspaceId": "task"}));
    assert_eq!(state["ok"], true, "{state}");
    assert_eq!(state["payload"]["headMessage"], "docs: add readme");

    let history = request("git.history", json!({"workspaceId": "task", "limit": 20}));
    assert_eq!(history["ok"], true, "{history}");
    assert_eq!(
        history["payload"]["items"][0]["subject"],
        "docs: add readme"
    );

    let explorer = request("git.explorerStatus", json!({"workspaceId": "task"}));
    assert_eq!(explorer["ok"], true, "{explorer}");
    let decorated: Vec<&str> = explorer["payload"]["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["path"].as_str().unwrap())
        .collect();
    assert_eq!(decorated, ["src", "src/main.rs"], "{explorer}");

    // A Source Control root inside the workspace is accepted; a sibling is not.
    let scoped = request(
        "git.status",
        json!({"workspaceId": "task", "path": remote.join("src").to_str().unwrap()}),
    );
    assert_eq!(scoped["ok"], true, "{scoped}");
    let outside = request(
        "git.status",
        json!({"workspaceId": "task", "path": remote.parent().unwrap().to_str().unwrap()}),
    );
    assert_eq!(outside["ok"], false, "{outside}");
    assert!(
        outside["error"]
            .as_str()
            .unwrap()
            .contains("outside workspace"),
        "{outside}"
    );

    let missing = request(
        "git.checkoutBranch",
        json!({"workspaceId": "task", "branch": "does-not-exist"}),
    );
    assert_eq!(missing["ok"], false, "{missing}");
    assert_eq!(missing["errorCode"], "gitError", "{missing}");
    assert_eq!(
        missing["errorDetails"]["kind"], "branchNotFound",
        "{missing}"
    );
}
