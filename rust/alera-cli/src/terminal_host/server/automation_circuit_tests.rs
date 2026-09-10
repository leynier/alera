use std::collections::HashMap;

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
    AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy, AutomationState,
    AutomationTarget,
};
use chrono::{Duration, Utc};

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};

const WORKSPACE_ID: &str = "workspace";

fn definition() -> AutomationDefinition {
    let now = Utc::now();
    let actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    };
    AutomationDefinition {
        id: "automation-expire".into(),
        slug: "expire".into(),
        name: "Expire".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Run".into(),
        schedule: AutomationSchedule::OneTime {
            at: now + Duration::hours(1),
            timezone: "UTC".into(),
        },
        target: AutomationTarget::FreshTab {
            workspace_id: WORKSPACE_ID.into(),
            agent_profile_id: "profile".into(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 7200,
        heartbeat_interval_seconds: 60,
        misfire_grace_seconds: 900,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        circuit_opened_at: None,
        state: AutomationState::Active,
        revision: 1,
        approved_revision: Some(1),
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

async fn seeded_actor() -> (tempfile::TempDir, crate::terminal_host::server::ServerActor) {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _events) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('profile', 'Profile', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
    (dir, actor)
}

#[tokio::test]
async fn expired_circuit_tick_broadcasts_automations_changed() {
    use crate::terminal_host::client::ClientFrame;
    use tokio::sync::mpsc::error::TryRecvError;

    let dir = tempfile::tempdir().unwrap();
    let (handle, mut events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('profile', 'Profile', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
    let now = Utc::now();
    let mut definition = definition();
    definition.id = "automation-circuit-reset".into();
    definition.slug = "circuit-reset".into();
    definition.circuit_open_seconds = 1;
    let actor_record = definition.created_by.clone();
    actor
        .runtime_store
        .upsert_automation(definition.clone(), actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .approve_automation(&definition.id, 1, actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .set_automation_circuit_opened(&definition.id, true, actor_record.clone(), Some("opened"))
        .await
        .unwrap();
    actor
        .runtime_store
        .set_automation_state(
            &definition.id,
            AutomationState::Blocked,
            actor_record,
            Some("opened"),
        )
        .await
        .unwrap();
    let mut opened = actor
        .runtime_store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .unwrap();
    opened.circuit_opened_at = Some(now - Duration::seconds(2));
    opened.updated_at = opened.circuit_opened_at.unwrap();
    sqlx::query("UPDATE automations SET dataJson = ?, updatedAt = ? WHERE id = ?")
        .bind(serde_json::to_string(&opened).unwrap())
        .bind(alera_core::runtime::format_timestamp(opened.updated_at))
        .bind(&opened.id)
        .execute(actor.runtime_store.pool())
        .await
        .unwrap();
    while !matches!(events.try_recv(), Err(TryRecvError::Empty)) {}

    actor.handle_automation_tick().await;

    let restored = actor
        .runtime_store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .unwrap();
    assert!(!restored.circuit_opened);
    assert_eq!(restored.state, AutomationState::Active);
    let mut saw_change = false;
    while let Ok(frame) = events.try_recv() {
        if let ClientFrame::Json(value) = frame {
            if value.get("event").and_then(serde_json::Value::as_str) == Some("automationsChanged")
            {
                saw_change = true;
                break;
            }
        }
    }
    assert!(
        saw_change,
        "circuit reset must broadcast automationsChanged"
    );
}

#[tokio::test]
async fn open_automation_circuit_preserves_paused_state() {
    let (_dir, mut actor) = seeded_actor().await;
    let mut definition = definition();
    definition.id = "automation-paused-circuit".into();
    definition.slug = "paused-circuit".into();
    let actor_record = definition.created_by.clone();
    actor
        .runtime_store
        .upsert_automation(definition.clone(), actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .approve_automation(&definition.id, 1, actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .set_automation_state(
            &definition.id,
            AutomationState::Paused,
            actor_record.clone(),
            Some("paused with active runs"),
        )
        .await
        .unwrap();

    actor
        .open_automation_circuit(
            &definition.id,
            actor_record,
            "automation circuit breaker opened",
        )
        .await;

    let opened = actor
        .runtime_store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .unwrap();
    assert!(opened.circuit_opened);
    assert_eq!(opened.state, AutomationState::Paused);
    assert!(actor.automations_active);
}

#[tokio::test]
async fn block_automation_definition_preserves_paused_state() {
    let (_dir, mut actor) = seeded_actor().await;
    let mut definition = definition();
    definition.id = "automation-paused-block".into();
    definition.slug = "paused-block".into();
    let actor_record = definition.created_by.clone();
    actor
        .runtime_store
        .upsert_automation(definition.clone(), actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .approve_automation(&definition.id, 1, actor_record.clone())
        .await
        .unwrap();
    actor
        .runtime_store
        .set_automation_state(
            &definition.id,
            AutomationState::Paused,
            actor_record.clone(),
            Some("paused with active runs"),
        )
        .await
        .unwrap();

    actor
        .block_automation_definition_if_active(
            &definition.id,
            actor_record,
            Some("run completed blocked"),
        )
        .await;

    let paused = actor
        .runtime_store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(paused.state, AutomationState::Paused);
}
