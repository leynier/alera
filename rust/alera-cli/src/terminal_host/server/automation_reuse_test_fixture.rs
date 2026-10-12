//! Shared setup for the conversation and workspace reuse tests.

use super::*;
use crate::terminal_host::session::Session;
use alera_core::runtime::{
    AutomationBoundTarget, AutomationOccurrence, AutomationReusePolicy, AutomationRun,
    AutomationRunTrigger, WorkspaceTabRecord,
};

pub(super) async fn reuse_definition(
    fixture: &mut Harness,
    policy: AutomationReusePolicy,
    target: AutomationTarget,
) -> AutomationDefinition {
    let mut definition = draft_definition();
    definition.reuse_policy = policy;
    definition.target = target;
    fixture
        .actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap()
}

pub(super) fn fresh_tab_target() -> AutomationTarget {
    AutomationTarget::FreshTab {
        workspace_id: "workspace-1".into(),
        agent_profile_id: "profile-1".into(),
    }
}

pub(super) async fn new_run(
    fixture: &mut Harness,
    definition: &AutomationDefinition,
    key: &str,
) -> AutomationRun {
    fixture
        .actor
        .runtime_store
        .create_automation_run(
            definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: key.into(),
                scheduled_at: Utc::now(),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap()
}

pub(super) async fn put_tab(fixture: &mut Harness, id: &str, payload: serde_json::Value) {
    let now = Utc::now();
    fixture
        .actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: id.into(),
            workspace_id: "workspace-1".into(),
            kind: "terminal".into(),
            title: "Codex".into(),
            created_at: now,
            updated_at: now,
            payload,
        })
        .await
        .unwrap();
}

pub(super) fn put_session(fixture: &mut Harness, id: &str, running: bool) {
    let mut session = Session::driver_test_stub(id, 80, 24);
    if !running {
        session.mark_exited_for_test();
    }
    fixture.actor.sessions.insert(id.into(), session);
}

pub(super) async fn bind(fixture: &mut Harness, tab: Option<&str>, conversation: Option<&str>) {
    let binding = AutomationBoundTarget {
        workspace_id: "workspace-1".into(),
        tab_id: tab.map(str::to_string),
        conversation_id: conversation.map(str::to_string),
        agent_profile_id: Some("profile-1".into()),
        bound_run_id: "earlier-run".into(),
        bound_at: Utc::now(),
        last_run_id: None,
        last_verified_at: None,
    };
    fixture
        .actor
        .runtime_store
        .bind_automation_target("automation-1", &binding, "test")
        .await
        .unwrap();
}

pub(super) async fn binding(fixture: &Harness) -> Option<AutomationBoundTarget> {
    fixture
        .actor
        .runtime_store
        .find_automation("automation-1")
        .await
        .unwrap()
        .unwrap()
        .bound_target
}
