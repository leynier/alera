use chrono::Utc;
use tempfile::TempDir;

use super::*;
use crate::runtime::{
    AutomationActorKind, AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy,
    AutomationState, AutomationTarget, AutomationTargetIdentity,
};

fn definition() -> AutomationDefinition {
    let now = Utc::now();
    AutomationDefinition {
        id: "automation-runs".into(),
        slug: "runs".into(),
        name: "Runs".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Run".into(),
        schedule: AutomationSchedule::OneTime {
            at: now + chrono::Duration::hours(1),
            timezone: "UTC".into(),
        },
        target: AutomationTarget::FreshTab {
            workspace_id: "workspace".into(),
            agent_profile_id: "profile".into(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
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
        state: super::super::AutomationState::Draft,
        revision: 1,
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
async fn completion_is_idempotent_and_heartbeat_updates_activity() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let definition = definition();
    let actor = definition.created_by.clone();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "oneTime|run".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-08-03T00:00".into(),
    };
    store
        .upsert_automation(definition.clone(), actor.clone())
        .await
        .unwrap();
    store
        .claim_automation_occurrence(&occurrence)
        .await
        .unwrap();
    let run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    let alive = store
        .heartbeat_automation_run(&run.id, actor.clone())
        .await
        .unwrap();
    assert!(alive.last_heartbeat_at.is_some());
    let done = store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("ok".into()),
            None,
            actor.clone(),
        )
        .await
        .unwrap();
    let same = store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Failure,
            Some("late completion".into()),
            Some("late".into()),
            actor,
        )
        .await
        .unwrap();
    assert_eq!(done.id, same.id);
    assert_eq!(same.status, AutomationRunStatus::Success);
    let archived = store
        .find_automation(&definition.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(archived.state, AutomationState::Archived);
}

#[tokio::test]
async fn lifecycle_identity_binds_actor_and_all_target_fields() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let definition = definition();
    let creator = definition.created_by.clone();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "scheduled|identity".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-08-03T00:00".into(),
    };
    store
        .upsert_automation(definition.clone(), creator)
        .await
        .unwrap();
    let run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    let actor = AutomationActor {
        kind: AutomationActorKind::ManagedAgent,
        id: Some("profile".into()),
        label: None,
    };
    let identity = AutomationTargetIdentity {
        workspace_id: Some("workspace".into()),
        tab_id: Some("tab".into()),
        session_id: Some("session".into()),
        profile_id: Some("profile".into()),
        conversation_id: Some("conversation".into()),
        terminal_handle: Some("session".into()),
    };
    store
        .bind_automation_run(&run.id, &actor, identity.clone())
        .await
        .unwrap();
    assert!(store
        .verify_automation_run_identity(&run.id, &actor, &identity)
        .await
        .is_ok());
    let mut wrong = identity;
    wrong.tab_id = Some("other-tab".into());
    assert!(store
        .verify_automation_run_identity(&run.id, &actor, &wrong)
        .await
        .is_err());
    let wrong_actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: Some("cli".into()),
        label: None,
    };
    assert!(store
        .verify_automation_run_identity(&run.id, &wrong_actor, &wrong)
        .await
        .is_err());
}

#[tokio::test]
async fn completion_rejects_blank_summary_and_non_final_status() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let definition = definition();
    let actor = definition.created_by.clone();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "oneTime|validation".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-08-03T00:00".into(),
    };
    store
        .upsert_automation(definition.clone(), actor.clone())
        .await
        .unwrap();
    let run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Manual)
        .await
        .unwrap();
    assert!(store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Success,
            Some("  ".into()),
            None,
            actor.clone(),
        )
        .await
        .is_err());
    assert!(store
        .complete_automation_run(
            &run.id,
            AutomationRunStatus::Dispatched,
            Some("not final".into()),
            None,
            actor,
        )
        .await
        .is_err());
}

#[tokio::test]
async fn retention_keeps_newest_hundred_final_runs_and_all_nonfinal_runs() {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let mut definition = definition();
    definition.schedule = AutomationSchedule::Recurring {
        cron: "* * * * *".into(),
        timezone: "UTC".into(),
        start_at: None,
        end_at: None,
        max_scheduled_runs: None,
    };
    let actor = definition.created_by.clone();
    store
        .upsert_automation(definition.clone(), actor)
        .await
        .unwrap();
    for index in 0..101 {
        let occurrence = AutomationOccurrence {
            automation_id: definition.id.clone(),
            key: format!("scheduled|retention|{index}"),
            scheduled_at: Utc::now(),
            local_time: format!("2026-08-03T00:{index:02}"),
        };
        let run = store
            .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
            .await
            .unwrap();
        store
            .update_automation_run_status(&run.id, AutomationRunStatus::Success, None)
            .await
            .unwrap();
    }
    let pending_occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "scheduled|retention|pending".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-08-03T01:00".into(),
    };
    store
        .create_automation_run(
            &definition,
            &pending_occurrence,
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    store.prune_automation_history(Utc::now()).await.unwrap();
    let runs = store
        .list_automation_runs(Some(&definition.id), 200)
        .await
        .unwrap();
    assert_eq!(
        runs.iter()
            .filter(|run| run.status == AutomationRunStatus::Success)
            .count(),
        100
    );
    assert_eq!(
        runs.iter()
            .filter(|run| run.status == AutomationRunStatus::Pending)
            .count(),
        1
    );
}
