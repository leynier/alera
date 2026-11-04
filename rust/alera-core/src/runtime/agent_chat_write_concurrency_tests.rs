use std::future::Future;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::Duration;

use anyhow::Result;
use serde_json::json;
use tokio::sync::oneshot;

use super::agent_chat_test_support::*;
use super::*;

unsafe extern "C" {
    fn sqlite3_txn_state(database: *mut std::ffi::c_void, schema: *const std::ffi::c_char) -> i32;
    fn sqlite3_get_autocommit(database: *mut std::ffi::c_void) -> i32;
}

/// Stops SQLite after the transaction acquires a read snapshot or writer lock.
async fn pause_chat_transaction(
    store: &RuntimeStore,
) -> (oneshot::Receiver<()>, std::sync::mpsc::Sender<()>) {
    let (entered, receiver) = oneshot::channel();
    let entered = Arc::new(Mutex::new(Some(entered)));
    let (resume, resumed) = std::sync::mpsc::channel();
    let resumed = Arc::new(Mutex::new(resumed));
    let paused = Arc::new(AtomicBool::new(false));
    let mut connections = Vec::new();
    for _ in 0..store.pool().options().get_max_connections() {
        connections.push(store.pool().acquire().await.unwrap());
    }
    for connection in &mut connections {
        let entered = entered.clone();
        let resumed = resumed.clone();
        let paused = paused.clone();
        let mut handle = connection.lock_handle().await.unwrap();
        let database = handle.as_raw_handle().as_ptr() as usize;
        handle.set_progress_handler(1, move || {
            // SAFETY: The live handle belongs to this callback's SQLite worker;
            // these functions only inspect its connection state.
            let (state, explicit) = unsafe {
                (
                    sqlite3_txn_state(database as *mut _, std::ptr::null()),
                    sqlite3_get_autocommit(database as *mut _) == 0,
                )
            };
            if explicit && state != 0 && !paused.swap(true, Ordering::SeqCst) {
                entered.lock().unwrap().take().unwrap().send(()).unwrap();
                resumed
                    .lock()
                    .unwrap()
                    .recv_timeout(Duration::from_secs(5))
                    .unwrap();
            }
            true
        });
    }
    (receiver, resume)
}

async fn mutate_while_workspace_rename_competes<T: Send + 'static>(
    store: &RuntimeStore,
    competing: &RuntimeStore,
    mutation: impl Future<Output = Result<T>> + Send + 'static,
) -> T {
    let (entered, resume) = pause_chat_transaction(store).await;
    let task = tokio::spawn(mutation);
    tokio::time::timeout(Duration::from_secs(5), entered)
        .await
        .unwrap()
        .unwrap();
    let mut connection = competing.pool().acquire().await.unwrap();
    sqlx::query("PRAGMA busy_timeout = 0")
        .execute(&mut *connection)
        .await
        .unwrap();
    let rename = sqlx::query("UPDATE workspaces SET name = 'Concurrent Rename' WHERE id = 'ws'")
        .execute(&mut *connection)
        .await;
    resume.send(()).unwrap();
    let outcome = tokio::time::timeout(Duration::from_secs(5), task)
        .await
        .unwrap()
        .unwrap();
    let outcome = outcome.unwrap();
    let error = rename.expect_err("a chat mutation must own the writer lock before reading");
    assert_eq!(
        error.as_database_error().unwrap().code().as_deref(),
        Some("5")
    );
    sqlx::query("UPDATE workspaces SET name = 'Concurrent Rename' WHERE id = 'ws'")
        .execute(&mut *connection)
        .await
        .unwrap();
    outcome
}

#[tokio::test]
async fn commit_without_receipt_serializes_before_reading_the_chat() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["title"] = json!("Delegated Child");
    let delta =
        json!({"title": "Delegated Child", "items": [item("a", "assistant_message", "saved")]});
    let owned = store.clone();
    let id = chat_id.clone();
    let outcome = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned
            .commit_agent_chat(&id, cursor, &next, &delta, None)
            .await
    })
    .await;
    assert!(matches!(outcome, AgentChatCommitOutcome::Committed(_)));
    let stored = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(stored.cursor, 1);
    assert_eq!(stored.snapshot["title"], "Delegated Child");
    assert_eq!(stored.snapshot["items"][0]["text"], "saved");
    assert_eq!(
        store.find_workspace("ws").await.unwrap().unwrap().name,
        "Concurrent Rename"
    );
}

#[tokio::test]
async fn create_without_receipt_serializes_chat_and_tab_admission() {
    let (dir, store) = store_with_workspace("ws").await;
    create_chat(&store, "ws", "existing").await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let chat_id = new_chat_id();
    let record = record(
        &chat_id,
        "ws",
        "child",
        snapshot(&chat_id, "ws", "child", 0),
    );
    let tab = tab(&chat_id, "ws", "child");
    let owned = store.clone();
    let outcome = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned.create_agent_chat(&record, &tab, None).await
    })
    .await;
    assert!(matches!(outcome, AgentChatCreateOutcome::Created(_)));
    let child = store.agent_chat(&chat_id).await.unwrap().unwrap();
    let tab = store.find_workspace_tab("child").await.unwrap().unwrap();
    assert_eq!(tab.payload["chatId"], child.chat_id);
    assert_eq!(store.list_agent_chats("ws", false).await.unwrap().len(), 2);
}

#[tokio::test]
async fn archive_and_restore_without_receipt_serialize_before_reading() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let owned = store.clone();
    let id = chat_id.clone();
    let archived = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned.archive_agent_chat(&id).await
    })
    .await;
    assert!(archived.archived);
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
    let owned = store.clone();
    let id = chat_id.clone();
    let restored = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned
            .restore_agent_chat(&id, &tab(&id, "ws", "restored"))
            .await
    })
    .await;
    assert!(!restored.archived);
    assert_eq!(restored.tab_id, "restored");
    assert_eq!(
        store
            .agent_chat_for_tab("restored")
            .await
            .unwrap()
            .unwrap()
            .chat_id,
        chat_id
    );
}

#[tokio::test]
async fn native_id_mapping_serializes_before_reading_the_current_generation() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let owned = store.clone();
    let id = chat_id.clone();
    let mapped = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned
            .map_agent_chat_native_id(&AgentChatNativeIdInput {
                chat_id: id,
                generation: 1,
                kind: "turn".into(),
                native_id: json!("provider-turn"),
                app_id: None,
            })
            .await
    })
    .await;
    assert_eq!(
        store
            .agent_chat_app_id(&chat_id, 1, "turn", &json!("provider-turn"))
            .await
            .unwrap(),
        Some(mapped)
    );
}

#[tokio::test]
async fn startup_recovery_serializes_before_reading_live_chat_state() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let owned = store.clone();
    let recovered = mutate_while_workspace_rename_competes(&store, &competing, async move {
        owned.recover_agent_chats().await
    })
    .await;
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].chat_id, chat_id);
    assert_eq!(
        store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot["session"]["status"],
        "stopped"
    );
}

#[tokio::test]
async fn failed_chat_receipt_admission_leaves_no_chat_tab_items_or_receipt() {
    let (_dir, store) = store_with_workspace("ws").await;
    sqlx::query(
        "CREATE TRIGGER rejectChatReceipt BEFORE INSERT ON agentChatReceipts BEGIN \
         SELECT RAISE(ABORT, 'chat receipt admission failed'); END",
    )
    .execute(store.pool())
    .await
    .unwrap();
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "child", 0);
    initial["items"] = json!([item("initial", "user_message", "delegate this task")]);
    let receipt = AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: "failed-chat".into(),
        digest: "digest".into(),
        receipt: json!({"chatId": chat_id, "tabId": "child"}),
    };
    let error = store
        .create_agent_chat(
            &record(&chat_id, "ws", "child", initial),
            &tab(&chat_id, "ws", "child"),
            Some(&receipt),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("chat receipt admission failed"));
    assert!(store.agent_chat(&chat_id).await.unwrap().is_none());
    assert!(store.find_workspace_tab("child").await.unwrap().is_none());
    assert!(store
        .agent_chat_item(&chat_id, "initial")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .check_agent_chat_receipt("desktop", "failed-chat", "digest")
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert!(store
        .list_chat_orchestration_tasks(&ChatOrchestrationTaskFilter::default())
        .await
        .unwrap()
        .tasks
        .is_empty());
}

#[tokio::test]
async fn failed_task_receipt_admission_leaves_no_task_receipt_chat_or_tab() {
    let (_dir, store) = store_with_workspace("ws").await;
    sqlx::query(
        "CREATE TRIGGER rejectTaskReceipt BEFORE INSERT ON chatOrchestrationReceipts BEGIN \
         SELECT RAISE(ABORT, 'task receipt admission failed'); END",
    )
    .execute(store.pool())
    .await
    .unwrap();
    let task = NewChatOrchestrationTask {
        task_id: "failed-task".into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: None,
        parent_chat_id: None,
        child_chat_id: None,
        project_id: Some("project".into()),
        workspace_id: Some("ws".into()),
        host_id: Some("local".into()),
        target: ChatOrchestrationTarget::Workspace {
            workspace_id: "ws".into(),
        },
        title: None,
        role: None,
        brief: "delegate this task".into(),
        notify: ChatOrchestrationNotify::Always,
        launch_options: None,
    };
    let receipt = ChatOrchestrationReceipt {
        scope: "desktop".into(),
        verb: "delegate".into(),
        request_id: "failed-task".into(),
        digest: "digest".into(),
        response: json!({"taskId": "failed-task", "status": "preparing"}),
    };
    let error = store
        .create_chat_orchestration_task(task, Some(&receipt))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("task receipt admission failed"));
    assert!(store
        .chat_orchestration_task("failed-task")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .check_chat_orchestration_receipt("desktop", "delegate", "failed-task", "digest")
            .await
            .unwrap(),
        ChatOrchestrationReceiptCheck::New
    );
    assert!(store.list_agent_chats("ws", true).await.unwrap().is_empty());
    assert!(store.list_workspace_tabs("ws").await.unwrap().is_empty());
}
