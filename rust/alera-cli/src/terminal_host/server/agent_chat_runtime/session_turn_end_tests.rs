use std::sync::Arc;
use std::time::Duration;

use alera_provider_protocol::{EventKind, FailureClass, ProviderEvent, ProviderKind};
use serde_json::{json, Value};

use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderFactory;
use crate::terminal_host::server::checkout_buffer_guards_tests;

use super::super::commands::CallerCtx;
use super::super::events::NullSink;
use super::super::session::{ChatSession, SessionDeps};
use super::super::wire::ChatTurn;
use super::super::{AgentChatRuntime, ChatActivity, CreateChatInput, InstanceDirectory};

const TIMESTAMP: &str = "2026-10-25T10:00:00.000Z";

async fn session_fixture() -> (tempfile::TempDir, ChatSession) {
    let (root, actor) = checkout_buffer_guards_tests::fixture().await;
    let store = actor.runtime_store.clone();
    let factory = Arc::new(MockProviderFactory::default());
    let instances = Arc::new(InstanceDirectory::default());
    let runtime = AgentChatRuntime::new(
        store.clone(),
        factory.clone(),
        Arc::new(store.clone()),
        Box::new(NullSink),
        instances.clone(),
    );
    let created = runtime
        .create(
            CreateChatInput {
                workspace_id: "task".into(),
                provider_instance_id: Some("codex".into()),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    runtime.shutdown().await;
    let deps = SessionDeps {
        store: store.clone(),
        factory,
        hooks: Default::default(),
        sink: Arc::new(NullSink),
        tabs: Arc::new(store),
        activity: Arc::new(ChatActivity::default()),
        instances,
        flush_delay: Duration::ZERO,
    };
    let session = ChatSession::load(created["chatId"].as_str().unwrap(), deps)
        .await
        .unwrap();
    (root, session)
}

fn start_turn(session: &mut ChatSession, id: &str) {
    let turn: ChatTurn = serde_json::from_value(json!({
        "turnId": id, "status": "running", "startedAt": TIMESTAMP,
        "provider": "codex", "providerInstanceId": "codex", "generation": 1,
    }))
    .unwrap();
    session.header.upsert_turn(turn);
    session.header.session.active_turn_id = Some(id.into());
}

fn event(session: &ChatSession, kind: EventKind, payload: Value) -> ProviderEvent {
    ProviderEvent::new(
        ProviderKind::Codex,
        "codex",
        session.header.chat_id.clone(),
        kind,
        payload,
        None,
    )
}

#[tokio::test]
async fn a_failed_turn_keeps_the_provider_text_and_its_failure_class() {
    let (_root, mut session) = session_fixture().await;
    start_turn(&mut session, "turn-1");
    let failed = event(
        &session,
        EventKind::TurnCompleted,
        json!({
            "state": "failed",
            "errorMessage": "You've hit your usage limit.",
            "failureClass": "usage_limit",
        }),
    );
    session.apply_provider_event(failed).await;
    let turn = session.header.turn_mut("turn-1").unwrap().clone();
    assert_eq!(turn.status, "failed");
    assert_eq!(
        turn.error_message.as_deref(),
        Some("You've hit your usage limit.")
    );
    assert_eq!(turn.failure_class, Some(FailureClass::UsageLimit));
    assert_eq!(
        serde_json::to_value(&turn).unwrap()["failureClass"],
        "usage_limit"
    );
    assert_eq!(
        session.header.session.error_message.as_deref(),
        Some("You've hit your usage limit.")
    );
}

#[tokio::test]
async fn an_unclassified_or_completed_turn_records_no_failure_class() {
    let (_root, mut session) = session_fixture().await;
    start_turn(&mut session, "turn-1");
    let failed = event(
        &session,
        EventKind::TurnCompleted,
        json!({ "state": "failed", "errorMessage": "boom", "failureClass": "unknown" }),
    );
    session.apply_provider_event(failed).await;
    let turn = session.header.turn_mut("turn-1").unwrap().clone();
    assert_eq!(turn.failure_class, None);
    assert!(serde_json::to_value(&turn)
        .unwrap()
        .get("failureClass")
        .is_none());

    start_turn(&mut session, "turn-2");
    let completed = event(
        &session,
        EventKind::TurnCompleted,
        json!({ "state": "completed" }),
    );
    session.apply_provider_event(completed).await;
    assert_eq!(
        session.header.turn_mut("turn-2").unwrap().failure_class,
        None
    );
}
