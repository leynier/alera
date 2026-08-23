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
