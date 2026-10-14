use super::*;
use std::sync::Arc;
use std::time::Duration;

use super::super::events::NullSink;
use super::super::session::SessionDeps;
use super::super::wire::{ChatItem, ChatTurn};
use super::super::{ChatActivity, InstanceDirectory};
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;
use alera_core::runtime::{
    AgentChatNativeIdInput, AgentChatNativeOperationInput, AgentChatNativeOperationReceipt,
};

#[path = "session_native_history_admission_tests.rs"]
mod admission_tests;

fn operation(state: &str, kind: &str) -> AgentChatNativeOperation {
    AgentChatNativeOperation {
        operation_id: uuid::Uuid::new_v4().to_string(),
        chat_id: uuid::Uuid::new_v4().to_string(),
        generation: 4,
        base_cursor: 9,
        native_thread_id: "private-native-thread".into(),
        process_epoch: "private-process-epoch".into(),
        kind: kind.into(),
        turn_id: "private-app-turn".into(),
        boundary: json!({"type":"beforeTurn","value":"private-native-turn"}),
        actor: "private-actor".into(),
        caller_scope: "private-caller-scope".into(),
        verb: "private-receipt-verb".into(),
        request_id: "private-request-id".into(),
        digest: "private-digest".into(),
        state: state.into(),
        revision: 3,
        ack: Some(json!({"acknowledged":true,"untrustedPayload":"private-ack"})),
        result: Some(json!({"response":"private-result"})),
    }
}

#[test]
fn public_status_contains_only_the_confirmed_package_contract() {
    let operation = operation("acknowledged", AGENT_CHAT_NATIVE_REWIND);
    let summary = native_operation_public_summary(&operation);
    let mut keys = summary
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect::<Vec<_>>();
    keys.sort_unstable();
    assert_eq!(keys, ["kind", "operationId", "recovery", "state"]);
    assert_eq!(summary["operationId"], operation.operation_id);
    let serialized = summary.to_string();
    for hidden in [
        "private-native-thread",
        "private-process-epoch",
        "private-native-turn",
        "private-app-turn",
        "private-actor",
        "private-caller-scope",
        "private-receipt-verb",
        "private-request-id",
        "private-digest",
        "private-ack",
        "private-result",
    ] {
        assert!(
            !serialized.contains(hidden),
            "public status exposed {hidden}"
        );
    }
    assert_eq!(summary["recovery"]["canFinishAcknowledged"], true);
    assert_eq!(summary["recovery"].as_object().unwrap().len(), 6);
}

#[test]
fn unknown_state_or_kind_is_never_echoed_and_remains_frozen() {
    let operation = operation("private-provider-state", "private-provider-kind");
    let summary = native_operation_public_summary(&operation);
    assert_eq!(summary["state"], "unknown");
    assert_eq!(summary["kind"], "unknown");
    assert!(!summary.to_string().contains("private-provider"));
    assert_eq!(summary["recovery"]["needsReconciliation"], true);
    for action in [
        "canCancelUnstarted",
        "canFinishAcknowledged",
        "canRestartFromTranscript",
        "canContinueFromCurrentFiles",
    ] {
        assert_eq!(summary["recovery"][action], false);
    }
}

#[test]
fn unknown_kind_never_offers_actions_for_a_recognized_prepared_or_acknowledged_state() {
    for state in ["prepared", "acknowledged"] {
        let summary = native_operation_public_summary(&operation(state, "unsupported-kind"));
        assert_eq!(summary["recovery"]["needsReconciliation"], true);
        for action in [
            "canCancelUnstarted",
            "canFinishAcknowledged",
            "canRestartFromTranscript",
            "canContinueFromCurrentFiles",
        ] {
            assert_eq!(
                summary["recovery"][action], false,
                "{state} exposed {action}"
            );
        }
    }
}

#[test]
fn prepared_cancellation_does_not_offer_an_acknowledged_or_uncertain_action() {
    let summary = native_operation_recovery(&operation("prepared", AGENT_CHAT_NATIVE_REWIND));
    assert_eq!(summary["needsReconciliation"], true);
    assert_eq!(summary["canCancelUnstarted"], true);
    assert_eq!(summary["canFinishAcknowledged"], false);
    assert_eq!(summary["canRestartFromTranscript"], false);
    assert!(native_operation_transition_allowed("prepared", "cancelled"));
    assert!(!native_operation_transition_allowed(
        "prepared",
        "acknowledged"
    ));
}

#[test]
fn acknowledged_operation_requires_evidence_and_never_offers_another_native_attempt() {
    let mut operation = operation("acknowledged", AGENT_CHAT_NATIVE_REWIND_FILES);
    assert_eq!(
        native_operation_recovery(&operation)["canFinishAcknowledged"],
        true
    );
    assert!(!native_operation_transition_allowed(
        "acknowledged",
        "executing"
    ));
    assert!(!native_operation_transition_allowed(
        "acknowledged",
        "prepared"
    ));
    operation.ack = None;
    let recovery = native_operation_recovery(&operation);
    assert_eq!(recovery["needsReconciliation"], true);
    assert_eq!(recovery["canFinishAcknowledged"], false);
    assert_eq!(recovery["canContinueFromCurrentFiles"], false);
}

#[test]
fn unknown_native_outcome_requires_the_kind_specific_explicit_fallback() {
    let conversation = native_operation_recovery(&operation("uncertain", AGENT_CHAT_NATIVE_REWIND));
    let files = native_operation_recovery(&operation("uncertain", AGENT_CHAT_NATIVE_REWIND_FILES));
    assert_eq!(conversation["canRestartFromTranscript"], true);
    assert_eq!(conversation["canContinueFromCurrentFiles"], false);
    assert_eq!(files["canRestartFromTranscript"], false);
    assert_eq!(files["canContinueFromCurrentFiles"], true);
    for recovery in [conversation, files] {
        assert_eq!(recovery["canCancelUnstarted"], false);
        assert_eq!(recovery["canFinishAcknowledged"], false);
    }
    assert!(native_operation_transition_allowed(
        "executing",
        "uncertain"
    ));
    assert!(native_operation_transition_allowed(
        "uncertain",
        "reconciled"
    ));
    for next in [
        "prepared",
        "executing",
        "acknowledged",
        "cancelled",
        "completed",
    ] {
        assert!(
            !native_operation_transition_allowed("uncertain", next),
            "blind retry or completion via {next}"
        );
    }
}

#[test]
fn only_known_terminal_states_release_the_chat_freeze() {
    for state in ["completed", "cancelled", "reconciled"] {
        let operation = operation(state, AGENT_CHAT_NATIVE_REWIND);
        assert!(!native_operation_freezes(&operation));
        assert_eq!(
            native_operation_recovery(&operation)["needsReconciliation"],
            false
        );
        assert!(!native_operation_transition_allowed(state, "executing"));
    }
    for state in [
        "prepared",
        "executing",
        "acknowledged",
        "uncertain",
        "futureState",
        "",
    ] {
        assert!(native_operation_freezes(&operation(
            state,
            AGENT_CHAT_NATIVE_REWIND
        )));
    }
}

#[test]
fn only_an_executing_operation_from_a_lost_process_is_marked_uncertain() {
    let executing = operation("executing", AGENT_CHAT_NATIVE_REWIND);
    assert!(native_operation_requires_restart_reconciliation(
        &executing,
        "new-process-epoch"
    ));
    assert!(!native_operation_requires_restart_reconciliation(
        &executing,
        &executing.process_epoch
    ));
    for state in [
        "prepared",
        "acknowledged",
        "uncertain",
        "completed",
        "cancelled",
        "reconciled",
    ] {
        assert!(
            !native_operation_requires_restart_reconciliation(
                &operation(state, AGENT_CHAT_NATIVE_REWIND),
                "new-process-epoch",
            ),
            "restart must preserve {state} without another native call"
        );
    }
}

async fn prepared_fixture() -> (TestHarness, ChatSession, AgentChatNativeOperation) {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    harness.runtime.shutdown().await;
    let deps = SessionDeps {
        store: harness.store.clone(),
        factory: harness.factory.clone(),
        hooks: Default::default(),
        sink: Arc::new(NullSink),
        tabs: Arc::new(harness.store.clone()),
        activity: Arc::new(ChatActivity::default()),
        instances: Arc::new(InstanceDirectory::default()),
        flush_delay: Duration::ZERO,
    };
    let mut session = ChatSession::load(&chat_id, deps).await.unwrap();
    let stamp = "2026-10-13T10:00:00.000Z";
    session.header.upsert_turn(
        serde_json::from_value::<ChatTurn>(json!({
            "turnId":"seed-turn","status":"completed","startedAt":stamp,"completedAt":stamp,
            "provider":"codex","providerInstanceId":"codex","generation":1,
        }))
        .unwrap(),
    );
    for (id, kind, text) in [
        ("seed-user", "user_message", "Original prompt"),
        ("seed-assistant", "assistant_message", "Settled answer"),
    ] {
        let mut item = ChatItem::new(id.into(), kind, stamp, 1);
        item.turn_id = Some("seed-turn".into());
        item.status = "completed".into();
        item.text = Some(text.into());
        session.insert_item(item);
    }
    session.flush().await.unwrap();
    harness
        .store
        .bind_agent_chat_native_thread(&chat_id, 1, Some("native-seed-source"))
        .await
        .unwrap();
    session.native_thread = Some("native-seed-source".into());
    session.process_epoch = "seed-process".into();
    harness
        .store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: chat_id.clone(),
            generation: 1,
            kind: "turn@seed-process".into(),
            native_id: json!("native-seed-turn"),
            app_id: Some("seed-turn".into()),
        })
        .await
        .unwrap();
    let input = AgentChatNativeOperationInput {
        operation_id: uuid::Uuid::new_v4().to_string(),
        chat_id,
        expected_cursor: session.committed.cursor,
        expected_generation: 1,
        expected_native_thread_id: "native-seed-source".into(),
        process_epoch: "seed-process".into(),
        kind: AGENT_CHAT_NATIVE_REWIND.into(),
        turn_id: "seed-turn".into(),
        boundary: json!({"type":"beforeTurn","value":"native-seed-turn"}),
        actor: "runtime".into(),
    };
    let receipt = AgentChatNativeOperationReceipt {
        caller_scope: "runtime".into(),
        verb: "agentChat.rewind".into(),
        request_id: uuid::Uuid::new_v4().to_string(),
        digest: "seed-digest".into(),
    };
    let AgentChatNativeOperationOutcome::Applied(operation) = harness
        .store
        .begin_agent_chat_native_operation(&input, &receipt)
        .await
        .unwrap()
    else {
        panic!("prepare failed");
    };
    (harness, session, *operation)
}

async fn transition(
    session: &mut ChatSession,
    operation: &AgentChatNativeOperation,
    state: &str,
    evidence: Value,
) -> AgentChatNativeOperation {
    let AgentChatNativeOperationOutcome::Applied(operation) = session
        .deps
        .store
        .transition_agent_chat_native_operation(
            &operation.chat_id,
            &operation.operation_id,
            operation.revision,
            state,
            Some(&evidence),
        )
        .await
        .unwrap()
    else {
        panic!("transition failed");
    };
    *operation
}

#[tokio::test]
async fn reload_keeps_prepared_cancellable_without_a_provider_spawn_or_cursor_step() {
    let (harness, session, prepared) = prepared_fixture().await;
    let mut reloaded = ChatSession::load(&prepared.chat_id, session.deps.clone())
        .await
        .unwrap();
    reloaded.load_native_history_recovery().await.unwrap();
    let status = reloaded
        .native_history_operation_status(None)
        .await
        .unwrap();
    assert_eq!(status["operation"]["state"], "prepared");
    assert_eq!(status["operation"]["recovery"]["canCancelUnstarted"], true);
    let current = harness
        .store
        .agent_chat_native_operation(&prepared.chat_id, &prepared.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.revision, prepared.revision);
    assert_eq!(
        harness
            .store
            .agent_chat(&prepared.chat_id)
            .await
            .unwrap()
            .unwrap()
            .cursor,
        prepared.base_cursor
    );
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn reload_marks_lost_execution_uncertain_once_and_never_retries_the_provider() {
    let (harness, mut session, prepared) = prepared_fixture().await;
    let executing = transition(
        &mut session,
        &prepared,
        "executing",
        json!({"processEpoch":prepared.process_epoch}),
    )
    .await;
    let mut reloaded = ChatSession::load(&executing.chat_id, session.deps.clone())
        .await
        .unwrap();
    reloaded.load_native_history_recovery().await.unwrap();
    let status = reloaded
        .native_history_operation_status(None)
        .await
        .unwrap();
    assert_eq!(status["operation"]["state"], "uncertain");
    assert_eq!(
        status["operation"]["recovery"]["canRestartFromTranscript"],
        true
    );
    assert_eq!(
        status["operation"]["recovery"]["canFinishAcknowledged"],
        false
    );
    let current = harness
        .store
        .agent_chat_native_operation(&executing.chat_id, &executing.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.revision, executing.revision + 1);
    reloaded.load_native_history_recovery().await.unwrap();
    let repeated = harness
        .store
        .agent_chat_native_operation(&executing.chat_id, &executing.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(repeated.revision, current.revision);
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(!status.to_string().contains("native-seed"));
    harness.finish().await;
}

#[tokio::test]
async fn reload_preserves_acknowledgment_for_explicit_finishing_without_native_io() {
    let (harness, mut session, prepared) = prepared_fixture().await;
    let executing = transition(
        &mut session,
        &prepared,
        "executing",
        json!({"processEpoch":prepared.process_epoch}),
    )
    .await;
    let acknowledged = transition(&mut session, &executing, "acknowledged", json!({
        "threadId":executing.native_thread_id,"nativeThreadId":"observed-after-rewind","boundary":executing.boundary,
    })).await;
    let mut reloaded = ChatSession::load(&acknowledged.chat_id, session.deps.clone())
        .await
        .unwrap();
    reloaded.load_native_history_recovery().await.unwrap();
    let status = reloaded
        .native_history_operation_status(Some(&acknowledged.operation_id))
        .await
        .unwrap();
    assert_eq!(status["operation"]["state"], "acknowledged");
    assert_eq!(
        status["operation"]["recovery"]["canFinishAcknowledged"],
        true
    );
    assert_eq!(
        status["operation"]["recovery"]["canRestartFromTranscript"],
        false
    );
    let current = harness
        .store
        .agent_chat_native_operation(&acknowledged.chat_id, &acknowledged.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.revision, acknowledged.revision);
    assert_eq!(current.ack, acknowledged.ack);
    assert!(!status.to_string().contains("observed-after-rewind"));
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}
