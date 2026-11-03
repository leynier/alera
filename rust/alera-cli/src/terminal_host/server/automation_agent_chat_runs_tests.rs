use std::collections::HashMap;

use alera_core::runtime::{
    automation_from_input, AutomationActor, AutomationActorKind, AutomationOccurrence,
    AutomationRunTrigger, AutomationState, RuntimeStore,
};
use serde_json::json;

use super::*;
use crate::terminal_host::server::actor_test_harness::test_actor;
use crate::terminal_host::server::agent_chat_runtime::commands::SendInput;
use crate::terminal_host::server::automation_agent_chat_turns::wait_for_turn_end;
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;
use crate::terminal_host::server::chat_orchestration::ScheduleOp;

fn actor() -> AutomationActor {
    AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    }
}

fn definition(chat_id: &str, state: &str) -> AutomationDefinition {
    automation_from_input(
        &json!({
            "name": "Check the deploy",
            "promptTemplate": "Check the deploy.",
            "schedule": {"interval": {"everySeconds": 900, "anchor": Utc::now()}},
            "target": {"agentChat": {"chatId": chat_id, "workspaceId": "ws-a", "runtimeModeCeiling": "auto"}},
            "state": state,
        }),
        actor(),
    )
    .unwrap()
}

/// A dispatched run of `definition` waiting on `client_message_id`.
async fn dispatched_run(
    store: &RuntimeStore,
    definition: &AutomationDefinition,
    chat_id: &str,
    client_message_id: &str,
) -> AutomationRun {
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: format!("manual|{client_message_id}"),
        scheduled_at: Utc::now(),
        local_time: Utc::now().to_rfc3339(),
    };
    let mut run = store
        .create_automation_run(definition, &occurrence, AutomationRunTrigger::Manual)
        .await
        .unwrap();
    run = store
        .begin_automation_attempt(&run.id, definition.retry_max_attempts)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatched;
    run.chat_id = Some(chat_id.into());
    run.client_message_id = Some(client_message_id.into());
    store.save_automation_run(&run).await.unwrap()
}

#[tokio::test]
async fn a_run_ends_with_the_chat_turn_its_message_started() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    let saved = harness
        .store
        .upsert_automation(definition(&chat, "paused"), actor())
        .await
        .unwrap();
    let run = dispatched_run(&harness.store, &saved, &chat, "automation:run:1").await;
    let watcher = tokio::spawn({
        let store = harness.store.clone();
        let events = Some(harness.runtime.subscribe());
        let run_id = run.id.clone();
        let chat = chat.clone();
        async move { wait_for_turn_end(&store, events, &run_id, &chat, "automation:run:1").await }
    });
    harness
        .runtime
        .send(
            &chat,
            SendInput {
                client_message_id: "automation:run:1".into(),
                text: "Check the deploy.".into(),
                attachments: Vec::new(),
                delivery: "queue".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: Some("auto".into()),
                origin: Some(json!({"kind": "automation", "runId": run.id})),
            },
            CallerCtx {
                scope: "automation".into(),
                actor: "automation:test".into(),
                mobile: false,
            },
        )
        .await
        .unwrap();
    let control = harness.control(&chat).await;
    control.wait_turns(1).await;
    assert!(!watcher.is_finished());
    control.complete(1, "Deploy is healthy.");
    let ended = tokio::time::timeout(std::time::Duration::from_secs(20), watcher)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(ended, Some(("completed".to_owned(), None)));
    harness.finish().await;
}

#[tokio::test]
async fn a_post_above_the_scheduling_chats_mode_is_refused_for_good() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "full-access").await;
    let post = ChatPost {
        automation_id: "automation".into(),
        automation_name: "Check".into(),
        run_id: "run".into(),
        run_number: 1,
        chat_id: Some(chat.clone()),
        create: CreateChatInput {
            workspace_id: "ws-a".into(),
            ..Default::default()
        },
        text: "Check the deploy.".into(),
        client_message_id: "automation:run:capped".into(),
        runtime_mode_ceiling: Some("approval-required".into()),
    };
    let error = post.send(&harness.runtime).await.unwrap_err();
    assert!(refused_by_chat(&error), "{}", error.wire_message());
    harness.finish().await;
}

#[tokio::test]
async fn turn_ends_complete_fail_or_cancel_the_run() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor_under_test = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let store = actor_under_test.runtime_store.clone();
    let saved = store
        .upsert_automation(definition("chat", "paused"), actor())
        .await
        .unwrap();
    for (turn, expected) in [
        ("completed", AutomationRunStatus::Success),
        ("failed", AutomationRunStatus::Failure),
        ("interrupted", AutomationRunStatus::Cancelled),
    ] {
        let message = format!("automation:{turn}");
        let run = dispatched_run(&store, &saved, "chat", &message).await;
        // A late event for another message changes nothing.
        actor_under_test
            .handle_agent_chat_run_event(AgentChatRunEvent::TurnEnded {
                run_id: run.id.clone(),
                client_message_id: "automation:other".into(),
                status: turn.into(),
                error: None,
            })
            .await;
        assert!(!store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status
            .is_final());
        actor_under_test
            .handle_agent_chat_run_event(AgentChatRunEvent::TurnEnded {
                run_id: run.id.clone(),
                client_message_id: message,
                status: turn.into(),
                error: (turn != "completed").then(|| "provider stopped".into()),
            })
            .await;
        let finished = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(finished.status, expected, "{turn}");
        if expected == AutomationRunStatus::Failure {
            assert_eq!(finished.error.as_deref(), Some("provider stopped"));
        }
    }
}

#[tokio::test]
async fn deleting_a_scheduled_task_moves_its_automation_to_the_trash() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor_under_test = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let store = actor_under_test.runtime_store.clone();
    let saved = store
        .upsert_automation(definition("chat", "paused"), actor())
        .await
        .unwrap();
    actor_under_test
        .apply_schedule_op(ScheduleOp::Trash {
            id: saved.id.clone(),
            actor: actor(),
        })
        .await
        .unwrap();
    let trashed = store.find_automation(&saved.id).await.unwrap().unwrap();
    assert_eq!(trashed.state, AutomationState::Trashed);
    assert_eq!(trashed.state_before_trash, Some(AutomationState::Paused));
}
