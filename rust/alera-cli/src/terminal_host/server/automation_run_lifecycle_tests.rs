use std::collections::HashMap;

use alera_core::runtime::{
    AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
    AutomationOccurrence, AutomationOverlapPolicy, AutomationRun, AutomationRunStatus,
    AutomationRunTrigger, AutomationSchedule, AutomationSetupPolicy, AutomationState,
    AutomationTarget, WorkspaceTabRecord,
};
use chrono::{Duration, Utc};
use serde_json::json;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::server::ServerActor;
use crate::terminal_host::session::Session;

const WORKSPACE_ID: &str = "workspace";
const TAB_ID: &str = "owned-tab";
const SETUP_TAB_ID: &str = "setup-tab";
const SESSION_ID: &str = "owned-session";
const SETUP_SESSION_ID: &str = "setup-session";
const NEIGHBOR_TAB_ID: &str = "neighbor-tab";
const NEIGHBOR_SESSION_ID: &str = "neighbor-session";

struct ExpireCase {
    owned_tab: bool,
    taken_over: bool,
    include_setup_tab: bool,
    inactivity_timeout_seconds: i64,
    started_ago: Duration,
    absolute_deadline_ago: Option<Duration>,
    cancel_requested_ago: Option<Duration>,
}

impl Default for ExpireCase {
    fn default() -> Self {
        Self {
            owned_tab: true,
            taken_over: false,
            include_setup_tab: false,
            inactivity_timeout_seconds: 7200,
            started_ago: Duration::seconds(10),
            absolute_deadline_ago: None,
            cancel_requested_ago: None,
        }
    }
}

struct ExpireHarness {
    _dir: tempfile::TempDir,
    actor: ServerActor,
    run_id: String,
}

async fn expire_harness(case: ExpireCase) -> ExpireHarness {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _events) = ClientHandle::test_channels();
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
    let definition = definition(case.inactivity_timeout_seconds);
    let actor_record = definition.created_by.clone();
    actor
        .runtime_store
        .upsert_automation(definition.clone(), actor_record)
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "manual|expire".into(),
        scheduled_at: now,
        local_time: "2026-09-08T00:00".into(),
    };
    let mut run = actor
        .runtime_store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Manual)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatched;
    run.workspace_id = Some(WORKSPACE_ID.into());
    run.tab_id = Some(TAB_ID.into());
    run.session_id = Some(SESSION_ID.into());
    run.owned_tab = case.owned_tab;
    run.taken_over = case.taken_over;
    run.started_at = Some(now - case.started_ago);
    run.absolute_deadline_at = case.absolute_deadline_ago.map(|ago| now - ago);
    run.cancel_requested_at = case.cancel_requested_ago.map(|ago| now - ago);
    if case.include_setup_tab {
        run.setup_tab_id = Some(SETUP_TAB_ID.into());
    }
    actor.runtime_store.save_automation_run(&run).await.unwrap();

    upsert_tab(&actor, TAB_ID).await;
    upsert_tab(&actor, NEIGHBOR_TAB_ID).await;
    if case.include_setup_tab {
        upsert_tab(&actor, SETUP_TAB_ID).await;
    }

    actor
        .sessions
        .insert(SESSION_ID.into(), stub_session(SESSION_ID, TAB_ID));
    actor.sessions.insert(
        NEIGHBOR_SESSION_ID.into(),
        stub_session(NEIGHBOR_SESSION_ID, NEIGHBOR_TAB_ID),
    );
    if case.include_setup_tab {
        actor.sessions.insert(
            SETUP_SESSION_ID.into(),
            stub_session(SETUP_SESSION_ID, SETUP_TAB_ID),
        );
    }

    ExpireHarness {
        run_id: run.id,
        actor,
        _dir: dir,
    }
}

fn definition(inactivity_timeout_seconds: i64) -> AutomationDefinition {
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
        inactivity_timeout_seconds,
        heartbeat_interval_seconds: inactivity_timeout_seconds.clamp(1, 60),
        misfire_grace_seconds: 900,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        state: AutomationState::Active,
        revision: 1,
        approved_revision: Some(1),
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

fn stub_session(session_id: &str, tab_id: &str) -> Session {
    let mut session = Session::driver_test_stub(session_id, 80, 24);
    session.tab_id = tab_id.to_string();
    session.workspace_id = WORKSPACE_ID.to_string();
    session
}

async fn upsert_tab(actor: &ServerActor, tab_id: &str) {
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: tab_id.to_string(),
            workspace_id: WORKSPACE_ID.to_string(),
            kind: "terminal".to_string(),
            title: tab_id.to_string(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();
}

async fn tab_exists(actor: &ServerActor, tab_id: &str) -> bool {
    actor
        .runtime_store
        .find_workspace_tab(tab_id)
        .await
        .unwrap()
        .is_some()
}

async fn saved_run(actor: &ServerActor, run_id: &str) -> AutomationRun {
    actor
        .runtime_store
        .find_automation_run(run_id)
        .await
        .unwrap()
        .expect("automation run should still exist")
}

#[tokio::test]
async fn inactivity_timeout_terminates_owned_tab_session() {
    let mut harness = expire_harness(ExpireCase {
        inactivity_timeout_seconds: 1,
        started_ago: Duration::seconds(5),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Timeout);
    assert_eq!(
        run.error.as_deref(),
        Some("automation inactivity timeout exceeded")
    );
    assert!(!harness.actor.sessions.contains_key(SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
    assert!(tab_exists(&harness.actor, TAB_ID).await);
}

#[tokio::test]
async fn absolute_deadline_terminates_owned_tab_session() {
    let mut harness = expire_harness(ExpireCase {
        absolute_deadline_ago: Some(Duration::seconds(1)),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Timeout);
    assert_eq!(
        run.error.as_deref(),
        Some("automation absolute 24-hour maximum exceeded")
    );
    assert!(!harness.actor.sessions.contains_key(SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
    assert!(tab_exists(&harness.actor, TAB_ID).await);
}

#[tokio::test]
async fn timeout_does_not_terminate_taken_over_tab() {
    let mut harness = expire_harness(ExpireCase {
        taken_over: true,
        inactivity_timeout_seconds: 1,
        started_ago: Duration::seconds(5),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Timeout);
    assert!(harness.actor.sessions.contains_key(SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
}

#[tokio::test]
async fn timeout_does_not_terminate_non_owned_tab() {
    let mut harness = expire_harness(ExpireCase {
        owned_tab: false,
        inactivity_timeout_seconds: 1,
        started_ago: Duration::seconds(5),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Timeout);
    assert!(harness.actor.sessions.contains_key(SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
}

#[tokio::test]
async fn cancellation_grace_still_terminates_owned_tab() {
    let mut harness = expire_harness(ExpireCase {
        cancel_requested_ago: Some(Duration::seconds(31)),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Cancelled);
    assert_eq!(
        run.error.as_deref(),
        Some("automation cancellation grace elapsed")
    );
    assert!(!harness.actor.sessions.contains_key(SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
    assert!(tab_exists(&harness.actor, TAB_ID).await);
}

#[tokio::test]
async fn timeout_terminates_owned_setup_tab_session() {
    let mut harness = expire_harness(ExpireCase {
        include_setup_tab: true,
        inactivity_timeout_seconds: 1,
        started_ago: Duration::seconds(5),
        ..ExpireCase::default()
    })
    .await;

    harness.actor.expire_inactive_automation_runs().await;

    let run = saved_run(&harness.actor, &harness.run_id).await;
    assert_eq!(run.status, AutomationRunStatus::Timeout);
    assert!(!harness.actor.sessions.contains_key(SESSION_ID));
    assert!(!harness.actor.sessions.contains_key(SETUP_SESSION_ID));
    assert!(harness.actor.sessions.contains_key(NEIGHBOR_SESSION_ID));
    assert!(tab_exists(&harness.actor, TAB_ID).await);
    assert!(tab_exists(&harness.actor, SETUP_TAB_ID).await);
}
