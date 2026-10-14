use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use serde_json::{json, Value};

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderFactory;
use crate::terminal_host::server::{checkout_buffer_guards_tests, ClientState};

use super::super::commands::CallerCtx;
use super::super::events::{ChatEventSink, ChatRuntimeEvent, NullSink};
use super::super::session::{ChatSession, SessionDeps};
use super::super::wire::ChatItem;
use super::super::{AgentChatRuntime, ChatActivity, CreateChatInput, InstanceDirectory};

#[derive(Default)]
struct CapturedCommits(Mutex<Vec<ChatRuntimeEvent>>);

#[async_trait]
impl ChatEventSink for CapturedCommits {
    async fn emit(&self, event: ChatRuntimeEvent) {
        self.0.lock().unwrap().push(event);
    }
    fn activity_changed(&self) {}
}

#[tokio::test]
async fn host_flush_persists_hidden_payload_rows_and_broadcasts_every_cursor_without_them() {
    let (_root, mut actor) = checkout_buffer_guards_tests::fixture().await;
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
    let chat_id = created["chatId"].as_str().unwrap();
    runtime.shutdown().await;
    let sink = Arc::new(CapturedCommits::default());
    let deps = SessionDeps {
        store: store.clone(),
        factory,
        hooks: Default::default(),
        sink: sink.clone(),
        tabs: Arc::new(store.clone()),
        activity: Arc::new(ChatActivity::default()),
        instances,
        flush_delay: Duration::ZERO,
    };
    let mut session = ChatSession::load(chat_id, deps.clone()).await.unwrap();
    let mut head = ChatItem::new(
        "head".into(),
        "mcp_tool_call",
        "2026-10-12T10:00:00.000Z",
        1,
    );
    head.status = "completed".into();
    head.streaming = false;
    session.insert_item(head);
    let retained = json!({"result": "x".repeat(620 * 1024)}).to_string();
    session
        .set_item_payload("head", Some(&retained))
        .await
        .unwrap();
    session.flush().await.unwrap();
    let page = store
        .agent_chat_payload(chat_id, "head", 0, 200)
        .await
        .unwrap();
    assert!(page.segment_count >= 3);
    let mut loaded = page
        .chunks
        .iter()
        .map(|chunk| chunk.text.as_str())
        .collect::<String>();
    let mut next = page.next_index;
    while let Some(index) = next {
        let tail = store
            .agent_chat_payload(chat_id, "head", index, 200)
            .await
            .unwrap();
        assert_eq!(tail.revision, page.revision);
        loaded.extend(tail.chunks.iter().map(|chunk| chunk.text.as_str()));
        next = tail.next_index;
    }
    assert_eq!(loaded, retained);
    let (handle, mut received) = ClientHandle::test_channels();
    actor.clients.clear();
    actor.clients.insert(99, ClientState::local(handle, true));
    let events = std::mem::take(&mut *sink.0.lock().unwrap());
    let mut hidden_commits = 0;
    let mut previous = None;
    for event in events {
        let ChatRuntimeEvent::Changed { cursor, delta, .. } = &event else {
            continue;
        };
        let cursor = *cursor;
        if let Some(previous) = previous {
            assert_eq!(cursor, previous + 1);
        }
        previous = Some(cursor);
        let hidden_only = delta
            .get("items")
            .and_then(Value::as_array)
            .is_some_and(|items| items.iter().all(|item| item["type"] == "payload"));
        if hidden_only {
            hidden_commits += 1;
        }
        actor.handle_agent_chat_runtime_event(event);
        let wire = received.try_recv().unwrap().as_json().unwrap();
        assert_eq!(wire["event"], "agentChatChanged");
        assert_eq!(wire["payload"]["cursor"], cursor);
        let public = &wire["payload"]["delta"];
        assert!(!public
            .get("items")
            .and_then(Value::as_array)
            .is_some_and(|items| items
                .iter()
                .any(|item| item["type"] == "payload" && item["normalized"]["hidden"] == true)));
        if hidden_only {
            assert_eq!(public, &json!({}));
        }
    }
    assert!(hidden_commits >= 3);
    assert!(received.try_recv().is_err());

    // Reloading does not hydrate hidden rows, so cleanup must query durability.
    let mut reloaded = ChatSession::load(chat_id, deps).await.unwrap();
    assert!(reloaded
        .items
        .values()
        .all(|item| item.item_type != "payload"));
    let stored_head: ChatItem = serde_json::from_value(
        store
            .agent_chat_item(chat_id, "head")
            .await
            .unwrap()
            .unwrap(),
    )
    .unwrap();
    reloaded.items.insert("head".into(), stored_head);
    let smaller = json!({"result": "smaller"}).to_string();
    reloaded
        .set_item_payload("head", Some(&smaller))
        .await
        .unwrap();
    reloaded.flush().await.unwrap();
    assert_eq!(
        store
            .agent_chat_payload_item_ids(chat_id, "head")
            .await
            .unwrap(),
        ["head:payload:1"]
    );
    assert_eq!(
        store
            .agent_chat_payload(chat_id, "head", 0, 200)
            .await
            .unwrap()
            .chunks[0]
            .text,
        smaller
    );
    assert!(store
        .agent_chat_item(chat_id, "head:payload:2")
        .await
        .unwrap()
        .is_none());
}
