//! Shared `ext:mcp` inbox: attribution, retry keys, and per-client filters.

use serde_json::{json, Value};

use super::super::inbox_test_fixture::*;

fn mcp_origin(client: &str) -> Value {
    json!({ "transport": "remote", "clientId": client, "clientName": client.to_uppercase(), "callId": "c-1" })
}

async fn ask(fixture: &mut Fixture, client: &str, to: &str) -> String {
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": to, "body": "Status?", "inbox": "ext:mcp", "externalOrigin": mcp_origin(client)}),
        )
        .await;
    asked["questionId"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn only_local_clients_record_an_mcp_origin() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?", "inbox": "ext:mcp", "externalOrigin": mcp_origin("chatgpt")}),
        )
        .await;
    let origin = &asked["message"]["external_meta"]["origin"];
    assert_eq!(origin["surface"], "mcp");
    assert_eq!(origin["clientName"], "CHATGPT");
    assert!(origin.get("callId").is_none());
    assert_eq!(asked["origin"], *origin);
    let phone = fixture
        .request(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?", "externalOrigin": mcp_origin("chatgpt")}),
        )
        .await;
    assert_eq!(phone["errorCode"], "inbox_origin_forbidden");
    let malformed = fixture
        .request(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?", "externalOrigin": {"clientName": "x"}}),
        )
        .await;
    assert_eq!(malformed["errorCode"], "inbox_invalid_origin");
}

#[tokio::test]
async fn a_retried_ask_with_the_same_key_returns_the_first_question() {
    let mut fixture = fixture().await;
    let payload = json!({
        "to": "claude-term",
        "body": "?",
        "inbox": "ext:mcp",
        "externalOrigin": mcp_origin("chatgpt"),
        "requestKey": "request-0001",
    });
    let first = fixture.ok(CLI, "inbox.ask", payload.clone()).await;
    let retry = fixture.ok(CLI, "inbox.ask", payload.clone()).await;
    assert_eq!(first["deduplicated"], false);
    assert_eq!(retry["deduplicated"], true);
    assert_eq!(retry["questionId"], first["questionId"]);
    let mut other_client = payload;
    other_client["externalOrigin"] = mcp_origin("claude-ai");
    let separate = fixture.ok(CLI, "inbox.ask", other_client).await;
    assert_ne!(separate["questionId"], first["questionId"]);
}

#[tokio::test]
async fn threads_and_inbox_waits_filter_by_the_origin_client() {
    let mut fixture = fixture().await;
    let own = ask(&mut fixture, "chatgpt", "claude-term").await;
    let foreign = ask(&mut fixture, "claude-ai", "codex-term").await;
    let threads = fixture
        .ok(
            CLI,
            "inbox.threads",
            json!({"inbox": "ext:mcp", "originClientId": "chatgpt"}),
        )
        .await;
    let items = threads["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["threadId"], own.as_str());
    assert_eq!(items[0]["origin"]["clientId"], "chatgpt");

    fixture.reply(&foreign, "Not yours").await;
    let quiet = fixture
        .ok(
            CLI,
            "inbox.wait",
            json!({"inbox": "ext:mcp", "after": 0, "timeoutMs": 0, "originClientId": "chatgpt"}),
        )
        .await;
    assert_eq!(quiet["outcome"], "pending");
    let skipped = quiet["cursor"].as_i64().unwrap();
    assert!(skipped > 0, "the cursor moves past other clients' replies");
    let foreign_thread = fixture
        .ok(CLI, "inbox.thread", json!({"threadId": foreign}))
        .await;
    assert_eq!(foreign_thread["thread"]["unreadReplyCount"], 1);

    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"inbox": "ext:mcp", "after": skipped, "timeoutMs": 60000, "originClientId": "chatgpt"}),
        )
        .await;
    fixture.reply(&own, "Yours").await;
    let woken = fixture.take_response(DESKTOP, wait_id).unwrap();
    let payload = &woken["payload"];
    assert_eq!(payload["outcome"], "message");
    assert_eq!(payload["messages"].as_array().unwrap().len(), 1);
    assert_eq!(
        payload["threadOrigins"][own.as_str()]["clientId"],
        "chatgpt"
    );
}
