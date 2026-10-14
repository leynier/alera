use std::sync::Arc;
use std::time::Duration;

use super::*;
use crate::terminal_host::server::chat_orchestration::mock_provider::MockProviderFactory;
use crate::terminal_host::server::checkout_buffer_guards_tests;

use super::super::commands::CallerCtx;
use super::super::events::NullSink;
use super::super::session::SessionDeps;
use super::super::wire::ChatTurn;
use super::super::{AgentChatRuntime, ChatActivity, CreateChatInput, InstanceDirectory};

const TIMESTAMP: &str = "2026-10-13T10:00:00.000Z";

fn request(id: &str) -> ChatRequest {
    serde_json::from_value(json!({
        "requestId": id, "kind": "commandExecutionApproval", "turnId": "turn",
        "createdAt": TIMESTAMP, "title": "Run A Command", "command": "echo hello",
        "decisions": ["accept", "decline"],
    }))
    .unwrap()
}

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

fn notice(session: &mut ChatSession, id: &str) {
    let mut item = ChatItem::new(id.into(), "notice", TIMESTAMP, 1);
    item.status = "completed".into();
    item.text = Some("Unrelated history".into());
    session.insert_item(item);
}

fn turn(session: &mut ChatSession, id: &str) {
    let turn: ChatTurn = serde_json::from_value(json!({
        "turnId": id, "status": "completed", "startedAt": TIMESTAMP,
        "completedAt": TIMESTAMP, "provider": "codex", "providerInstanceId": "codex",
        "generation": 1,
    }))
    .unwrap();
    session.header.upsert_turn(turn);
}

#[test]
fn history_tokens_require_a_positive_sequence() {
    assert_eq!(history_before(None).unwrap(), i64::MAX);
    assert_eq!(history_before(Some("seq:12")).unwrap(), 12);
    for invalid in ["12", "seq:0", "seq:-1", "seq:x", "seq:9223372036854775808"] {
        assert!(history_before(Some(invalid)).is_err(), "{invalid}");
    }
}

#[test]
fn request_history_excludes_freeform_response_values() {
    let request = request("r");
    let projection = request_projection(
        &request,
        "resolved",
        Some(&json!({
            "type": "approval", "decision": "accept", "answers": {"password": "private"},
            "result": "private", "content": "private", "updatedInput": {"secret": "private"},
        })),
        Some("human"),
        TIMESTAMP,
    );
    assert_eq!(
        projection["response"],
        json!({"type": "approval", "decision": "accept"})
    );
    assert!(!projection.to_string().contains("private"));
    assert_eq!(projection["actor"], "human");
    assert_eq!(projection["resolvedAt"], TIMESTAMP);

    let unsupported = request_projection(
        &request,
        "resolved",
        Some(&json!({
            "type": "approval", "decision": "acceptAlways",
        })),
        None,
        TIMESTAMP,
    );
    assert_eq!(unsupported["response"], json!({"type": "approval"}));

    let input = request_projection(
        &request,
        "resolved",
        Some(&json!({
            "type": "userInput", "answers": {"value": "private"},
        })),
        None,
        TIMESTAMP,
    );
    assert_eq!(input["response"], json!({"type": "userInput"}));
}

#[test]
fn provider_diff_never_infers_changes_from_command_output_or_previews() {
    assert!(provider_diff(
        &json!({
            "itemId": "command", "turnId": "t", "type": "command_execution",
            "output": "+added line", "normalized": {"changes": [{"path": "a"}]},
        }),
        "t"
    )
    .is_none());
    assert!(provider_diff(
        &json!({
            "itemId": "preview", "turnId": "t", "type": "file_change",
            "normalized": {"changes": "[{\"path\":\"a\"}]..."},
        }),
        "t"
    )
    .is_none());
    let reported = json!({"path": "a", "kind": "update", "diff": "+line"});
    let exact = provider_diff(
        &json!({
            "itemId": "change", "turnId": "t", "type": "file_change", "status": "completed",
            "normalized": {"changes": [reported.clone()]},
        }),
        "t",
    )
    .unwrap();
    assert_eq!(exact["changes"], json!([reported]));
    assert!(provider_diff(
        &json!({
            "itemId": "other", "turnId": "other", "type": "file_change",
            "data": {"diff": "+other"},
        }),
        "t"
    )
    .is_none());
}

#[tokio::test]
async fn request_resolution_updates_one_durable_history_item_and_survives_reload() {
    let (_root, mut session) = session_fixture().await;
    turn(&mut session, "turn");
    let request = request("r");
    session.record_request_history(&request, "pending", None, None);
    session.flush().await.unwrap();
    let pending = session.approval_history(None, 10).await.unwrap();
    assert_eq!(
        pending["items"][0]["normalized"]["approvalHistory"]["status"],
        "pending"
    );
    session.record_request_history(
        &request,
        "resolved",
        Some(&json!({
            "type": "approval", "decision": "decline", "content": "private",
        })),
        Some("mobile:person"),
    );
    session.flush().await.unwrap();

    let mut reloaded = ChatSession::load(&session.header.chat_id, session.deps.clone())
        .await
        .unwrap();
    let resolved = reloaded.approval_history(None, 10).await.unwrap();
    assert_eq!(resolved["items"].as_array().unwrap().len(), 1);
    assert_eq!(resolved["items"][0]["itemId"], "approvalHistory:r");
    let history = &resolved["items"][0]["normalized"]["approvalHistory"];
    assert_eq!(history["response"]["decision"], "decline");
    assert_eq!(history["actor"], "mobile:person");
    assert!(!resolved.to_string().contains("private"));
}

#[tokio::test]
async fn approval_pages_keep_matching_rows_across_sparse_transcript_boundaries() {
    let (_root, mut session) = session_fixture().await;
    turn(&mut session, "turn");
    for index in 0..3 {
        session.record_request_history(&request(&format!("r{index}")), "expired", None, None);
        session.flush().await.unwrap();
        for gap in 0..8 {
            notice(&mut session, &format!("noise-{index}-{gap}"));
        }
        session.flush().await.unwrap();
    }
    let newest = session.approval_history(None, 2).await.unwrap();
    let ids = newest["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["itemId"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(ids, ["approvalHistory:r1", "approvalHistory:r2"]);
    let older = session
        .approval_history(newest["historyBefore"].as_str(), 2)
        .await
        .unwrap();
    assert_eq!(older["items"].as_array().unwrap().len(), 1);
    assert_eq!(older["items"][0]["itemId"], "approvalHistory:r0");
    assert!(older["historyBefore"].is_null());
    assert_eq!(older["scanLimited"], false);
}

#[tokio::test]
async fn sparse_history_scan_reports_its_bounded_continuation() {
    let (_root, mut session) = session_fixture().await;
    for index in 0..HISTORY_SCAN_MAX_PAGES + 8 {
        notice(&mut session, &format!("noise-{index}"));
    }
    session.flush().await.unwrap();
    let page = session.approval_history(None, 1).await.unwrap();
    assert!(page["items"].as_array().unwrap().is_empty());
    assert_eq!(page["scanLimited"], true);
    assert!(page["historyBefore"].as_str().unwrap().starts_with("seq:"));
}

#[tokio::test]
async fn turn_diff_reads_durable_provider_changes_beyond_the_snapshot_window() {
    let (_root, mut session) = session_fixture().await;
    turn(&mut session, "turn");
    let changes = json!([{"path": "source.rs", "kind": "update", "diff": "+new"}]);
    let mut changed = ChatItem::new("change".into(), "file_change", TIMESTAMP, 1);
    changed.turn_id = Some("turn".into());
    changed.status = "completed".into();
    changed.normalized.insert("changes".into(), changes.clone());
    session.insert_item(changed);
    session.flush().await.unwrap();
    for index in 0..HISTORY_MAX_ITEMS + 4 {
        notice(&mut session, &format!("noise-{index}"));
    }
    session.flush().await.unwrap();
    session.items.clear();
    let diff = session.turn_diff("turn").await.unwrap();
    assert_eq!(diff["source"], "provider");
    assert_eq!(diff["available"], true);
    assert_eq!(diff["truncated"], false);
    assert_eq!(diff["items"].as_array().unwrap().len(), 1);
    assert_eq!(diff["items"][0]["changes"], changes);
    assert!(session.turn_diff("missing").await.is_err());
}

#[tokio::test]
async fn provider_turn_diff_updates_one_redacted_entry_with_exact_payload_paging() {
    let (_root, mut session) = session_fixture().await;
    turn(&mut session, "turn");
    session
        .record_turn_diff("turn", &json!({"diff": "+first", "secret": "private", "threadId": "private-thread", "turnId": "private-turn"}))
        .await
        .unwrap();
    session.flush().await.unwrap();
    let initial = session.turn_diff("turn").await.unwrap();
    assert_eq!(initial["items"][0]["diff"], "+first");
    assert!(!initial.to_string().contains("private"));

    let exact = "+line\n".repeat(20_000);
    session
        .record_turn_diff("turn", &json!({"diff": exact, "apiKey": "private"}))
        .await
        .unwrap();
    session.flush().await.unwrap();
    let larger = session.turn_diff("turn").await.unwrap();
    assert_eq!(larger["items"].as_array().unwrap().len(), 1);
    assert!(larger["items"][0]["payloadRef"].is_object());
    let payload = session
        .deps
        .store
        .agent_chat_payload(&session.header.chat_id, "turnDiff:turn", 0, 200)
        .await
        .unwrap();
    let retained: Value = serde_json::from_str(
        &payload
            .chunks
            .iter()
            .map(|chunk| chunk.text.as_str())
            .collect::<String>(),
    )
    .unwrap();
    assert_eq!(retained["diff"], exact);
    assert!(!retained.to_string().contains("private"));
}
