use super::reuse_fixture::{bind, binding, fresh_tab_target, new_run, put_tab, reuse_definition};
use super::*;
use crate::terminal_host::client::ClientFrame;
use alera_core::runtime::{
    AutomationBoundTarget, AutomationReusePolicy, AutomationRun, AutomationRunStatus,
};

fn owned_tab() -> serde_json::Value {
    json!({"terminalSessionId": "bound-session", "conversationId": "conversation-1", "automationOwned": true, "automationRunId": "earlier-run"})
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

async fn bound_owned_run(fixture: &mut Harness) -> AutomationRun {
    let definition = reuse_definition(
        fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    let mut run = new_run(fixture, &definition, "owned").await;
    let mut started = fixture
        .actor
        .runtime_store
        .begin_automation_attempt(&run.id, 3)
        .await
        .unwrap();
    started.status = AutomationRunStatus::Dispatched;
    started.workspace_id = Some("workspace-1".into());
    started.tab_id = Some("bound-tab".into());
    started.session_id = Some("bound-session".into());
    started.owned_tab = true;
    started.started_at = Some(Utc::now() - chrono::Duration::hours(3));
    started.last_heartbeat_at = started.started_at;
    started.last_activity_at = started.started_at;
    run = fixture
        .actor
        .runtime_store
        .save_automation_run(&started)
        .await
        .unwrap();
    let mut payload = owned_tab();
    payload["automationRunId"] = json!(run.id);
    put_tab(fixture, "bound-tab", payload).await;
    bind(fixture, Some("bound-tab"), Some("conversation-1")).await;
    run
}

#[tokio::test]
async fn takeover_and_timeout_release_the_bound_tab() {
    let mut fixture = harness().await;
    let run = bound_owned_run(&mut fixture).await;
    fixture
        .actor
        .handle_automation_request(1, "automation.takeOver", &json!({"runId": run.id}))
        .await
        .unwrap();
    let released = binding(&fixture).await.unwrap();
    assert_eq!(released.tab_id, None);
    assert_eq!(released.workspace_id, "workspace-1");

    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    let mut taken = stored(&fixture, &run.id).await;
    taken.taken_over = false;
    fixture
        .actor
        .runtime_store
        .save_automation_run(&taken)
        .await
        .unwrap();
    fixture.actor.expire_inactive_automation_runs().await;
    assert_eq!(
        stored(&fixture, &run.id).await.status,
        AutomationRunStatus::Timeout
    );
    assert_eq!(binding(&fixture).await.unwrap().tab_id, None);
}

fn automation_events(fixture: &mut Harness) -> Vec<serde_json::Value> {
    let mut events = Vec::new();
    while let Ok(frame) = fixture.events.try_recv() {
        let value = match frame {
            ClientFrame::Json(value) => value,
            ClientFrame::OrderedControl { frame, .. } => match *frame {
                ClientFrame::Json(value) => value,
                _ => continue,
            },
            _ => continue,
        };
        if value["event"] == "automationsChanged" {
            events.push(value);
        }
    }
    events
}

#[tokio::test]
async fn unbind_clears_the_binding_and_patch_cannot_write_it() {
    let mut fixture = harness().await;
    reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    put_tab(&mut fixture, "bound-tab", owned_tab()).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    let forged = AutomationBoundTarget {
        workspace_id: "forged".into(),
        tab_id: None,
        conversation_id: None,
        agent_profile_id: None,
        bound_run_id: "forged".into(),
        bound_at: Utc::now(),
        last_run_id: None,
        last_verified_at: None,
    };
    let patched = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.patch",
            &json!({"id": "automation-1", "changes": {"name": "Renamed", "boundTarget": forged}}),
        )
        .await
        .unwrap();
    assert_eq!(patched["boundTarget"]["workspaceId"], "workspace-1");
    assert_eq!(patched["reusePolicy"], "reuseConversation");
    assert_eq!(
        patched["boundTargetSummary"],
        "Workspace Workspace · tab Codex"
    );
    automation_events(&mut fixture);

    let unbound = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.unbind",
            &json!({"id": "automation-1", "reason": "fresh start"}),
        )
        .await
        .unwrap();
    assert!(unbound["boundTarget"].is_null());
    assert!(unbound["boundTargetSummary"].is_null());
    assert_eq!(binding(&fixture).await, None);
    let events = automation_events(&mut fixture);
    assert_eq!(events.len(), 1, "{events:?}");
    assert_eq!(events[0]["payload"]["automationId"], "automation-1");
    let audit = fixture
        .actor
        .runtime_store
        .list_automation_audit_events(Some("automation-1"), 50)
        .await
        .unwrap();
    assert!(audit
        .iter()
        .any(|event| event.action == "targetUnbound" && event.details["reason"] == "fresh start"));
}

#[test]
fn reuse_is_advertised_and_unbind_is_allowed_on_mobile() {
    use super::super::mobile_gateway_surface::{mobile_request_allowed, MOBILE_HELLO_CAPABILITIES};
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&"automationReuseV1"));
    assert!(mobile_request_allowed("automation.unbind"));
}

#[tokio::test]
async fn status_reports_the_reuse_capability() {
    let fixture = harness().await;
    let status = fixture.actor.host_status_payload();
    assert!(status["runtimeCapabilities"]
        .as_array()
        .unwrap()
        .contains(&json!("automationReuseV1")));
}
