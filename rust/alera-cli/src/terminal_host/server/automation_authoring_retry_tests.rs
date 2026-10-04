use super::*;

#[tokio::test]
async fn create_key_rejects_changed_payload_and_replays_original_after_edit() {
    let mut fixture = harness().await;
    let input = json!({"name":"Review","promptTemplate":"Review changes","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"workspace-1","agentProfileId":"profile-1"}}});
    let payload = json!({"automation":input,"requestKey":"ambiguous-save"});
    let created = fixture
        .actor
        .handle_automation_request(1, "automation.create", &payload)
        .await
        .unwrap();
    let mut changed = payload.clone();
    changed["automation"]["promptTemplate"] = json!("Changed task");
    let error = fixture
        .actor
        .handle_automation_request(1, "automation.create", &changed)
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("different automation"));
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .list_automations(false)
            .await
            .unwrap()
            .len(),
        1
    );
    let patched = fixture.actor.handle_automation_request(1, "automation.patch", &json!({"id":created["id"],"changes":{"promptTemplate":"Edited later","creationRequestFingerprint":"forged"}})).await.unwrap();
    let repeated = fixture
        .actor
        .handle_automation_request(1, "automation.create", &payload)
        .await
        .unwrap();
    assert_eq!(repeated["id"], created["id"]);
    assert_eq!(repeated["revision"], patched["revision"]);
    changed["requestKey"] = json!("new-save");
    let next = fixture
        .actor
        .handle_automation_request(1, "automation.create", &changed)
        .await
        .unwrap();
    assert_ne!(next["id"], created["id"]);
    assert_eq!(next["promptTemplate"], "Changed task");
}

async fn failed_first_launch(
    fixture: &mut Harness,
    precheck: bool,
) -> (AutomationDefinition, AutomationRun) {
    let mut definition = draft_definition();
    definition.state = AutomationState::Active;
    if precheck {
        definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
            command: "exit 0".into(),
            timeout_seconds: 5,
        });
    }
    let store = &fixture.actor.runtime_store;
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Paused,
            definition.created_by.clone(),
            None,
        )
        .await
        .unwrap();
    let run = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "failed-before-terminal".into(),
                scheduled_at: Utc::now(),
                local_time: "fixture".into(),
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    let mut run = store.begin_automation_attempt(&run.id, 3).await.unwrap();
    run.absolute_deadline_at = Some(Utc::now() + chrono::Duration::hours(1));
    let run = store.save_automation_run(&run).await.unwrap();
    fixture
        .actor
        .fail_run(&run, "Transient launch error".into())
        .await;
    let mut pending = fixture
        .actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.status, AutomationRunStatus::Pending);
    assert!(pending.recovery.is_none());
    assert_eq!(pending.absolute_deadline_at, run.absolute_deadline_at);
    pending.retry_after = Some(Utc::now() - chrono::Duration::seconds(1));
    fixture
        .actor
        .runtime_store
        .save_automation_run(&pending)
        .await
        .unwrap();
    (definition, pending)
}

#[tokio::test]
async fn first_launch_failure_redispatches_without_missing_terminal_recovery() {
    let mut fixture = harness().await;
    let (definition, pending) = failed_first_launch(&mut fixture, false).await;
    fixture
        .actor
        .handle(crate::terminal_host::server::ServerCommand::AutomationTick)
        .await;
    let retried = fixture
        .actor
        .runtime_store
        .find_automation_run(&pending.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(retried.status, AutomationRunStatus::Dispatched);
    assert_eq!(retried.attempt_count, 2);
    assert!(retried.tab_id.is_some());
    assert_eq!(retried.absolute_deadline_at, pending.absolute_deadline_at);
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation(&definition.id)
            .await
            .unwrap()
            .unwrap()
            .state,
        AutomationState::Paused
    );
}

#[tokio::test]
async fn dispatch_retry_precheck_keeps_original_absolute_deadline() {
    let mut fixture = harness().await;
    let (definition, pending) = failed_first_launch(&mut fixture, true).await;
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    fixture.actor.inbox = inbox;
    fixture
        .actor
        .start_automation_run(&definition, pending.clone(), true)
        .await;
    let reserved = fixture
        .actor
        .runtime_store
        .find_automation_run(&pending.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(reserved.absolute_deadline_at, pending.absolute_deadline_at);
    let command = tokio::time::timeout(std::time::Duration::from_secs(10), commands.recv())
        .await
        .unwrap()
        .unwrap();
    fixture.actor.handle(command).await;
    let retried = fixture
        .actor
        .runtime_store
        .find_automation_run(&pending.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(retried.status, AutomationRunStatus::Dispatched);
    assert_eq!(retried.attempt_count, 2);
    assert_eq!(retried.absolute_deadline_at, pending.absolute_deadline_at);
}
