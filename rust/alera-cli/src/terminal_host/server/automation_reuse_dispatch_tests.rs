use super::reuse_fixture::{bind, binding, fresh_tab_target, new_run, put_tab, reuse_definition};
use super::*;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::session::Session;
use crate::terminal_host::session::TestQueuedWrite;
use alera_core::runtime::{
    AutomationOccurrence, AutomationOverlapPolicy, AutomationReusePolicy, AutomationRun,
    AutomationRunReuse, AutomationRunStatus, AutomationRunTrigger,
};
use std::sync::mpsc::Receiver;
use std::time::Duration;

fn owned_tab() -> serde_json::Value {
    json!({"terminalSessionId": "bound-session", "conversationId": "conversation-1", "automationOwned": true, "automationRunId": "earlier-run"})
}

/// A bound, idle conversation whose PTY records what the host writes.
async fn idle_bound_conversation(
    fixture: &mut Harness,
    policy: AutomationReusePolicy,
) -> (AutomationDefinition, Receiver<TestQueuedWrite>) {
    let definition = reuse_definition(fixture, policy, fresh_tab_target()).await;
    put_tab(fixture, "bound-tab", owned_tab()).await;
    bind(fixture, Some("bound-tab"), Some("conversation-1")).await;
    let mut session = Session::driver_test_stub("bound-session", 80, 24);
    let writes = session.attach_test_input();
    fixture
        .actor
        .sessions
        .insert("bound-session".into(), session);
    fixture
        .actor
        .agent_presence
        .update("bound-session", "codex".into(), AgentPresenceState::Done);
    (definition, writes)
}

async fn finished_previous_run(
    fixture: &mut Harness,
    definition: &AutomationDefinition,
    summary: &str,
) -> AutomationRun {
    let mut previous = new_run(fixture, definition, "previous").await;
    previous.status = AutomationRunStatus::Success;
    previous.summary = Some(summary.into());
    previous.finished_at = Some(Utc::now());
    let previous = fixture
        .actor
        .runtime_store
        .save_automation_run(&previous)
        .await
        .unwrap();
    let mut current = binding(fixture).await.unwrap();
    current.last_run_id = Some(previous.id.clone());
    fixture
        .actor
        .runtime_store
        .bind_automation_target(&definition.id, &current, "test")
        .await
        .unwrap();
    previous
}

async fn stored(fixture: &Harness, id: &str) -> AutomationRun {
    fixture
        .actor
        .runtime_store
        .find_automation_run(id)
        .await
        .unwrap()
        .unwrap()
}

fn pasted(writes: &Receiver<TestQueuedWrite>) -> String {
    let write = writes.recv_timeout(Duration::from_secs(5)).unwrap();
    String::from_utf8_lossy(&write.bytes).into_owned()
}

#[tokio::test]
async fn an_idle_bound_conversation_receives_the_run_with_a_bounded_preface() {
    let mut fixture = harness().await;
    let (definition, writes) =
        idle_bound_conversation(&mut fixture, AutomationReusePolicy::ReuseConversation).await;
    finished_previous_run(&mut fixture, &definition, &"x".repeat(2000)).await;
    let run = new_run(&mut fixture, &definition, "second").await;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), false)
        .await;

    let dispatched = stored(&fixture, &run.id).await;
    assert_eq!(dispatched.status, AutomationRunStatus::Dispatched);
    assert_eq!(dispatched.reuse, Some(AutomationRunReuse::Conversation));
    assert_eq!(dispatched.tab_id.as_deref(), Some("bound-tab"));
    assert_eq!(dispatched.session_id.as_deref(), Some("bound-session"));
    assert!(dispatched.owned_tab);
    let identity = dispatched.target_identity.clone().unwrap();
    assert_eq!(identity.conversation_id.as_deref(), Some("conversation-1"));
    let attempts = fixture
        .actor
        .runtime_store
        .automation_attempts(&run.id)
        .await
        .unwrap();
    assert_eq!(attempts.len(), 1);
    assert_eq!(attempts[0].launch_kind.as_deref(), Some("reusePaste"));
    let tab = fixture
        .actor
        .runtime_store
        .find_workspace_tab("bound-tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(tab.payload["automationRunId"], run.id.as_str());
    assert_eq!(
        tab.payload["automationAttemptId"].as_str(),
        dispatched.attempt_id.as_deref()
    );
    let bound = binding(&fixture).await.unwrap();
    assert_eq!(bound.tab_id.as_deref(), Some("bound-tab"));
    assert_eq!(bound.last_run_id.as_deref(), Some(run.id.as_str()));

    let prompt = pasted(&writes);
    assert!(prompt.contains("This is run #"), "{prompt}");
    assert!(prompt.contains("delivered to the conversation it used before"));
    assert!(prompt.contains(&format!("{}...", "x".repeat(509))));
    assert!(!prompt.contains(&"x".repeat(510)));
    assert!(prompt.contains(&format!("--attempt-id {}", dispatched.attempt_id.unwrap())));
    let rendered = dispatched.rendered_prompt.unwrap();
    assert!(rendered.starts_with("This is run #"));
}

#[tokio::test]
async fn no_preface_without_a_finished_previous_run() {
    let mut fixture = harness().await;
    let (definition, writes) =
        idle_bound_conversation(&mut fixture, AutomationReusePolicy::ReuseConversation).await;
    let run = new_run(&mut fixture, &definition, "second").await;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), false)
        .await;
    assert!(!pasted(&writes).contains("This is run #"));
}

#[tokio::test]
async fn a_busy_bound_conversation_parks_the_run_without_spending_an_attempt() {
    let mut fixture = harness().await;
    let (definition, _writes) =
        idle_bound_conversation(&mut fixture, AutomationReusePolicy::ReuseConversation).await;
    fixture.actor.agent_presence.update(
        "bound-session",
        "codex".into(),
        AgentPresenceState::Working,
    );
    let run = new_run(&mut fixture, &definition, "parked").await;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), true)
        .await;
    let parked = stored(&fixture, &run.id).await;
    assert_eq!(parked.status, AutomationRunStatus::Pending);
    assert_eq!(parked.attempt_count, 0);
    assert_eq!(parked.started_at, None);
    assert_eq!(parked.precheck, Some(false));
    assert!(parked.retry_after.is_some_and(|at| at > Utc::now()));
    let recovery = parked.recovery.unwrap();
    assert_eq!(recovery.status, "waiting");
    assert_eq!(
        recovery.code.as_deref(),
        Some("waitingForBoundConversation")
    );
    assert!(fixture
        .actor
        .runtime_store
        .automation_attempts(&run.id)
        .await
        .unwrap()
        .is_empty());
}

async fn overdue_run(
    fixture: &mut Harness,
    definition: &AutomationDefinition,
    overlap: AutomationOverlapPolicy,
) -> AutomationRun {
    let mut run = fixture
        .actor
        .runtime_store
        .create_automation_run(
            definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: uuid::Uuid::new_v4().to_string(),
                scheduled_at: Utc::now() - chrono::Duration::hours(2),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    run.overlap_policy = Some(overlap);
    fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap()
}

#[tokio::test]
async fn a_conversation_busy_past_the_grace_window_skips_or_opens_a_parallel_tab() {
    let mut fixture = harness().await;
    let (definition, _writes) =
        idle_bound_conversation(&mut fixture, AutomationReusePolicy::ReuseConversation).await;
    fixture.actor.agent_presence.update(
        "bound-session",
        "codex".into(),
        AgentPresenceState::Working,
    );
    let skipped = overdue_run(&mut fixture, &definition, AutomationOverlapPolicy::Skip).await;
    fixture
        .actor
        .start_automation_run(&definition, skipped.clone(), false)
        .await;
    let skipped = stored(&fixture, &skipped.id).await;
    assert_eq!(skipped.status, AutomationRunStatus::OverlapSkipped);
    assert_eq!(
        skipped.error.as_deref(),
        Some("bound conversation stayed busy past the misfire grace window")
    );

    let parallel = overdue_run(
        &mut fixture,
        &definition,
        AutomationOverlapPolicy::ForceParallel,
    )
    .await;
    fixture
        .actor
        .start_automation_run(&definition, parallel.clone(), false)
        .await;
    let parallel = stored(&fixture, &parallel.id).await;
    assert_eq!(parallel.status, AutomationRunStatus::Dispatched);
    assert_eq!(parallel.reuse, Some(AutomationRunReuse::Workspace));
    assert_ne!(parallel.tab_id.as_deref(), Some("bound-tab"));
    assert_eq!(parallel.workspace_id.as_deref(), Some("workspace-1"));
    assert_eq!(
        binding(&fixture).await.unwrap().tab_id.as_deref(),
        Some("bound-tab"),
        "a parallel run never moves the binding"
    );
}

#[tokio::test]
async fn the_first_reusing_run_binds_the_tab_it_created() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    let run = new_run(&mut fixture, &definition, "first").await;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), false)
        .await;
    let dispatched = stored(&fixture, &run.id).await;
    assert_eq!(dispatched.status, AutomationRunStatus::Dispatched);
    assert_eq!(dispatched.reuse, Some(AutomationRunReuse::Bound));
    let bound = binding(&fixture).await.unwrap();
    assert_eq!(bound.workspace_id, "workspace-1");
    assert_eq!(bound.tab_id, dispatched.tab_id);
    assert_eq!(bound.bound_run_id, run.id);
    assert_eq!(bound.agent_profile_id.as_deref(), Some("profile-1"));
}

#[tokio::test]
async fn run_again_on_a_reusing_automation_returns_to_its_bound_target() {
    let mut fixture = harness().await;
    let (definition, writes) =
        idle_bound_conversation(&mut fixture, AutomationReusePolicy::ReuseConversation).await;
    let previous = finished_previous_run(&mut fixture, &definition, "Done before").await;
    let next = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.runNow",
            &json!({"id": definition.id, "continueFromRunId": previous.id}),
        )
        .await
        .unwrap();
    let next: AutomationRun = serde_json::from_value(next).unwrap();
    assert_eq!(
        next.continue_from_run_id.as_deref(),
        Some(previous.id.as_str())
    );
    assert_eq!(next.tab_id.as_deref(), Some("bound-tab"));
    assert_eq!(next.reuse, Some(AutomationRunReuse::Conversation));
    let rendered = next.rendered_prompt.unwrap();
    assert!(rendered.contains("Previous run summary: Done before"));
    assert!(!rendered.contains(&format!("Previous run {} summary", previous.id)));
    assert!(pasted(&writes).contains("Done before"));
}

#[tokio::test]
async fn recovery_moves_the_binding_to_the_relaunched_tab() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    let run = new_run(&mut fixture, &definition, "interrupted").await;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), false)
        .await;
    let mut interrupted = stored(&fixture, &run.id).await;
    let first_tab = interrupted.tab_id.clone().unwrap();
    assert_eq!(
        binding(&fixture).await.unwrap().tab_id.as_deref(),
        Some(first_tab.as_str())
    );
    fixture.actor.terminate_sessions_for_tab(&first_tab).await;
    interrupted.status = AutomationRunStatus::Pending;
    interrupted.recovery = Some(alera_core::runtime::AutomationRecovery {
        status: "retryingWithContext".into(),
        attempt: interrupted.attempt_count,
        max_attempts: 3,
        interrupted_at: Some(Utc::now()),
        code: Some("runtimeRestart".into()),
    });
    let interrupted = fixture
        .actor
        .runtime_store
        .save_automation_run(&interrupted)
        .await
        .unwrap();
    fixture
        .actor
        .resume_interrupted_automation_run(&definition, interrupted)
        .await;
    let recovered = stored(&fixture, &run.id).await;
    assert_eq!(recovered.status, AutomationRunStatus::Dispatched);
    assert_ne!(recovered.tab_id.as_deref(), Some(first_tab.as_str()));
    assert_eq!(binding(&fixture).await.unwrap().tab_id, recovered.tab_id);
}
