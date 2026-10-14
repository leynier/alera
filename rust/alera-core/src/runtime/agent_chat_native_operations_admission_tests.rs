use serde_json::{json, Value};

use super::test_support::*;
use crate::runtime::*;

fn task(id: &str) -> NewChatOrchestrationTask {
    NewChatOrchestrationTask {
        task_id: id.into(),
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
        brief: "prepare the delegated task".into(),
        notify: ChatOrchestrationNotify::Never,
        launch_options: None,
    }
}

fn task_receipt(id: &str) -> ChatOrchestrationReceipt {
    ChatOrchestrationReceipt {
        scope: "desktop".into(),
        verb: "agentChat.delegate".into(),
        request_id: id.into(),
        digest: id.into(),
        response: json!({"taskId":id}),
    }
}

fn assert_pending_conflict(error: anyhow::Error) {
    assert_eq!(
        error.downcast_ref::<ChatOrchestrationStoreError>(),
        Some(&ChatOrchestrationStoreError::Conflict(
            "native operation pending; reconcile it before creating linked tasks".into()
        ))
    );
}

async fn settle(store: &RuntimeStore, id: &str) {
    let transition = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Interrupted,
    );
    assert!(matches!(
        store
            .transition_chat_orchestration_task(id, &transition)
            .await
            .unwrap(),
        ChatOrchestrationTransitionOutcome::Applied { .. }
    ));
}

#[tokio::test]
async fn uncertain_native_operation_blocks_direct_parent_child_and_target_admission_atomically() {
    let (_dir, store, chat) = fixture().await;
    let op = advance(
        &store,
        &begin(&store, &chat, "one", false).await,
        "executing",
        None,
    )
    .await;
    advance(
        &store,
        &op,
        "uncertain",
        Some(&json!({"reason":"providerError"})),
    )
    .await;
    let tabs = store.list_workspace_tabs("ws").await.unwrap();
    for linkage in ["parent", "child", "target"] {
        let mut value = task(linkage);
        match linkage {
            "parent" => value.parent_chat_id = Some(chat.clone()),
            "child" => value.child_chat_id = Some(chat.clone()),
            _ => {
                value.target = ChatOrchestrationTarget::Chat {
                    chat_id: chat.clone(),
                }
            }
        }
        let receipt = task_receipt(linkage);
        assert_pending_conflict(
            store
                .create_chat_orchestration_task(value, Some(&receipt))
                .await
                .unwrap_err(),
        );
        assert!(store
            .chat_orchestration_task(linkage)
            .await
            .unwrap()
            .is_none());
        assert_eq!(
            store
                .check_chat_orchestration_receipt(
                    &receipt.scope,
                    &receipt.verb,
                    &receipt.request_id,
                    &receipt.digest
                )
                .await
                .unwrap(),
            ChatOrchestrationReceiptCheck::New
        );
    }
    assert_eq!(store.list_workspace_tabs("ws").await.unwrap(), tabs);
    let task_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM chatOrchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    let workspace_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workspaces")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(task_count, 0);
    assert_eq!(workspace_count, 1);
}

#[tokio::test]
async fn native_freeze_blocks_inherited_root_and_parent_task_child_even_without_direct_parent() {
    for linkage in ["root", "ancestor-child"] {
        let (_dir, store, chat) = fixture().await;
        let mut ancestor = task("ancestor");
        if linkage == "root" {
            ancestor.parent_chat_id = Some(chat.clone());
        } else {
            ancestor.child_chat_id = Some(chat.clone());
        }
        store
            .create_chat_orchestration_task(ancestor, None)
            .await
            .unwrap();
        settle(&store, "ancestor").await;
        begin(&store, &chat, "one", false).await;
        let mut nested = task("nested");
        nested.parent_task_id = Some("ancestor".into());
        assert_pending_conflict(
            store
                .create_chat_orchestration_task(nested, None)
                .await
                .unwrap_err(),
        );
        assert!(store
            .chat_orchestration_task("nested")
            .await
            .unwrap()
            .is_none());
    }
}

#[tokio::test]
async fn competing_native_intent_and_linked_task_admission_have_only_one_winner() {
    let (dir, store, chat) = fixture().await;
    let competing = RuntimeStore::open(dir.path()).await.unwrap();
    let mut linked = task("linked");
    linked.parent_chat_id = Some(chat.clone());
    let intent = input(&chat, "one", false);
    let native_receipt = receipt("one");
    let (native, admission) = tokio::join!(
        store.begin_agent_chat_native_operation(&intent, &native_receipt),
        competing.create_chat_orchestration_task(linked, None),
    );
    match native.unwrap() {
        AgentChatNativeOperationOutcome::Applied(_) => {
            assert_pending_conflict(admission.unwrap_err());
            assert!(store
                .chat_orchestration_task("linked")
                .await
                .unwrap()
                .is_none());
        }
        AgentChatNativeOperationOutcome::Busy { .. } => {
            assert!(matches!(
                admission.unwrap(),
                ChatOrchestrationCreateOutcome::Created(_)
            ));
            assert!(store
                .pending_agent_chat_native_operation(&chat)
                .await
                .unwrap()
                .is_none());
        }
        other => panic!("unexpected competing native admission: {other:?}"),
    }
}

#[tokio::test]
async fn existing_task_receipt_replays_during_freeze_without_creating_new_task() {
    let (_dir, store, chat) = fixture().await;
    let mut linked = task("linked");
    linked.parent_chat_id = Some(chat.clone());
    let receipt = task_receipt("linked");
    store
        .create_chat_orchestration_task(linked.clone(), Some(&receipt))
        .await
        .unwrap();
    settle(&store, "linked").await;
    begin(&store, &chat, "one", false).await;
    assert_eq!(
        store
            .create_chat_orchestration_task(linked, Some(&receipt))
            .await
            .unwrap(),
        ChatOrchestrationCreateOutcome::Replay(receipt.response)
    );
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM chatOrchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 1);
}

#[tokio::test]
async fn unknown_native_kind_rejects_mutations_and_recovery_keeps_its_chat_frozen() {
    let (_dir, store, chat) = fixture().await;
    begin(&store, &chat, "one", false).await;
    for (state, next_state) in [
        ("prepared", "cancelled"),
        ("executing", "uncertain"),
        ("acknowledged", "executing"),
        ("uncertain", "cancelled"),
    ] {
        sqlx::query("UPDATE agentChatNativeOperations SET kind = 'future-kind', state = ? WHERE operationId = 'one'").bind(state).execute(store.pool()).await.unwrap();
        let before = store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap();
        let error = store
            .transition_agent_chat_native_operation(&chat, "one", before.revision, next_state, None)
            .await
            .unwrap_err();
        assert!(error
            .to_string()
            .contains("unsupported native operation kind"));
        for result in [
            store
                .complete_agent_chat_native_rewind(
                    &chat,
                    "one",
                    before.revision,
                    0,
                    &json!({}),
                    None,
                )
                .await,
            store
                .complete_agent_chat_native_files(
                    &chat,
                    "one",
                    before.revision,
                    0,
                    &json!({}),
                    None,
                )
                .await,
        ] {
            assert!(result
                .unwrap_err()
                .to_string()
                .contains("unsupported native operation kind"));
        }
        assert_eq!(
            store.recover_agent_chat_native_operations().await.unwrap(),
            0
        );
        assert_eq!(
            store
                .pending_agent_chat_native_operation(&chat)
                .await
                .unwrap()
                .unwrap(),
            before
        );
        assert_eq!(
            store
                .check_agent_chat_receipt(
                    &json!(["desktop", "agentChat.nativeRewind"]).to_string(),
                    "one",
                    "one"
                )
                .await
                .unwrap(),
            AgentChatReceiptCheck::New
        );
        assert!(store.archive_agent_chat(&chat).await.is_err());
        let mut linked = task(state);
        linked.parent_chat_id = Some(chat.clone());
        assert_pending_conflict(
            store
                .create_chat_orchestration_task(linked, None)
                .await
                .unwrap_err(),
        );
        let summary = agent_chat_native_operation_public_summary(&before);
        assert_eq!(summary["kind"], "unknown");
        assert_eq!(summary["recovery"]["needsReconciliation"], true);
        for action in [
            "canCancelUnstarted",
            "canFinishAcknowledged",
            "canRestartFromTranscript",
            "canContinueFromCurrentFiles",
        ] {
            assert_eq!(summary["recovery"][action], Value::Bool(false));
        }
    }
}
