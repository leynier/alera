use std::sync::Arc;
use std::time::Duration;

use super::super::events::NullSink;
use super::super::session::SessionDeps;
use super::super::wire::{ChatItem, ChatTurn};
use super::super::{AgentChatRuntime, ChatActivity, CreateChatInput, InstanceDirectory};
use super::*;
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderFactory;
use crate::terminal_host::server::checkout_buffer_guards_tests;
use alera_core::runtime::{AgentChatNativeIdInput, AgentChatReceiptCheck};
use alera_provider_protocol::*;
use async_trait::async_trait;

const TIMESTAMP: &str = "2026-10-13T10:00:00.000Z";

struct NativeBoundaryProvider;

#[async_trait]
impl Provider for NativeBoundaryProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Codex
    }
    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities::default()
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        NativeHistoryCapabilities {
            fork_at_turn: true,
            ..Default::default()
        }
    }
    fn session(&self) -> Option<&ProviderSession> {
        None
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn start_session(
        &mut self,
        _: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        Err(ProviderError::Unsupported(
            "test has no native launch".into(),
        ))
    }
    async fn send_turn(&mut self, _: TurnInput) -> Result<TurnStartResult, ProviderError> {
        Err(ProviderError::Unsupported("test has no inference".into()))
    }
    async fn interrupt(&mut self, _: InterruptInput) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn respond(&mut self, _: RuntimeResponse) -> Result<(), ProviderError> {
        Ok(())
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        Ok(None)
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
}

async fn fixture() -> (tempfile::TempDir, ChatSession, Arc<MockProviderFactory>) {
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
    let session = ChatSession::load(
        created["chatId"].as_str().unwrap(),
        SessionDeps {
            store: store.clone(),
            factory: factory.clone(),
            hooks: Default::default(),
            sink: Arc::new(NullSink),
            tabs: Arc::new(store),
            activity: Arc::new(ChatActivity::default()),
            instances,
            flush_delay: Duration::ZERO,
        },
    )
    .await
    .unwrap();
    (root, session, factory)
}

async fn add_turn(session: &mut ChatSession, id: &str, text: &str) {
    session.header.upsert_turn(
        serde_json::from_value::<ChatTurn>(json!({
            "turnId": id, "status": "completed", "startedAt": TIMESTAMP, "completedAt": TIMESTAMP,
            "provider": "codex", "providerInstanceId": "codex", "generation": 1,
        }))
        .unwrap(),
    );
    let mut prompt = ChatItem::new(format!("user-{id}"), "user_message", TIMESTAMP, 1);
    prompt.turn_id = Some(id.into());
    prompt.status = "completed".into();
    prompt.text = Some(text.into());
    prompt.client_message_id = Some(format!("message-{id}"));
    prompt.attachments = Some(vec![json!({"type": "image", "path": "/host/image.png"})]);
    session.insert_item(prompt);
    let mut response = ChatItem::new(format!("assistant-{id}"), "assistant_message", TIMESTAMP, 1);
    response.turn_id = Some(id.into());
    response.status = "completed".into();
    response.text = Some(format!("Answer {id}"));
    session.insert_item(response);
    session.flush().await.unwrap();
}

fn key(verb: &str) -> ReceiptKey {
    ReceiptKey {
        verb: verb.into(),
        request_id: format!("request-{verb}"),
        digest: "digest".into(),
    }
}

#[tokio::test]
async fn transcript_fork_copies_a_settled_prefix_without_launching_or_changing_source() {
    let (_root, mut session, factory) = fixture().await;
    add_turn(&mut session, "a", "first").await;
    add_turn(&mut session, "b", "second").await;
    let cursor = session.committed.cursor;
    let receipt = key("agentChat.fork");
    let fork_id = uuid::Uuid::new_v4().to_string();
    let response = session
        .fork_history(
            "a",
            &fork_id,
            "tab-fork-one",
            None,
            &CallerCtx::runtime(),
            Some(&receipt),
        )
        .await
        .unwrap();
    assert_eq!(response["operationKind"], "transcriptFork");
    assert_eq!(response["filesystemChangesReverted"], false);
    assert_eq!(response["snapshot"]["session"]["status"], "stopped");
    assert!(factory.launches.lock().unwrap().is_empty());
    assert_eq!(session.committed.cursor, cursor);
    let record = session
        .deps
        .store
        .agent_chat(&fork_id)
        .await
        .unwrap()
        .unwrap();
    assert!(record.native_thread_id.is_none());
    assert_eq!(record.generation, 1);
    let items = record.snapshot["items"].as_array().unwrap();
    assert_eq!(items.len(), 2);
    assert!(items.iter().all(|item| item["turnId"] == "a"));
    assert!(record.snapshot.get("lineage").is_none());
    let unused_id = uuid::Uuid::new_v4().to_string();
    let replay = session
        .fork_history(
            "a",
            &unused_id,
            "unused-tab",
            None,
            &CallerCtx::runtime(),
            Some(&receipt),
        )
        .await
        .unwrap();
    assert_eq!(replay, response);
    assert!(session
        .deps
        .store
        .agent_chat(&unused_id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn rewind_returns_original_prompt_resets_native_identity_and_preserves_workspace_files() {
    let (root, mut session, _factory) = fixture().await;
    add_turn(&mut session, "a", "first").await;
    add_turn(&mut session, "b", "second").await;
    add_turn(&mut session, "c", "third").await;
    let witness = root.path().join("rewind-witness.txt");
    std::fs::write(&witness, "changes stay here").unwrap();
    session
        .deps
        .store
        .bind_agent_chat_native_thread(&session.header.chat_id, 1, Some("native-source"))
        .await
        .unwrap();
    session.native_thread = Some("native-source".into());
    let mut metadata = json!({"nativeFork": {"sourceNativeThreadId": "old-source"}});
    session
        .deps
        .store
        .set_agent_chat_metadata(&session.header.chat_id, Some(&metadata))
        .await
        .unwrap();
    let receipt = key("agentChat.rewind");
    let cursor = session.committed.cursor;
    let response = session
        .rewind_history("b", &CallerCtx::runtime(), Some(&receipt))
        .await
        .unwrap();
    assert_eq!(response["operationKind"], "transcriptRewind");
    assert_eq!(response["filesystemChangesReverted"], false);
    assert_eq!(response["nativeRollback"], false);
    assert_eq!(response["prompt"], "second");
    assert_eq!(response["attachments"][0]["path"], "/host/image.png");
    assert_eq!(response["event"]["cursor"], cursor + 1);
    assert_eq!(response["event"]["delta"]["snapshotRequired"], true);
    assert!(session.native_thread.is_none());
    assert_eq!(session.generation, 2);
    assert!(session.handoff_pending);
    assert!(session.items.is_empty());
    assert_eq!(
        std::fs::read_to_string(witness).unwrap(),
        "changes stay here"
    );
    let record = session
        .deps
        .store
        .agent_chat(&session.header.chat_id)
        .await
        .unwrap()
        .unwrap();
    metadata = record.metadata.unwrap();
    assert!(metadata.get("nativeFork").is_none());
    assert_eq!(record.snapshot["items"].as_array().unwrap().len(), 2);
    assert!(session
        .deps
        .store
        .is_agent_chat_message_cancelled(&session.header.chat_id, "message-b")
        .await
        .unwrap());
    assert!(session
        .deps
        .store
        .is_agent_chat_message_cancelled(&session.header.chat_id, "message-c")
        .await
        .unwrap());
    let saved = session
        .deps
        .store
        .check_agent_chat_receipt(
            &receipt_scope("runtime", &receipt.verb),
            &receipt.request_id,
            &receipt.digest,
        )
        .await
        .unwrap();
    assert_eq!(saved, AgentChatReceiptCheck::Replay(response));
}

#[tokio::test]
async fn rewind_refuses_to_discard_additional_steering_messages() {
    let (_root, mut session, _) = fixture().await;
    add_turn(&mut session, "a", "original").await;
    let mut steer = ChatItem::new("steer".into(), "user_message", TIMESTAMP, 1);
    steer.turn_id = Some("a".into());
    steer.status = "completed".into();
    steer.text = Some("keep this instruction".into());
    session.insert_item(steer);
    session.flush().await.unwrap();
    let cursor = session.committed.cursor;
    assert!(session
        .rewind_history("a", &CallerCtx::runtime(), None)
        .await
        .is_err());
    let record = session
        .deps
        .store
        .agent_chat(&session.header.chat_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(record.cursor, cursor);
    assert_eq!(record.snapshot["items"].as_array().unwrap().len(), 3);
}

#[tokio::test]
async fn archived_delete_keeps_a_detached_receipt_and_refuses_an_open_chat() {
    let (_root, mut session, _) = fixture().await;
    add_turn(&mut session, "a", "preserve before deletion").await;
    assert!(session
        .delete_history(&CallerCtx::runtime(), None)
        .await
        .is_err());
    session.header.archived = true;
    session.flush().await.unwrap();
    session
        .deps
        .store
        .archive_agent_chat(&session.header.chat_id)
        .await
        .unwrap();
    let receipt = key("agentChat.delete");
    let response = session
        .delete_history(&CallerCtx::runtime(), Some(&receipt))
        .await
        .unwrap();
    assert_eq!(response["deleted"], true);
    assert!(session.closed);
    assert!(session
        .deps
        .store
        .agent_chat(&session.header.chat_id)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        session
            .deps
            .store
            .check_agent_chat_receipt(
                &receipt_scope("runtime", &receipt.verb),
                &receipt.request_id,
                &receipt.digest,
            )
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(response)
    );
}

#[tokio::test]
async fn native_boundary_lookup_is_current_generation_and_epoch_independent() {
    let (_root, mut session, _) = fixture().await;
    add_turn(&mut session, "a", "first").await;
    session
        .deps
        .store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: session.header.chat_id.clone(),
            generation: 1,
            kind: "turn@old-process".into(),
            native_id: json!("native-a"),
            app_id: Some("a".into()),
        })
        .await
        .unwrap();
    let mapped = session
        .deps
        .store
        .agent_chat_native_id_for_app(&session.header.chat_id, 1, "turn", "a")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(mapped.native_id, "native-a");
    session
        .rewind_history("a", &CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert!(session
        .deps
        .store
        .agent_chat_native_id_for_app(&session.header.chat_id, 2, "turn", "a",)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn native_fork_preparation_requires_verified_caps_and_hides_the_exact_boundary() {
    let (_root, mut session, factory) = fixture().await;
    add_turn(&mut session, "a", "first").await;
    session
        .deps
        .store
        .bind_agent_chat_native_thread(&session.header.chat_id, 1, Some("private-thread"))
        .await
        .unwrap();
    session.native_thread = Some("private-thread".into());
    session
        .deps
        .store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: session.header.chat_id.clone(),
            generation: 1,
            kind: "turn@prior-epoch".into(),
            native_id: json!("private-turn"),
            app_id: Some("a".into()),
        })
        .await
        .unwrap();
    session.provider = Some(Box::new(NativeBoundaryProvider));
    let native_fork_id = uuid::Uuid::new_v4().to_string();
    let native = session
        .fork_history(
            "a",
            &native_fork_id,
            "native-tab",
            None,
            &CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(native["operationKind"], "nativeForkDeferred");
    assert!(!native.to_string().contains("private-thread"));
    assert!(!native.to_string().contains("private-turn"));
    let record = session
        .deps
        .store
        .agent_chat(&native_fork_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        record.metadata.unwrap()["nativeFork"]["boundary"],
        json!({"type":"turn", "id":"private-turn"})
    );
    assert!(factory.launches.lock().unwrap().is_empty());
    session.provider = None;
    let transcript_fork_id = uuid::Uuid::new_v4().to_string();
    let fallback = session
        .fork_history(
            "a",
            &transcript_fork_id,
            "transcript-tab",
            None,
            &CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(fallback["operationKind"], "transcriptFork");
}
