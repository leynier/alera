use chrono::Utc;
use tempfile::TempDir;

use super::*;
use crate::runtime::{
    AutomationActorKind, AutomationSchedule, AutomationSetupPolicy, AutomationTarget,
};

async fn seed_profile(store: &RuntimeStore) {
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('profile-1', 'Profile 1', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(store.pool())
    .await
    .unwrap();
}

fn definition() -> AutomationDefinition {
    let now = Utc::now();
    AutomationDefinition {
        id: "automation-1".into(),
        slug: "review".into(),
        name: "Review".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Review {{workspace.name}}".into(),
        schedule: AutomationSchedule::Recurring {
            cron: "0 * * * *".into(),
            timezone: "UTC".into(),
            start_at: None,
            end_at: None,
            max_scheduled_runs: None,
        },
        target: AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: "profile-1".into(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: super::super::AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 7200,
        heartbeat_interval_seconds: 60,
        misfire_grace_seconds: 900,
        misfire_policy: super::super::AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        circuit_opened_at: None,
        state: AutomationState::Draft,
        revision: 0,
        approved_revision: None,
        created_by: AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: None,
            label: None,
        },
        modified_by: AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: None,
            label: None,
        },
        created_at: now,
        updated_at: now,
    }
}

#[tokio::test]
async fn list_automations_sorts_names_stored_in_definition_json() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let mut later = definition();
    later.id = "automation-zebra".into();
    later.slug = "zebra".into();
    later.name = "zebra".into();
    store.upsert_automation(later, actor.clone()).await.unwrap();
    let mut earlier = definition();
    earlier.id = "automation-alpha".into();
    earlier.slug = "alpha".into();
    earlier.name = "Alpha".into();
    store.upsert_automation(earlier, actor).await.unwrap();

    let listed = store.list_automations(false).await.unwrap();

    assert_eq!(
        listed
            .into_iter()
            .map(|automation| automation.name)
            .collect::<Vec<_>>(),
        vec!["Alpha", "zebra"]
    );
}

#[tokio::test]
async fn revisioned_upsert_invalidates_material_approval() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    let approved = store
        .approve_automation(&saved.id, saved.revision, actor.clone())
        .await
        .unwrap();
    assert_eq!(approved.state, AutomationState::Active);
    let mut changed = approved.clone();
    changed.prompt_template = "Run {{workspace.path}}".into();
    let edited = store.upsert_automation(changed, actor).await.unwrap();
    assert_eq!(edited.revision, 2);
    assert_eq!(edited.approved_revision, None);
    assert_eq!(edited.state, AutomationState::Draft);
}

#[tokio::test]
async fn name_description_and_tags_preserve_exact_revision_approval() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    let approved = store
        .approve_automation(&saved.id, saved.revision, actor.clone())
        .await
        .unwrap();
    let mut cosmetic = approved.clone();
    cosmetic.name = "Renamed Review".into();
    cosmetic.description = "A clearer description".into();
    cosmetic.tag_ids = vec!["attention".into()];
    let edited = store.upsert_automation(cosmetic, actor).await.unwrap();
    assert_eq!(edited.revision, approved.revision + 1);
    assert_eq!(edited.approved_revision, Some(edited.revision));
    assert_eq!(edited.state, AutomationState::Active);
}

#[tokio::test]
async fn expired_circuit_open_duration_resets_blocked_automations() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    let approved = store
        .approve_automation(&saved.id, saved.revision, actor.clone())
        .await
        .unwrap();
    store
        .set_automation_circuit_opened(&approved.id, true, actor.clone(), Some("opened for test"))
        .await
        .unwrap();
    store
        .set_automation_state(
            &approved.id,
            AutomationState::Blocked,
            actor.clone(),
            Some("opened for test"),
        )
        .await
        .unwrap();
    let mut opened = store.find_automation(&approved.id).await.unwrap().unwrap();
    opened.circuit_opened_at = Some(Utc::now() - chrono::Duration::seconds(901));
    opened.updated_at = opened.circuit_opened_at.unwrap();
    sqlx::query("UPDATE automations SET dataJson = ?, updatedAt = ? WHERE id = ?")
        .bind(serde_json::to_string(&opened).unwrap())
        .bind(crate::runtime::format_timestamp(opened.updated_at))
        .bind(&opened.id)
        .execute(store.pool())
        .await
        .unwrap();

    let (reset, errors) = store
        .reset_expired_automation_circuits(Utc::now(), actor)
        .await
        .unwrap();
    let restored = store.find_automation(&approved.id).await.unwrap().unwrap();

    assert_eq!(reset, 1);
    assert!(errors.is_empty());
    assert!(!restored.circuit_opened);
    assert_eq!(restored.circuit_opened_at, None);
    assert_eq!(restored.state, AutomationState::Active);
}

#[tokio::test]
async fn circuit_open_duration_does_not_reset_before_it_elapses() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    store
        .set_automation_circuit_opened(&saved.id, true, actor.clone(), Some("opened for test"))
        .await
        .unwrap();

    let (reset, errors) = store
        .reset_expired_automation_circuits(Utc::now(), actor)
        .await
        .unwrap();
    let opened = store.find_automation(&saved.id).await.unwrap().unwrap();

    assert_eq!(reset, 0);
    assert!(errors.is_empty());
    assert!(opened.circuit_opened);
    assert!(opened.circuit_opened_at.is_some());
    assert!(store.has_pending_automation_work().await.unwrap());
}

#[tokio::test]
async fn expired_circuit_reset_preserves_paused_and_unapproved_state() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    store
        .set_automation_circuit_opened(&saved.id, true, actor.clone(), Some("opened for test"))
        .await
        .unwrap();
    store
        .set_automation_state(
            &saved.id,
            AutomationState::Paused,
            actor.clone(),
            Some("paused while open"),
        )
        .await
        .unwrap();
    let mut opened = store.find_automation(&saved.id).await.unwrap().unwrap();
    opened.circuit_opened_at = Some(Utc::now() - chrono::Duration::seconds(901));
    opened.updated_at = opened.circuit_opened_at.unwrap();
    sqlx::query("UPDATE automations SET dataJson = ?, updatedAt = ? WHERE id = ?")
        .bind(serde_json::to_string(&opened).unwrap())
        .bind(crate::runtime::format_timestamp(opened.updated_at))
        .bind(&opened.id)
        .execute(store.pool())
        .await
        .unwrap();

    let (reset, errors) = store
        .reset_expired_automation_circuits(Utc::now(), actor.clone())
        .await
        .unwrap();
    let restored = store.find_automation(&saved.id).await.unwrap().unwrap();
    assert_eq!(reset, 1);
    assert!(errors.is_empty());
    assert!(!restored.circuit_opened);
    assert_eq!(restored.state, AutomationState::Paused);

    let (again, again_errors) = store
        .reset_expired_automation_circuits(Utc::now(), actor)
        .await
        .unwrap();
    assert_eq!(again, 0);
    assert!(again_errors.is_empty());
}

#[tokio::test]
async fn open_automation_circuit_blocks_active_and_preserves_paused() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    store
        .approve_automation(&saved.id, saved.revision, actor.clone())
        .await
        .unwrap();

    let blocked = store
        .open_automation_circuit(&saved.id, actor.clone(), Some("opened while active"))
        .await
        .unwrap();
    assert!(blocked.circuit_opened);
    assert_eq!(blocked.state, AutomationState::Blocked);

    store
        .set_automation_circuit_opened(&saved.id, false, actor.clone(), Some("reset"))
        .await
        .unwrap();
    store
        .set_automation_state(
            &saved.id,
            AutomationState::Paused,
            actor.clone(),
            Some("paused after reset"),
        )
        .await
        .unwrap();
    let paused = store
        .open_automation_circuit(&saved.id, actor, Some("opened while paused"))
        .await
        .unwrap();
    assert!(paused.circuit_opened);
    assert_eq!(paused.state, AutomationState::Paused);
}

#[tokio::test]
async fn reset_automation_circuit_restores_approved_blocked_state() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    seed_profile(&store).await;
    let actor = definition().created_by.clone();
    let saved = store
        .upsert_automation(definition(), actor.clone())
        .await
        .unwrap();
    store
        .approve_automation(&saved.id, saved.revision, actor.clone())
        .await
        .unwrap();
    store
        .open_automation_circuit(&saved.id, actor.clone(), Some("opened"))
        .await
        .unwrap();

    let restored = store
        .reset_automation_circuit(&saved.id, actor, Some("scheduled success"))
        .await
        .unwrap();
    assert!(!restored.circuit_opened);
    assert_eq!(restored.circuit_opened_at, None);
    assert_eq!(restored.state, AutomationState::Active);
}
