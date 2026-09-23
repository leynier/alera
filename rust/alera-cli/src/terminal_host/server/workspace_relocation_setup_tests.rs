use super::*;
use alera_core::runtime::{ProjectConfig, WorktreeCopyRule, WorktreeSetupConfig};

#[tokio::test]
async fn setup_recovery_uses_runtime_evidence_and_never_repeats_commands() {
    for uncertain_spawn in [false, true] {
        let mut fixture = Fixture::new().await;
        fixture
            .actor
            .runtime_store
            .upsert_project_config(
                "project",
                ProjectConfig {
                    worktree: WorktreeSetupConfig {
                        copy: vec![],
                        setup: vec!["echo forbidden > repeated.txt".into()],
                    },
                    ..ProjectConfig::default()
                },
                Utc::now(),
            )
            .await
            .unwrap();
        let destination = fixture._root.path().join("workspaces/recovery");
        let response = fixture
            .request_relocation(
                "handOff",
                json!({
                    "id": "main", "branch": "recovery", "path": destination.to_string_lossy(),
                    "moveChanges": false, "sharedImpactConfirmed": true, "deferSetup": true,
                }),
            )
            .await;
        assert_eq!(response["ok"], true, "{response}");
        let receipt = fixture
            .actor
            .runtime_store
            .list_workspace_relocation_recovery("main", 1)
            .await
            .unwrap()
            .remove(0)
            .setup
            .unwrap();
        let receipt = fixture
            .actor
            .runtime_store
            .claim_relocation_setup(&receipt)
            .await
            .unwrap();
        if uncertain_spawn {
            let boot = crate::relocation_setup_process::current_boot_id().unwrap();
            fixture
                .actor
                .runtime_store
                .begin_setup_root_process(&receipt, 0, std::env::consts::OS, boot.as_deref())
                .await
                .unwrap();
        }
        for (request_id, workspace_id) in [(80, "other-task"), (81, "main")] {
            fixture.actor.handle_line(1, json!({"id": request_id, "type": "workspace.recoverRelocationSetup", "payload": {
                "id": workspace_id, "relocationId": receipt.relocation_id,
                "attemptId": receipt.attempt_id, "bootId": "forged-new-boot",
            }}).to_string()).await;
            let response = wait_setup_response(&mut fixture, request_id).await;
            assert_eq!(
                response["ok"],
                !uncertain_spawn && workspace_id == "main",
                "{response}"
            );
            if response["ok"] == true {
                assert_eq!(response["payload"]["steps"][0]["succeeded"], false);
            }
        }
        assert!(!destination.join("repeated.txt").exists());
        let stored = fixture
            .actor
            .runtime_store
            .find_relocation_setup(&receipt.relocation_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(stored.report.is_some(), !uncertain_spawn);
    }
}

#[cfg(unix)]
#[tokio::test]
async fn setup_cancellation_closes_recorded_descendants_and_prevents_the_next_command() {
    let mut fixture = Fixture::new().await;
    let config = ProjectConfig {
        worktree: WorktreeSetupConfig {
            copy: vec![],
            setup: vec![
                "echo started > started.txt; sleep 3 & echo $! > child-pid.txt; wait".into(),
                "echo forbidden > second.txt".into(),
            ],
        },
        ..ProjectConfig::default()
    };
    fixture
        .actor
        .runtime_store
        .upsert_project_config("project", config, Utc::now())
        .await
        .unwrap();
    let destination = fixture._root.path().join("workspaces/cancellable-setup");
    let response = fixture.request_relocation("handOff", json!({"id": "main", "branch": "cancellable-setup", "path": destination.to_string_lossy(), "moveChanges": false, "sharedImpactConfirmed": true, "deferSetup": true})).await;
    assert_eq!(response["ok"], true, "{response}");
    let relocation_id: String =
        sqlx::query_scalar("SELECT id FROM workspaceRelocations WHERE workspaceId = 'main'")
            .fetch_one(fixture.actor.runtime_store.pool())
            .await
            .unwrap();
    fixture.actor.handle_line(1, json!({"id": 10, "type": "workspace.runSetup", "payload": {"id": "main", "relocationId": relocation_id}}).to_string()).await;
    tokio::time::timeout(Duration::from_secs(5), async {
        while !destination.join("child-pid.txt").exists() {
            tokio::select! {
                command = fixture.commands.recv() => fixture.actor.handle(command.unwrap()).await,
                _ = tokio::time::sleep(Duration::from_millis(10)) => {}
            }
        }
    })
    .await
    .unwrap();
    let receipt = fixture
        .actor
        .runtime_store
        .find_relocation_setup(&relocation_id)
        .await
        .unwrap()
        .unwrap();
    let attempt = receipt.attempt_id.as_deref().unwrap();
    assert!(fixture
        .actor
        .runtime_store
        .request_relocation_setup_cancellation("other-task", &relocation_id, attempt)
        .await
        .is_err());
    assert!(fixture
        .actor
        .runtime_store
        .request_relocation_setup_cancellation("main", &relocation_id, "stale")
        .await
        .is_err());
    fixture.actor.handle_line(1, json!({"id": 20, "type": "workspace.cancelRelocationSetup", "payload": {"id": "main", "relocationId": relocation_id, "attemptId": attempt}}).to_string()).await;
    let cancelled = wait_setup_response(&mut fixture, 20).await;
    assert_eq!(cancelled["ok"], true, "{cancelled}");
    assert_eq!(cancelled["payload"]["processesClosed"], false);
    assert!(fixture
        .actor
        .runtime_store
        .setup_cancellation_requested(&receipt)
        .await
        .unwrap());
    assert!(fixture
        .actor
        .runtime_store
        .begin_setup_root_process(&receipt, 1, "test", None)
        .await
        .is_err());
    let finished = wait_setup_response(&mut fixture, 10).await;
    assert_eq!(finished["ok"], true, "{finished}");
    assert!(!destination.join("second.txt").exists());
    let descendants = fixture
        .actor
        .runtime_store
        .list_setup_descendants(&receipt)
        .await
        .unwrap();
    assert!(!descendants.is_empty());
    assert!(descendants.iter().all(|process| process.exit_verified));
    let report = fixture
        .actor
        .runtime_store
        .find_relocation_setup(&relocation_id)
        .await
        .unwrap()
        .unwrap()
        .report
        .unwrap();
    assert!(report
        .steps
        .iter()
        .any(|step| !step.succeeded && step.label == "Setup Cancellation"));
    let reopened = alera_core::runtime::RuntimeStore::open(fixture._root.path())
        .await
        .unwrap();
    assert!(reopened
        .setup_cancellation_requested(&receipt)
        .await
        .unwrap());
}

async fn wait_setup_response(fixture: &mut Fixture, id: i64) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            tokio::select! {
                command = fixture.commands.recv() => fixture.actor.handle(command.unwrap()).await,
                frame = fixture.responses.recv() => {
                    let value = frame.unwrap().as_json().unwrap();
                    if value["id"] == id { return value; }
                }
            }
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn deferred_relocation_setup_pins_commands_and_replays_the_receipt_without_running_twice() {
    let mut fixture = Fixture::new().await;
    let config = ProjectConfig {
        worktree: WorktreeSetupConfig {
            copy: vec![],
            setup: vec!["echo setup>>setup-count.txt".into()],
        },
        ..ProjectConfig::default()
    };
    fixture
        .actor
        .runtime_store
        .upsert_project_config("project", config, Utc::now())
        .await
        .unwrap();
    let destination = fixture._root.path().join("workspaces/setup-once");
    let response = fixture
        .request_relocation(
            "handOff",
            json!({
                "id": "main", "branch": "setup-once", "path": destination.to_string_lossy(),
                "moveChanges": false, "sharedImpactConfirmed": true, "deferSetup": true,
            }),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert!(
        response["payload"]["deferredSetupCommand"]
            .as_str()
            .is_some(),
        "{response}"
    );
    assert!(!destination.join("setup-count.txt").exists());
    let relocation_id: String =
        sqlx::query_scalar("SELECT id FROM workspaceRelocations WHERE workspaceId = 'main'")
            .fetch_one(fixture.actor.runtime_store.pool())
            .await
            .unwrap();
    let directory = fixture.actor.setup_script_directory().unwrap();
    let script = crate::worktree_setup_script::setup_script_path(&directory, "main", cfg!(windows));
    crate::worktree_setup_script::remove_stale_setup_scripts(&directory);
    assert!(!script.exists());
    let workspace = fixture
        .actor
        .runtime_store
        .find_workspace("main")
        .await
        .unwrap()
        .unwrap();
    let (_, command) = crate::workspace_relocation_setup::prepare_launcher(
        &fixture.actor.runtime_store,
        &workspace,
        &relocation_id,
        &directory,
    )
    .await
    .unwrap();
    assert!(command.is_some());
    assert!(std::fs::read_to_string(&script)
        .unwrap()
        .contains(&format!("--relocation-id {relocation_id}")));
    assert!(!destination.join("setup-count.txt").exists());
    assert!(fixture
        .actor
        .runtime_store
        .find_relocation_setup(&relocation_id)
        .await
        .unwrap()
        .unwrap()
        .attempt_id
        .is_none());
    fixture
        .actor
        .runtime_store
        .upsert_project_config("project", ProjectConfig::default(), Utc::now())
        .await
        .unwrap();
    let report = crate::workspace_relocation_setup::run(
        &fixture.actor.runtime_store,
        "main",
        &relocation_id,
    )
    .await
    .unwrap();
    assert!(report.steps.iter().all(|step| step.succeeded), "{report:?}");
    assert_eq!(report.steps.len(), 1);
    let receipt = fixture
        .actor
        .runtime_store
        .find_relocation_setup(&relocation_id)
        .await
        .unwrap()
        .unwrap();
    let processes = fixture
        .actor
        .runtime_store
        .list_setup_root_processes(&receipt)
        .await
        .unwrap();
    assert_eq!(processes.len(), 1);
    assert_eq!(
        processes[0].phase,
        alera_core::runtime::SetupRootProcessPhase::RootExited
    );
    assert!(processes[0].pid.is_some_and(|pid| pid > 0));
    #[cfg(target_os = "linux")]
    assert_eq!(
        processes[0].boot_id,
        crate::relocation_setup_process::current_boot_id().unwrap()
    );
    let reopened = alera_core::runtime::RuntimeStore::open(fixture._root.path())
        .await
        .unwrap();
    let repeated = crate::workspace_relocation_setup::run(&reopened, "main", &relocation_id)
        .await
        .unwrap();
    assert_eq!(repeated, report);
    let (cached, command) = crate::workspace_relocation_setup::prepare_launcher(
        &reopened,
        &workspace,
        &relocation_id,
        &directory,
    )
    .await
    .unwrap();
    assert_eq!(cached, report);
    assert!(command.is_none());
    assert_eq!(
        std::fs::read_to_string(destination.join("setup-count.txt"))
            .unwrap()
            .lines()
            .count(),
        1
    );
}

#[tokio::test]
async fn relocation_setup_preserves_transferred_files_inline_and_on_deferred_retry() {
    let mut fixture = Fixture::new().await;
    fixture
        .actor
        .runtime_store
        .upsert_project_config(
            "project",
            ProjectConfig {
                worktree: WorktreeSetupConfig {
                    copy: vec![WorktreeCopyRule {
                        from: "README.md".into(),
                        to: None,
                        overwrite: true,
                    }],
                    setup: vec![],
                },
                ..ProjectConfig::default()
            },
            Utc::now(),
        )
        .await
        .unwrap();
    std::fs::write(
        Path::new(&fixture.main_path).join("README.md"),
        "transferred edit",
    )
    .unwrap();
    let destination = fixture._root.path().join("workspaces/protected-setup");
    let response = fixture
        .request_relocation(
            "handOff",
            json!({
                "id": "main", "branch": "protected-setup", "path": destination.to_string_lossy(),
                "moveChanges": true, "sharedImpactConfirmed": true, "deferSetup": false,
            }),
        )
        .await;
    assert_eq!(response["ok"], true, "{response}");
    assert_eq!(
        response["payload"]["setupReport"]["steps"][0]["succeeded"], false,
        "{response}"
    );
    assert_eq!(
        std::fs::read_to_string(destination.join("README.md")).unwrap(),
        "transferred edit"
    );
    assert_eq!(
        std::fs::read_to_string(Path::new(&fixture.main_path).join("README.md")).unwrap(),
        "hello\n"
    );
    let report =
        crate::worktree_setup::run_workspace_setup(&fixture.actor.runtime_store, "main", true)
            .await
            .unwrap();
    assert_eq!(report.steps.len(), 1);
    assert!(!report.steps[0].succeeded);
    assert!(report.steps[0]
        .message
        .as_deref()
        .unwrap()
        .contains("files were preserved"));
    assert_eq!(
        std::fs::read_to_string(destination.join("README.md")).unwrap(),
        "transferred edit"
    );
}
