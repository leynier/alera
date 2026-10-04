use super::super::{
    AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger, AutomationSchedule,
};
use super::*;

fn actor() -> AutomationActor {
    AutomationActor {
        kind: super::super::AutomationActorKind::LocalCli,
        id: None,
        label: None,
    }
}

fn input() -> Value {
    json!({"name":"Daily Review","promptTemplate":"Review {{project.name}}","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"workspace","agentProfileId":"profile"}}})
}

async fn fixture() -> (tempfile::TempDir, RuntimeStore, AutomationDefinition) {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    sqlx::query("INSERT INTO agentProfiles (id,name,agentType,command,createdAt,updatedAt) VALUES ('profile','Profile','codex','codex',datetime('now'),datetime('now'))").execute(store.pool()).await.unwrap();
    let definition = automation_from_input(&input(), actor()).unwrap();
    let definition = store.upsert_automation(definition, actor()).await.unwrap();
    (directory, store, definition)
}

fn occurrence(definition: &AutomationDefinition, key: &str) -> AutomationOccurrence {
    AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: key.into(),
        scheduled_at: Utc::now(),
        local_time: "fixture".into(),
    }
}

#[test]
fn partial_creation_defaults_active_but_never_selects_target() {
    let definition = automation_from_input(&input(), actor()).unwrap();
    assert_eq!(definition.state, AutomationState::Active);
    assert_eq!(definition.retry_max_attempts, 3);
    assert_eq!(
        definition.misfire_policy,
        super::super::AutomationMisfirePolicy::Skip
    );
    let mut missing = input();
    missing.as_object_mut().unwrap().remove("target");
    assert!(automation_from_input(&missing, actor()).is_err());
    let mut draft = input();
    draft["state"] = json!("draft");
    assert_eq!(
        automation_from_input(&draft, actor()).unwrap().state,
        AutomationState::Draft
    );
}

#[tokio::test]
async fn atomic_admission_survives_restart_and_rolls_back_failed_insert() {
    let (directory, store, definition) = fixture().await;
    let occurrence = occurrence(&definition, "scheduled");
    sqlx::query("CREATE TRIGGER failAdmission BEFORE INSERT ON automationRuns BEGIN SELECT RAISE(ABORT,'test failure'); END").execute(store.pool()).await.unwrap();
    assert!(store
        .admit_automation_run(
            &definition,
            &occurrence,
            AutomationRunTrigger::Scheduled,
            true
        )
        .await
        .is_err());
    assert_eq!(
        store
            .count_automation_occurrences(&definition.id)
            .await
            .unwrap(),
        0
    );
    sqlx::query("DROP TRIGGER failAdmission")
        .execute(store.pool())
        .await
        .unwrap();
    let run = store
        .admit_automation_run(
            &definition,
            &occurrence,
            AutomationRunTrigger::Scheduled,
            true,
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(run.number, 1);
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened
        .admit_automation_run(
            &definition,
            &occurrence,
            AutomationRunTrigger::Scheduled,
            true
        )
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        reopened
            .list_automation_runs(Some(&definition.id), 100)
            .await
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn concurrent_admission_has_one_owner_and_unique_run_numbers() {
    let (_directory, store, definition) = fixture().await;
    let occurrence = occurrence(&definition, "scheduled");
    let (a, b) = tokio::join!(
        store.admit_automation_run(
            &definition,
            &occurrence,
            AutomationRunTrigger::Scheduled,
            true
        ),
        store.admit_automation_run(
            &definition,
            &occurrence,
            AutomationRunTrigger::Scheduled,
            true
        )
    );
    assert_eq!(
        usize::from(a.unwrap().is_some()) + usize::from(b.unwrap().is_some()),
        1
    );
    let mut first = occurrence.clone();
    first.key = "manual-first".into();
    let mut second = occurrence;
    second.key = "manual-second".into();
    let (a, b) = tokio::join!(
        store.create_automation_run(&definition, &first, AutomationRunTrigger::Manual),
        store.create_automation_run(&definition, &second, AutomationRunTrigger::Manual)
    );
    assert_ne!(a.unwrap().number, b.unwrap().number);
}

#[tokio::test]
async fn editing_active_keeps_admitted_revision_and_resets_schedule_cursor() {
    let (_directory, store, definition) = fixture().await;
    let run = store
        .create_automation_run(
            &definition,
            &occurrence(&definition, "manual"),
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    let mut changed = definition.clone();
    changed.prompt_template = "New task".into();
    changed.schedule = AutomationSchedule::Recurring {
        cron: "0 10 * * *".into(),
        timezone: "UTC".into(),
        start_at: None,
        end_at: None,
        max_scheduled_runs: None,
    };
    let saved = store.upsert_automation(changed, actor()).await.unwrap();
    assert_eq!(saved.state, AutomationState::Active);
    assert!(saved.schedule_cursor_at.is_some());
    let run = store.find_automation_run(&run.id).await.unwrap().unwrap();
    assert_eq!(run.definition_revision, Some(definition.revision));
    assert_eq!(
        run.definition_snapshot.unwrap().prompt_template,
        definition.prompt_template
    );
}

#[tokio::test]
async fn attempts_preserve_deadline_and_budget_across_restart() {
    let (directory, store, definition) = fixture().await;
    let run = store
        .create_automation_run(
            &definition,
            &occurrence(&definition, "manual"),
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    let first = store.begin_automation_attempt(&run.id, 3).await.unwrap();
    assert!(store.begin_automation_attempt(&run.id, 3).await.is_err());
    store
        .schedule_automation_retry(&run.id, Utc::now(), "interrupted".into(), actor())
        .await
        .unwrap();
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    for count in [2, 3] {
        let next = store.begin_automation_attempt(&run.id, 3).await.unwrap();
        assert_eq!(next.attempt_count, count);
        assert_eq!(next.absolute_deadline_at, first.absolute_deadline_at);
        assert_ne!(next.attempt_id, first.attempt_id);
        store
            .schedule_automation_retry(&run.id, Utc::now(), "interrupted".into(), actor())
            .await
            .unwrap();
    }
    assert!(store.begin_automation_attempt(&run.id, 3).await.is_err());
    assert_eq!(store.automation_attempts(&run.id).await.unwrap().len(), 3);
    store
        .update_automation_run_status(&run.id, AutomationRunStatus::Failure, None)
        .await
        .unwrap();
    assert!(store.begin_automation_attempt(&run.id, 3).await.is_err());
}

#[tokio::test]
async fn trash_restore_preserves_completed_and_pauses_other_definitions() {
    let (_directory, store, definition) = fixture().await;
    store
        .set_automation_state(&definition.id, AutomationState::Trashed, actor(), None)
        .await
        .unwrap();
    assert_eq!(
        store
            .set_automation_state(&definition.id, AutomationState::Draft, actor(), None)
            .await
            .unwrap()
            .state,
        AutomationState::Paused
    );
    store
        .set_automation_state(&definition.id, AutomationState::Archived, actor(), None)
        .await
        .unwrap();
    store
        .set_automation_state(&definition.id, AutomationState::Trashed, actor(), None)
        .await
        .unwrap();
    assert_eq!(
        store
            .set_automation_state(&definition.id, AutomationState::Draft, actor(), None)
            .await
            .unwrap()
            .state,
        AutomationState::Archived
    );
}

#[tokio::test]
async fn gate_migration_requires_unambiguous_audit_evidence() {
    let (_directory, store, definition) = fixture().await;
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Blocked,
            actor(),
            Some("profile not opted in to automation execution"),
        )
        .await
        .unwrap();
    assert!(store
        .retired_gate_reactivation_candidates()
        .await
        .unwrap()
        .is_empty());
    store
        .set_automation_state(&definition.id, AutomationState::Active, actor(), None)
        .await
        .unwrap();
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Blocked,
            actor(),
            Some("profile not opted in to automation execution"),
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .retired_gate_reactivation_candidates()
            .await
            .unwrap()
            .len(),
        1
    );
    store
        .set_automation_state(
            &definition.id,
            AutomationState::Blocked,
            actor(),
            Some("Workspace missing"),
        )
        .await
        .unwrap();
    assert!(store
        .retired_gate_reactivation_candidates()
        .await
        .unwrap()
        .is_empty());
}
