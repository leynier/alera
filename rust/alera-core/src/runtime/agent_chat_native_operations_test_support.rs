use serde_json::{json, Value};

use crate::runtime::agent_chat_test_support::*;
use crate::runtime::*;

pub(super) async fn fixture() -> (tempfile::TempDir, RuntimeStore, String) {
    let (dir, store) = store_with_workspace("ws").await;
    let id = seed(&store, "tab").await;
    (dir, store, id)
}

pub(super) async fn seed(store: &RuntimeStore, tab_id: &str) -> String {
    let id = new_chat_id();
    let mut initial = snapshot(&id, "ws", tab_id, 0);
    let mut turns = Vec::new();
    let mut items = Vec::new();
    for index in 0..3 {
        let turn = format!("turn-{index}");
        turns.push(json!({"turnId":turn,"status":"completed","generation":1}));
        let mut user = item(
            &format!("user-{index}"),
            "user_message",
            &format!("prompt {index}"),
        );
        user["turnId"] = json!(turn);
        user["clientMessageId"] = json!(format!("client-{index}"));
        user["attachments"] = json!([{"name":"image.png","path":"/tmp/image.png"}]);
        let mut answer = item(&format!("answer-{index}"), "assistant_message", "answer");
        answer["turnId"] = json!(turn);
        items.push(user);
        items.push(answer);
    }
    initial["turns"] = json!(turns);
    initial["items"] = json!(items);
    store
        .create_agent_chat(
            &record(&id, "ws", tab_id, initial),
            &tab(&id, "ws", tab_id),
            None,
        )
        .await
        .unwrap();
    for index in 0..3 {
        for (kind, native, app) in [
            (
                "turn@epoch",
                format!("native-turn-{index}"),
                format!("turn-{index}"),
            ),
            (
                "userTurn@epoch",
                format!("native-user-{index}"),
                format!("turn-{index}"),
            ),
            (
                "userMessage@epoch",
                format!("native-user-{index}"),
                format!("user-{index}"),
            ),
        ] {
            store
                .map_agent_chat_native_id(&AgentChatNativeIdInput {
                    chat_id: id.clone(),
                    generation: 1,
                    kind: kind.into(),
                    native_id: json!(native),
                    app_id: Some(app),
                })
                .await
                .unwrap();
        }
    }
    id
}

pub(super) fn input(chat: &str, id: &str, files: bool) -> AgentChatNativeOperationInput {
    AgentChatNativeOperationInput {
        operation_id: id.into(),
        chat_id: chat.into(),
        expected_cursor: 0,
        expected_generation: 1,
        expected_native_thread_id: "native-thread".into(),
        process_epoch: "epoch".into(),
        kind: if files {
            AGENT_CHAT_NATIVE_REWIND_FILES
        } else {
            AGENT_CHAT_NATIVE_REWIND
        }
        .into(),
        turn_id: "turn-1".into(),
        actor: "human".into(),
        boundary: if files {
            json!({"type":"message","id":"native-user-1"})
        } else {
            json!({"type":"beforeTurn","value":"native-turn-1"})
        },
    }
}

pub(super) fn receipt(id: &str) -> AgentChatNativeOperationReceipt {
    AgentChatNativeOperationReceipt {
        caller_scope: "desktop".into(),
        verb: "agentChat.nativeRewind".into(),
        request_id: id.into(),
        digest: id.into(),
    }
}

pub(super) fn reconcile(id: &str) -> AgentChatReceipt {
    AgentChatReceipt {
        caller_scope: json!(["desktop", "agentChat.nativeHistory.reconcile"]).to_string(),
        request_id: id.into(),
        digest: id.into(),
        receipt: Value::Null,
    }
}

pub(super) fn applied(result: AgentChatNativeOperationOutcome) -> AgentChatNativeOperation {
    let AgentChatNativeOperationOutcome::Applied(op) = result else {
        panic!("expected a native operation state write");
    };
    *op
}

pub(super) async fn begin(
    store: &RuntimeStore,
    chat: &str,
    id: &str,
    files: bool,
) -> AgentChatNativeOperation {
    applied(
        store
            .begin_agent_chat_native_operation(&input(chat, id, files), &receipt(id))
            .await
            .unwrap(),
    )
}

pub(super) async fn advance(
    store: &RuntimeStore,
    op: &AgentChatNativeOperation,
    state: &str,
    evidence: Option<&Value>,
) -> AgentChatNativeOperation {
    applied(
        store
            .transition_agent_chat_native_operation(
                &op.chat_id,
                &op.operation_id,
                op.revision,
                state,
                evidence,
            )
            .await
            .unwrap(),
    )
}

pub(super) async fn acknowledge(
    store: &RuntimeStore,
    op: &AgentChatNativeOperation,
) -> AgentChatNativeOperation {
    let executing = advance(store, op, "executing", None).await;
    let ack = if op.kind == AGENT_CHAT_NATIVE_REWIND {
        json!({"threadId":"native-thread","nativeThreadId":"native-thread","boundary":op.boundary})
    } else {
        json!({"threadId":"native-thread","nativeThreadId":"native-thread","nativeUserMessageId":"native-user-1"})
    };
    advance(store, &executing, "acknowledged", Some(&ack)).await
}

pub(super) async fn stopped_snapshot(store: &RuntimeStore, chat: &str) -> Value {
    let (_, mut snapshot) = next_snapshot(store, chat).await;
    snapshot["session"]["status"] = json!("stopped");
    snapshot["turns"] = json!([]);
    snapshot.as_object_mut().unwrap().remove("recovery");
    snapshot.as_object_mut().unwrap().remove("usage");
    snapshot
}
