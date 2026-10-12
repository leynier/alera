use super::reuse_fixture::{
    bind, binding, fresh_tab_target, new_run, put_session, put_tab, reuse_definition,
};
use super::*;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::server::automation_bound_target_resolution::{
    BoundTargetPlan, WAITING_FOR_BOUND_CONVERSATION,
};
use alera_core::runtime::{AutomationBoundTarget, AutomationReusePolicy};

async fn plan(fixture: &mut Harness, definition: &AutomationDefinition) -> BoundTargetPlan {
    let run = new_run(fixture, definition, &uuid::Uuid::new_v4().to_string()).await;
    fixture
        .actor
        .plan_bound_target(definition, &run)
        .await
        .unwrap()
}

fn owned(conversation: &str) -> serde_json::Value {
    json!({"terminalSessionId": "bound-session", "conversationId": conversation, "automationOwned": true, "agentProfileLaunchV1": {"profileId": "profile-1"}})
}

fn user_tab(conversation: &str) -> serde_json::Value {
    json!({"terminalSessionId": "bound-session", "conversationId": conversation})
}

fn assert_new_tab(plan: BoundTargetPlan, rebind: bool) {
    match plan {
        BoundTargetPlan::NewTabInWorkspace {
            workspace,
            profile_id,
            rebind_tab,
        } => {
            assert_eq!(workspace.id, "workspace-1");
            assert_eq!(profile_id, "profile-1");
            assert_eq!(rebind_tab, rebind);
        }
        _ => panic!("expected a new tab"),
    }
}

async fn released(fixture: &Harness) -> bool {
    let current = binding(fixture).await.unwrap();
    current.tab_id.is_none() && current.workspace_id == "workspace-1"
}

#[tokio::test]
async fn existing_tab_without_reuse_keeps_the_strict_checks() {
    let mut fixture = harness().await;
    let target = |conversation: Option<&str>| AutomationTarget::ExistingTab {
        workspace_id: "workspace-1".into(),
        tab_id: "bound-tab".into(),
        conversation_id: conversation.map(str::to_string),
    };
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::NewEachRun,
        target(Some("conversation-1")),
    )
    .await;
    let run = new_run(&mut fixture, &definition, "strict").await;
    let error = |result: crate::terminal_host::host_error::HostResult<BoundTargetPlan>| {
        result.unwrap_err().wire_message()
    };
    assert_eq!(
        error(fixture.actor.plan_bound_target(&definition, &run).await),
        "automation existing tab is missing"
    );
    put_tab(&mut fixture, "bound-tab", user_tab("other")).await;
    assert_eq!(
        error(fixture.actor.plan_bound_target(&definition, &run).await),
        "automation conversation identity changed"
    );
    put_tab(&mut fixture, "bound-tab", user_tab("conversation-1")).await;
    let message = error(fixture.actor.plan_bound_target(&definition, &run).await);
    assert_eq!(
        message,
        "automation existing tab has no live PTY after restart"
    );
    // The dispatcher blocks instead of retrying an existing tab that changed.
    assert!(message.starts_with("automation existing tab "));
    put_session(&mut fixture, "bound-session", true);
    assert!(matches!(
        fixture
            .actor
            .plan_bound_target(&definition, &run)
            .await
            .unwrap(),
        BoundTargetPlan::Busy {
            code: WAITING_FOR_BOUND_CONVERSATION,
            ..
        }
    ));
    fixture
        .actor
        .agent_presence
        .update("bound-session", "codex".into(), AgentPresenceState::Done);
    assert!(matches!(
        fixture
            .actor
            .plan_bound_target(&definition, &run)
            .await
            .unwrap(),
        BoundTargetPlan::PasteIntoConversation { .. }
    ));
    let without_conversation = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::NewEachRun,
        target(None),
    )
    .await;
    assert_eq!(
        error(
            fixture
                .actor
                .plan_bound_target(&without_conversation, &run)
                .await
        ),
        "automation conversation continuity cannot be proven"
    );
    assert_eq!(binding(&fixture).await, None);
}

#[tokio::test]
async fn existing_tab_reusing_its_conversation_seeds_the_binding() {
    let mut fixture = harness().await;
    put_tab(&mut fixture, "bound-tab", user_tab("conversation-1")).await;
    put_session(&mut fixture, "bound-session", true);
    fixture
        .actor
        .agent_presence
        .update("bound-session", "codex".into(), AgentPresenceState::Done);
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        AutomationTarget::ExistingTab {
            workspace_id: "workspace-1".into(),
            tab_id: "bound-tab".into(),
            conversation_id: Some("conversation-1".into()),
        },
    )
    .await;
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::PasteIntoConversation { session_id, .. } if session_id == "bound-session"
    ));
    let seeded = binding(&fixture).await.unwrap();
    assert_eq!(seeded.tab_id.as_deref(), Some("bound-tab"));
    assert_eq!(seeded.conversation_id.as_deref(), Some("conversation-1"));
}

#[tokio::test]
async fn without_a_binding_every_policy_creates_its_target() {
    let mut fixture = harness().await;
    for policy in [
        AutomationReusePolicy::NewEachRun,
        AutomationReusePolicy::ReuseWorkspace,
        AutomationReusePolicy::ReuseConversation,
    ] {
        let definition = reuse_definition(&mut fixture, policy, fresh_tab_target()).await;
        assert!(matches!(
            plan(&mut fixture, &definition).await,
            BoundTargetPlan::CreateNew
        ));
    }
}

#[tokio::test]
async fn a_missing_or_archived_workspace_clears_the_binding_and_recreates() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    bind(&mut fixture, Some("bound-tab"), None).await;
    let mut workspace = fixture
        .actor
        .runtime_store
        .find_workspace("workspace-1")
        .await
        .unwrap()
        .unwrap();
    workspace.is_archived = true;
    fixture
        .actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::Recreate {
            reason: "workspaceArchived"
        }
    ));
    assert_eq!(binding(&fixture).await, None);

    let mut elsewhere = AutomationBoundTarget {
        workspace_id: "gone".into(),
        tab_id: None,
        conversation_id: None,
        agent_profile_id: None,
        bound_run_id: "run".into(),
        bound_at: Utc::now(),
        last_run_id: None,
        last_verified_at: None,
    };
    fixture
        .actor
        .runtime_store
        .bind_automation_target("automation-1", &elsewhere, "test")
        .await
        .unwrap();
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::Recreate {
            reason: "workspaceGone"
        }
    ));
    assert_eq!(binding(&fixture).await, None);
    let mut restored = fixture
        .actor
        .runtime_store
        .find_workspace("workspace-1")
        .await
        .unwrap()
        .unwrap();
    restored.is_archived = false;
    fixture
        .actor
        .runtime_store
        .upsert_workspace(restored)
        .await
        .unwrap();
    elsewhere.workspace_id = "workspace-1".into();
    let retargeted = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        AutomationTarget::FreshTab {
            workspace_id: "workspace-2".into(),
            agent_profile_id: "profile-1".into(),
        },
    )
    .await;
    fixture
        .actor
        .runtime_store
        .bind_automation_target("automation-1", &elsewhere, "test")
        .await
        .unwrap();
    assert!(matches!(
        plan(&mut fixture, &retargeted).await,
        BoundTargetPlan::Recreate {
            reason: "targetChanged"
        }
    ));
}

#[tokio::test]
async fn workspace_reuse_opens_a_new_tab_and_conversation_reuse_rebinds_a_missing_tab() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseWorkspace,
        fresh_tab_target(),
    )
    .await;
    bind(&mut fixture, None, None).await;
    assert_new_tab(plan(&mut fixture, &definition).await, false);

    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    bind(&mut fixture, Some("missing-tab"), None).await;
    assert_new_tab(plan(&mut fixture, &definition).await, true);
}

#[tokio::test]
async fn a_taken_over_or_changed_conversation_releases_the_tab() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    let mut taken = owned("conversation-1");
    taken["automationTakenOver"] = json!(true);
    put_tab(&mut fixture, "bound-tab", taken).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    assert_new_tab(plan(&mut fixture, &definition).await, true);
    assert!(released(&fixture).await);

    put_tab(&mut fixture, "bound-tab", owned("conversation-2")).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    assert_new_tab(plan(&mut fixture, &definition).await, true);
    assert!(released(&fixture).await);
}

#[tokio::test]
async fn a_live_conversation_is_pasted_into_when_idle_and_waited_for_when_busy() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    put_tab(&mut fixture, "bound-tab", owned("conversation-1")).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    put_session(&mut fixture, "bound-session", true);
    fixture.actor.agent_presence.update(
        "bound-session",
        "codex".into(),
        AgentPresenceState::Working,
    );
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::Busy {
            code: WAITING_FOR_BOUND_CONVERSATION,
            ..
        }
    ));
    fixture
        .actor
        .agent_presence
        .update("bound-session", "codex".into(), AgentPresenceState::Done);
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::PasteIntoConversation { .. }
    ));
    assert_eq!(
        binding(&fixture).await.unwrap().tab_id.as_deref(),
        Some("bound-tab")
    );
}

#[tokio::test]
async fn a_live_terminal_without_an_agent_relaunches_only_automation_tabs() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    put_tab(&mut fixture, "bound-tab", owned("conversation-1")).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    put_session(&mut fixture, "bound-session", true);
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::RelaunchConversation {
            native_session_id: None,
            ..
        }
    ));

    put_tab(&mut fixture, "bound-tab", user_tab("conversation-1")).await;
    assert_new_tab(plan(&mut fixture, &definition).await, true);
    assert!(released(&fixture).await);
}

#[tokio::test]
async fn a_dead_terminal_relaunches_with_a_native_session_or_its_own_tab() {
    let mut fixture = harness().await;
    let definition = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        fresh_tab_target(),
    )
    .await;
    put_session(&mut fixture, "bound-session", false);
    let native = "019a0f6e-1111-4222-8333-444455556666";
    let mut resumable = user_tab("conversation-1");
    resumable["agentNativeSessionId"] = json!(native);
    resumable["agentNativeSessionAgent"] = json!("codex");
    put_tab(&mut fixture, "bound-tab", resumable).await;
    bind(&mut fixture, Some("bound-tab"), Some("conversation-1")).await;
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::RelaunchConversation {
            native_session_id: Some(id),
            ..
        } if id == native
    ));

    put_tab(&mut fixture, "bound-tab", owned("conversation-1")).await;
    assert!(matches!(
        plan(&mut fixture, &definition).await,
        BoundTargetPlan::RelaunchConversation {
            native_session_id: None,
            ..
        }
    ));

    put_tab(&mut fixture, "bound-tab", user_tab("conversation-1")).await;
    assert_new_tab(plan(&mut fixture, &definition).await, true);
    assert!(released(&fixture).await);
}

#[tokio::test]
async fn readiness_names_the_reuse_fields_and_softens_a_missing_conversation() {
    let mut fixture = harness().await;
    let existing_tab = json!({"existingTab": {"workspaceId": "workspace-1", "tabId": "gone-tab", "conversationId": "conversation-1"}});
    let base = json!({"name": "Reuse", "promptTemplate": "Go", "schedule": {"recurring": {"cron": "0 9 * * *", "timezone": "UTC"}}});
    let readiness = |changes: serde_json::Value| {
        let mut automation = base.clone();
        for (key, value) in changes.as_object().unwrap() {
            automation[key] = value.clone();
        }
        json!({"automation": automation})
    };
    let issues = |value: &serde_json::Value| {
        value["issues"]
            .as_array()
            .unwrap()
            .iter()
            .map(|issue| {
                (
                    issue["field"].as_str().unwrap().to_string(),
                    issue["severity"].as_str().unwrap().to_string(),
                )
            })
            .collect::<Vec<_>>()
    };
    let workspace_reuse = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.readiness",
            &readiness(json!({"target": existing_tab, "reusePolicy": "reuseWorkspace"})),
        )
        .await
        .unwrap();
    assert!(issues(&workspace_reuse).contains(&("reusePolicy".into(), "error".into())));
    let cleanup = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.readiness",
            &readiness(json!({"target": {"freshTab": {"workspaceId": "workspace-1", "agentProfileId": "profile-1"}}, "reusePolicy": "reuseConversation", "cleanupPolicy": "onSuccess"})),
        )
        .await
        .unwrap();
    assert!(issues(&cleanup).contains(&("cleanupPolicy".into(), "error".into())));

    let strict = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::NewEachRun,
        serde_json::from_value(existing_tab.clone()).unwrap(),
    )
    .await;
    let strict = fixture.actor.automation_readiness(&strict, false).await;
    assert_eq!(strict["ready"], false);

    let reusing = reuse_definition(
        &mut fixture,
        AutomationReusePolicy::ReuseConversation,
        serde_json::from_value(existing_tab).unwrap(),
    )
    .await;
    bind(&mut fixture, Some("gone-tab"), Some("conversation-1")).await;
    let reusing = fixture
        .actor
        .runtime_store
        .find_automation(&reusing.id)
        .await
        .unwrap()
        .unwrap();
    let readiness = fixture.actor.automation_readiness(&reusing, false).await;
    assert!(issues(&readiness).contains(&("target".into(), "warning".into())));
    assert_eq!(readiness["ready"], true, "{readiness}");
}
