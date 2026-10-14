use alera_core::runtime::{RuntimeMobilePushSettings, WorkspaceTabRecord};
use chrono::{Duration, Utc};
use serde_json::json;

use super::agent_chat_runtime::ChatRuntimeEvent;
use super::checkout_buffer_guards_tests::fixture;
use crate::terminal_host::push_notifications::PushEvent;

#[tokio::test]
async fn committed_chat_requests_honor_opt_in_replay_cooldown_and_safe_routing() {
    let (_root, mut actor) = fixture().await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "chat-tab".into(),
            workspace_id: "task".into(),
            kind: "agentChat".into(),
            title: "Chat".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"chatId":"chat"}),
        })
        .await
        .unwrap();
    let request = |id: &str, created: chrono::DateTime<Utc>| {
        json!({
            "requestId":id,"kind":"command_execution_approval","createdAt":created,
            "command":"private command","detail":"private reason",
        })
    };
    let change = |cursor, requests| ChatRuntimeEvent::Changed {
        chat_id: "chat".into(),
        workspace_id: "task".into(),
        cursor,
        delta: json!({"requests":requests}),
    };
    actor
        .queue_chat_runtime_push(&change(1, vec![request("disabled", now)]))
        .await;
    assert!(actor.account_push.pending_events.is_empty());
    actor
        .runtime_store
        .set_mobile_push_settings(&RuntimeMobilePushSettings {
            enabled: true,
            ..Default::default()
        })
        .await
        .unwrap();
    actor
        .queue_chat_runtime_push(&ChatRuntimeEvent::ChatsChanged {
            workspace_id: Some("task".into()),
        })
        .await;
    actor
        .queue_chat_runtime_push(&change(2, vec![request("old", now - Duration::hours(1))]))
        .await;
    assert!(actor.account_push.pending_events.is_empty());
    actor
        .queue_chat_runtime_push(&change(3, vec![request("fresh", Utc::now())]))
        .await;
    actor
        .queue_chat_runtime_push(&change(3, vec![request("fresh", Utc::now())]))
        .await;
    actor
        .queue_chat_runtime_push(&change(4, vec![request("fresh", Utc::now())]))
        .await;
    actor
        .queue_chat_runtime_push(&change(5, vec![request("nearby", Utc::now())]))
        .await;
    assert_eq!(actor.account_push.pending_events.len(), 1);
    let event = &actor.account_push.pending_events[0];
    assert_eq!(event.data["chatId"], "chat");
    assert_eq!(event.data["workspaceId"], "task");
    assert_eq!(event.data["tabId"], "chat-tab");
    assert!(!event.data.to_string().contains("private"));
    assert!(!event.title.contains("private"));
    assert!(!event.body.contains("private"));
}

#[tokio::test]
async fn child_request_and_task_attention_coalesce_in_either_commit_order() {
    let (_root, mut actor) = fixture().await;
    let chat_event = || {
        PushEvent::chat_request(
            "chat",
            "request",
            "approval",
            Utc::now(),
            crate::terminal_host::push_notifications::PushLocation {
                terminal_session_id: None,
                workspace_id: Some("task".into()),
                tab_id: Some("chat-tab".into()),
                project_name: None,
                workspace_name: None,
                tab_title: None,
            },
        )
    };
    let task_event =
        || PushEvent::chat_task_attention("task-id", 2, true, Some("chat"), Utc::now(), None);
    for chat_first in [true, false] {
        actor.account_push.pending_events.clear();
        let (first, second) = if chat_first {
            (chat_event(), task_event())
        } else {
            (task_event(), chat_event())
        };
        actor.enqueue_push_event(first);
        actor.enqueue_push_event(second);
        assert_eq!(actor.account_push.pending_events.len(), 1);
        assert_eq!(
            actor.account_push.pending_events[0].data["kind"],
            "agentChat"
        );
    }
}

#[tokio::test]
async fn remote_committed_request_push_uses_hub_account_and_validated_mirrored_chat() {
    use super::actor_test_harness::test_actor;
    use super::agent_chat_remote::tests::remote_fixture;
    use std::collections::HashMap;

    let (root, router, _satellite) = remote_fixture().await;
    router.sync_workspace("task").await.unwrap();
    let mut hub = test_actor(&root, HashMap::new(), HashMap::new()).await;
    hub.runtime_store
        .set_mobile_push_settings(&RuntimeMobilePushSettings {
            enabled: true,
            ..Default::default()
        })
        .await
        .unwrap();
    let payload = json!({"chatId":"remote-chat","workspaceId":"task","cursor":5,"delta":{
        "requests":[{"requestId":"remote-request","kind":"tool_user_input","createdAt":Utc::now(),"questions":[{"question":"private question"}]}]
    }});
    assert!(router
        .validated_change("wrong-satellite", &payload)
        .await
        .unwrap()
        .is_none());
    let change = router
        .validated_change("satellite", &payload)
        .await
        .unwrap()
        .unwrap();
    hub.handle(super::ServerCommand::AgentChatRuntimeEvent { event: change })
        .await;
    assert_eq!(hub.account_push.pending_events.len(), 1);
    let request = hub.account_push.pending_events[0]
        .clone()
        .into_request(hub.account_push.service.runtime_id());
    assert_eq!(request.runtime_id, hub.account_push.service.runtime_id());
    assert_eq!(request.data["chatId"], "remote-chat");
    assert_eq!(request.data["workspaceId"], "task");
    assert_eq!(request.data["tabId"], "remote-tab");
    assert!(!request.data.to_string().contains("private"));
    assert!(router
        .validated_change("satellite", &payload)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn failed_task_attention_survives_missing_child_and_dedupes_committed_revision() {
    use alera_core::runtime::{
        ChatOrchestrationNotify, ChatOrchestrationTarget, ChatOrchestrationTaskKind,
        ChatOrchestrationTaskStatus, ChatOrchestrationTaskTransition, NewChatOrchestrationTask,
    };
    let (_root, mut actor) = fixture().await;
    actor
        .runtime_store
        .set_mobile_push_settings(&RuntimeMobilePushSettings {
            enabled: true,
            ..Default::default()
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .create_chat_orchestration_task(
            NewChatOrchestrationTask {
                task_id: "attention-task".into(),
                kind: ChatOrchestrationTaskKind::Delegate,
                caller_scope: "desktop".into(),
                parent_task_id: None,
                parent_chat_id: None,
                child_chat_id: None,
                project_id: None,
                workspace_id: None,
                host_id: Some("satellite".into()),
                target: ChatOrchestrationTarget::Chat {
                    chat_id: "deleted-chat".into(),
                },
                title: Some("private task title".into()),
                role: None,
                brief: "private brief".into(),
                notify: ChatOrchestrationNotify::Always,
                launch_options: None,
            },
            None,
        )
        .await
        .unwrap();
    let mut failed = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Failed,
    );
    failed.error = Some("private provider error".into());
    actor
        .runtime_store
        .transition_chat_orchestration_task("attention-task", &failed)
        .await
        .unwrap();
    let change = json!({"taskId":"attention-task"});
    actor.queue_chat_task_push(&change).await;
    actor.queue_chat_task_push(&change).await;
    assert_eq!(actor.account_push.pending_events.len(), 1);
    let event = &actor.account_push.pending_events[0];
    assert_eq!(event.data["taskId"], "attention-task");
    assert_eq!(event.data["kind"], "chatTask");
    assert!(event.data["chatId"].is_null());
    assert!(!event.body.contains("private"));
    assert!(!event.data.to_string().contains("private"));
}
