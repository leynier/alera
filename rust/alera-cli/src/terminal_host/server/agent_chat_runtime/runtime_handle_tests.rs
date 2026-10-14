use super::*;
use crate::terminal_host::server::agent_chat_runtime::commands::{ConfigureInput, SendInput};
use crate::terminal_host::server::chat_orchestration::test_support::TestHarness;

const DEADLINE: Duration = Duration::from_secs(5);

#[path = "runtime_draft_regression_tests.rs"]
mod draft_regressions;

#[tokio::test]
async fn unselected_draft_is_durable_and_refuses_send_until_configured() {
    let harness = TestHarness::new().await;
    let created = harness
        .runtime
        .create(
            CreateChatInput {
                workspace_id: "ws-a".into(),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let chat_id = created["chatId"].as_str().unwrap();
    assert!(created["snapshot"]["provider"].is_null());
    assert!(created["snapshot"]["providerInstanceId"].is_null());
    let tab = harness
        .store
        .find_workspace_tab(created["tabId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    assert!(tab.payload["providerInstanceId"].is_null());
    let error = harness
        .runtime
        .send(
            chat_id,
            SendInput {
                client_message_id: "unselected".into(),
                text: "Keep this draft".into(),
                attachments: Vec::new(),
                delivery: "auto".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: None,
            },
            CallerCtx::runtime(),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("agent") || error.to_string().contains("providerRequired"));
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(harness.runtime.snapshot(chat_id).await.unwrap()["turns"]
        .as_array()
        .unwrap()
        .is_empty());
    harness
        .runtime
        .command(
            chat_id,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("codex".into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.send_human(chat_id, "selected", "Start now").await;
    let control = harness.control(chat_id).await;
    tokio::time::timeout(DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    harness.finish().await;
}

#[tokio::test]
async fn closing_draft_discards_record_and_tab_and_replays_after_deletion() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    let tab_id = harness.runtime.snapshot(&chat_id).await.unwrap()["tabId"]
        .as_str()
        .unwrap()
        .to_string();
    let receipt = ReceiptKey {
        verb: "agentChat.close".into(),
        request_id: "discard".into(),
        digest: "same".into(),
    };
    let result = harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Close,
            CallerCtx::runtime(),
            Some(receipt.clone()),
        )
        .await
        .unwrap();
    assert_eq!(result["archived"], false);
    assert_eq!(result["discarded"], true);
    assert!(harness.store.agent_chat(&chat_id).await.unwrap().is_none());
    assert!(harness
        .store
        .find_workspace_tab(&tab_id)
        .await
        .unwrap()
        .is_none());
    assert!(harness
        .runtime
        .list(Some("ws-a"), true)
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        harness
            .runtime
            .command(&chat_id, ChatOp::Close, CallerCtx::runtime(), Some(receipt))
            .await
            .unwrap(),
        result
    );
    harness.finish().await;
}

#[tokio::test]
async fn read_cursor_is_receipt_backed_without_changing_snapshot_cursor() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    let before = harness.runtime.snapshot(&chat_id).await.unwrap();
    let cursor = before["cursor"].as_i64().unwrap();
    let key = ReceiptKey {
        verb: "agentChat.markRead".into(),
        request_id: "read".into(),
        digest: "read".into(),
    };
    let response = harness
        .runtime
        .mark_read(&chat_id, cursor, CallerCtx::runtime(), Some(key.clone()))
        .await
        .unwrap();
    assert_eq!(response["readCursor"], cursor);
    assert_eq!(
        harness
            .runtime
            .mark_read(&chat_id, cursor, CallerCtx::runtime(), Some(key))
            .await
            .unwrap(),
        response
    );
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["cursor"],
        before["cursor"]
    );
    assert_eq!(
        harness.runtime.list(Some("ws-a"), false).await.unwrap()[0]["unread"],
        false
    );
    harness.finish().await;
}

async fn settled(harness: &TestHarness, chat_id: &str) {
    tokio::time::timeout(DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(chat_id).await.unwrap();
            if snapshot["session"]["activeTurnId"].is_null() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn create_and_recover_spawn_nothing_first_send_starts_turn_one() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    assert!(uuid::Uuid::parse_str(&chat_id).is_ok());
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert_eq!(snapshot["session"]["status"], "stopped");
    assert!(snapshot["recovery"].is_null());
    assert_eq!(snapshot["titleSource"], "default");
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Recover { mode: None },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    let response = harness
        .send_human(&chat_id, "message-1", "  First title  \nMore detail")
        .await;
    assert_eq!(response["delivery"], "started");
    let control = harness.control(&chat_id).await;
    tokio::time::timeout(DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    assert_eq!(
        control.turns.lock().unwrap()[0].input,
        "  First title  \nMore detail"
    );
    assert_eq!(harness.factory.launches.lock().unwrap().len(), 1);
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert_eq!(snapshot["title"], "First title");
    assert_eq!(snapshot["titleSource"], "derived");
    assert_eq!(snapshot["turns"].as_array().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn reopening_cached_archived_chat_updates_actor() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    harness.send_human(&chat_id, "sent", "Keep this chat").await;
    harness
        .runtime
        .command(&chat_id, ChatOp::Close, CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["archived"],
        true
    );
    let reopened = harness
        .runtime
        .reopen(&chat_id, CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert_eq!(reopened["snapshot"]["archived"], false);
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["archived"],
        false
    );
    harness.finish().await;
}

#[tokio::test]
async fn empty_provider_switch_is_silent_and_explicit_model_reset_preserves_user_title() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Rename {
                title: "My title".into(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("claudeAgent".into()),
                model: Some(Some("model-a".into())),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Configure(ConfigureInput {
                model: Some(None),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert!(snapshot["session"]["model"].is_null());
    assert_eq!(snapshot["providerInstanceId"], "claudeAgent");
    assert_eq!(snapshot["title"], "My title");
    assert_eq!(snapshot["titleSource"], "user");
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness
        .send_human(&chat_id, "first", "Do not replace my title")
        .await;
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["title"],
        "My title"
    );
    harness.finish().await;
}

#[tokio::test]
async fn history_provider_switch_defers_spawn_and_hands_context_to_next_send() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&chat_id, "first", "Earlier question")
        .await;
    let control = harness.control(&chat_id).await;
    tokio::time::timeout(DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Earlier answer");
    settled(&harness, &chat_id).await;
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("claudeAgent".into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(harness.factory.launches.lock().unwrap().len(), 1);
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["session"]["status"],
        "stopped"
    );
    harness
        .send_human(&chat_id, "second", "Continue here")
        .await;
    tokio::time::timeout(DEADLINE, async {
        loop {
            if harness.factory.launches.lock().unwrap().len() == 2 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    let next = harness.control(&chat_id).await;
    tokio::time::timeout(DEADLINE, next.wait_turns(1))
        .await
        .unwrap();
    let input = next.turns.lock().unwrap()[0].input.clone();
    assert!(input.contains("Earlier question"));
    assert!(input.contains("Earlier answer"));
    assert!(input.ends_with("Continue here"));
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["turns"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    harness.finish().await;
}

#[tokio::test]
async fn unsupported_effort_and_queue_steer_keep_state() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    let before = harness.runtime.snapshot(&chat_id).await.unwrap();
    let error = harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Configure(ConfigureInput {
                reasoning_effort: Some(Some("high".into())),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("unsupported") || error.to_string().contains("effort"));
    assert_eq!(harness.runtime.snapshot(&chat_id).await.unwrap(), before);
    let turn = harness.send_human(&chat_id, "first", "First").await;
    let control = harness.control(&chat_id).await;
    tokio::time::timeout(DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let queue = harness
        .runtime
        .send(
            &chat_id,
            SendInput {
                client_message_id: "queue".into(),
                text: "Queued".into(),
                attachments: Vec::new(),
                delivery: "queue".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: None,
            },
            CallerCtx::runtime(),
        )
        .await
        .unwrap();
    let result = harness
        .runtime
        .command(
            &chat_id,
            ChatOp::QueuePromoteToSteer {
                queue_id: queue["queueId"].as_str().unwrap().into(),
                turn_id: turn["turnId"].as_str().unwrap().into(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await;
    assert!(result.is_err());
    assert_eq!(
        harness.runtime.snapshot(&chat_id).await.unwrap()["queue"][0]["text"],
        "Queued"
    );
    assert_eq!(control.turns.lock().unwrap().len(), 1);
    harness.finish().await;
}
