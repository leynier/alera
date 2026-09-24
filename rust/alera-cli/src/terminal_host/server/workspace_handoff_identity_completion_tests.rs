use super::*;

#[tokio::test]
async fn hand_on_relocates_stopped_session_paths_without_touching_neighbor_sessions() {
    let mut fixture = Fixture::new().await;
    let mut stopped = Session::driver_test_stub("stopped", 80, 24);
    stopped.workspace_id = fixture.child.id.clone();
    stopped.working_directory = format!("{}/nested", fixture.child.path);
    stopped.handle_exit(0);
    fixture.actor.sessions.insert("stopped".into(), stopped);
    let neighbor_rx = fixture.insert_main_shell_in_child();
    let neighbor_path = fixture.main_path.clone();
    fixture
        .actor
        .sessions
        .get_mut("main-shell")
        .unwrap()
        .working_directory = neighbor_path.clone();
    let response = fixture.request_hand_on().await;
    assert_eq!(response["ok"], true, "{response}");
    let stopped = fixture.actor.sessions.get("stopped").unwrap();
    assert_eq!(
        stopped.working_directory,
        format!("{}/nested", fixture.main_path)
    );
    assert!(!stopped.running());
    let persisted = fixture
        .actor
        .store
        .read("stopped", 1024)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        persisted.working_directory,
        format!("{}/nested", fixture.main_path)
    );
    assert_eq!(persisted.workspace_id, fixture.child.id);
    assert_eq!(
        fixture
            .actor
            .sessions
            .get("main-shell")
            .unwrap()
            .working_directory,
        neighbor_path
    );
    assert_no_write(&neighbor_rx);
}

#[tokio::test]
async fn runtime_hand_on_preserves_task_identity_and_the_existing_project_task() {
    let mut fixture = Fixture::new().await;
    let old_id = fixture.child.id.clone();
    let old_instance = fixture.child.instance_id.clone();
    let response = fixture.request_hand_on().await;
    assert_eq!(response["ok"], true, "{response}");
    let moved = fixture
        .actor
        .runtime_store
        .find_workspace(&old_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(moved.instance_id, old_instance);
    assert_eq!(moved.path, fixture.main_path);
    assert_eq!(moved.kind, WorkspaceKind::Main);
    assert!(fixture
        .actor
        .runtime_store
        .find_workspace("main")
        .await
        .unwrap()
        .is_some());
    assert!(!Path::new(&fixture.child.path).exists());
    assert!(fixture.actor.checkout_buffer_guards.is_empty());
}

#[tokio::test]
async fn runtime_hand_off_keeps_identity_and_the_project_branch() {
    let mut fixture = Fixture::new().await;
    let before = fixture
        .actor
        .runtime_store
        .find_workspace("main")
        .await
        .unwrap()
        .unwrap();
    std::fs::write(
        Path::new(&fixture.main_path).join("shared.txt"),
        "keep shared",
    )
    .unwrap();
    let destination = fixture._root.path().join("workspaces/independent");
    let response = fixture
        .request_relocation(
            "handOff",
            json!({
                "id": "main", "branch": "independent", "path": destination.to_string_lossy(),
                "moveChanges": false, "sharedImpactConfirmed": true, "deferSetup": true,
            }),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    let after = fixture
        .actor
        .runtime_store
        .find_workspace("main")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(after.instance_id, before.instance_id);
    assert_eq!(after.name, before.name);
    assert_eq!(after.kind, WorkspaceKind::Linked);
    assert_eq!(after.path, destination.to_string_lossy());
    assert_eq!(
        alera_core::git::current_branch(&fixture.main_path).unwrap(),
        "main"
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&fixture.main_path).join("shared.txt")).unwrap(),
        "keep shared"
    );
    assert!(!destination.join("shared.txt").exists());
    assert!(fixture.actor.checkout_buffer_guards.is_empty());
}
