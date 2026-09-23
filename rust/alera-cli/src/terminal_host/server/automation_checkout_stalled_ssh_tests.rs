use super::*;
use std::time::Duration;

#[tokio::test]
async fn stalled_ssh_preparation_allows_status_and_cancellation_without_allocating() {
    stalled_ssh_dispatch(false).await;
}

#[tokio::test]
async fn stalled_ssh_precheck_allows_status_and_cancellation_without_allocating() {
    stalled_ssh_dispatch(true).await;
}

async fn stalled_ssh_dispatch(precheck: bool) {
    let (mut fixture, mut definition) = empty_project().await;
    fixture.actor.clients.get_mut(&1).unwrap().local_role =
        crate::terminal_host::server::client_delivery::LocalClientRole::App;
    declare(&fixture.repo_path);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let store = fixture.actor.runtime_store.clone();
    store
        .upsert_ssh_target(
            serde_json::from_value(json!({
                "id":"stalled-fixture", "alias":"Stalled Fixture", "host":"127.0.0.1",
                "port":port, "username":"fixture", "authKind":"agent",
                "createdAt":Utc::now(), "updatedAt":Utc::now(),
                "installDir":"/fixture/sidecar", "bootstrapStatus":"installed",
                "runtimePlatform":"linux"
            }))
            .unwrap(),
        )
        .await
        .unwrap();
    store
        .register_project_checkout("project-1", "stalled-fixture", "/fixture/project")
        .await
        .unwrap();
    if let AutomationTarget::ProjectCheckout { host_id, .. } = &mut definition.target {
        *host_id = "stalled-fixture".into();
    }
    if precheck {
        definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
            command: "exit 0".into(),
            timeout_seconds: 30,
        });
    }
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let mut run = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "stalled-ssh".into(),
                scheduled_at: Utc::now(),
                local_time: "fixture".into(),
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    run.target_identity = Some(serde_json::from_value(json!({"profileId":"profile-1"})).unwrap());
    let run = store.save_automation_run(&run).await.unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = inbox;
    tokio::time::timeout(
        Duration::from_secs(1),
        fixture
            .actor
            .start_automation_run(&definition, run.clone(), precheck),
    )
    .await
    .expect("Initial policy checks must not wait for SSH on the actor");
    if precheck {
        assert!(fixture.actor.automation_precheck_jobs.contains(&run.id));
        fixture
            .actor
            .start_automation_run(&definition, run.clone(), true)
            .await;
        assert_eq!(fixture.actor.automation_precheck_jobs.len(), 1);
    }
    // Accept the real OpenSSH connection but withhold the SSH banner.
    let (connection, _) = tokio::time::timeout(Duration::from_secs(10), listener.accept())
        .await
        .expect("the preparation worker must attempt SSH")
        .unwrap();
    tokio::time::timeout(
        Duration::from_secs(1),
        fixture.actor.handle_request(1, "status.get", &json!({})),
    )
    .await
    .expect("SSH must not block the actor")
    .unwrap();
    let cancelled = tokio::time::timeout(
        Duration::from_secs(1),
        fixture.actor.handle_request(
            1,
            "automation.cancel",
            &json!({"run": run.id, "targetIdentity": run.target_identity}),
        ),
    )
    .await
    .expect("SSH must not block cancellation requests")
    .unwrap();
    assert!(cancelled["cancelRequestedAt"].is_string());
    assert_eq!(fixture.actor.managed_workspace_jobs, 0);
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
    drop(listener);
    drop(connection);
    let command = tokio::time::timeout(Duration::from_secs(20), commands.recv())
        .await
        .unwrap()
        .unwrap();
    fixture.actor.handle(command).await;
    let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
    assert_eq!(current.status, AutomationRunStatus::Cancelled);
    assert_eq!(current.attempt_count, if precheck { 0 } else { 1 });
    assert!(current.workspace_id.is_none());
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
    assert!(fixture.actor.automation_checkout_jobs.is_empty());
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
}
