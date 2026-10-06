use serde_json::json;

use super::inbox_test_fixture::*;

#[tokio::test]
async fn phones_get_only_the_inbox_verbs_on_their_allowlist() {
    let mut fixture = fixture().await;
    for verb in ["inbox.summary", "inbox.threads", "inbox.targets"] {
        fixture.ok(PHONE, verb, json!({})).await;
    }
    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    fixture
        .ok(
            PHONE,
            "inbox.thread",
            json!({"threadId": question_id, "markRead": true}),
        )
        .await;
    fixture
        .ok(PHONE, "inbox.markRead", json!({"threadId": question_id}))
        .await;
    let wait = fixture
        .request(PHONE, "inbox.wait", json!({"questionId": question_id}))
        .await;
    assert_eq!(wait["ok"], false);
    assert_eq!(
        wait["error"],
        "Mobile clients cannot call terminal host request: inbox.wait"
    );
    let purged = fixture
        .ok(PHONE, "inbox.purge", json!({"inbox": "ext:user"}))
        .await;
    assert_eq!(purged["deleted"], 1);
}

#[tokio::test]
async fn agents_cannot_write_as_an_inbox() {
    let mut fixture = fixture().await;
    let send = fixture
        .request(
            CLI,
            "orchestration.send",
            json!({"from": "ext:ci", "to": "claude-term", "subject": "Sneaky"}),
        )
        .await;
    assert_eq!(send["ok"], false, "{send}");
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let reply = fixture.reply(&question_id, "Answer").await;
    let reply_id = reply["id"].as_str().unwrap().to_string();
    let bounced = fixture
        .request(
            CLI,
            "orchestration.reply",
            json!({"id": reply_id, "body": "Follow-up"}),
        )
        .await;
    assert_eq!(bounced["ok"], false, "{bounced}");
    let dispatch = fixture
        .request(
            CLI,
            "orchestration.dispatch",
            json!({"task": "missing", "to": "ext:ci"}),
        )
        .await;
    assert_eq!(dispatch["ok"], false, "{dispatch}");
    assert!(dispatch["error"].as_str().unwrap().contains("inbox"));
}

#[tokio::test]
async fn cancel_waits_for_an_in_flight_paste_and_follow_ups_need_a_live_recipient() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "First?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    fixture
        .actor
        .orchestration_delivery_in_flight
        .insert("claude-term".to_string());
    let refused = fixture
        .request(CLI, "inbox.cancel", json!({"questionId": question_id}))
        .await;
    assert_eq!(refused["errorCode"], "inbox_not_cancellable", "{refused}");
    fixture
        .actor
        .orchestration_delivery_in_flight
        .remove("claude-term");
    fixture
        .ok(CLI, "inbox.cancel", json!({"questionId": question_id}))
        .await;

    let second = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Second?", "inbox": "ext:ci"}),
        )
        .await;
    let thread_id = second["threadId"].as_str().unwrap().to_string();
    // A workspace only chooses the recipient of a new thread.
    let follow_up = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"threadId": thread_id, "workspaceId": "ws-1", "body": "And then?"}),
        )
        .await;
    assert_eq!(
        follow_up["recipient"]["handle"], "codex-term",
        "{follow_up}"
    );
    fixture.actor.sessions.remove("codex-term");
    let gone = fixture
        .request(
            PHONE,
            "inbox.ask",
            json!({"threadId": thread_id, "body": "Still there?"}),
        )
        .await;
    assert_eq!(gone["errorCode"], "inbox_unknown_recipient", "{gone}");
}

#[tokio::test]
async fn agents_reach_an_inbox_only_inside_its_threads() {
    let mut fixture = fixture().await;
    let loose = fixture
        .request(
            CLI,
            "orchestration.send",
            json!({"from": "claude-term", "to": "ext:user", "subject": "Hello"}),
        )
        .await;
    assert_eq!(loose["errorCode"], "inbox_thread_required", "{loose}");
    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"to": "claude-term", "body": "?"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let stranger = fixture
        .request(
            CLI,
            "orchestration.send",
            json!({"from": "codex-term", "to": "ext:user", "subject": "Me too", "threadId": question_id}),
        )
        .await;
    assert_eq!(stranger["errorCode"], "inbox_thread_required", "{stranger}");
    let sent = fixture
        .ok(
            CLI,
            "orchestration.send",
            json!({"from": "claude-term", "to": "ext:user", "subject": "Progress", "threadId": question_id}),
        )
        .await;
    assert_eq!(sent["messages"][0]["thread_id"], question_id);
    let thread = fixture
        .ok(PHONE, "inbox.thread", json!({"threadId": question_id}))
        .await;
    assert_eq!(thread["messages"][1]["kind"], "message");
}

#[tokio::test]
async fn out_of_range_expiry_is_refused_without_asking() {
    let mut fixture = fixture().await;
    for expires in [
        json!(u64::MAX),
        json!(i64::MAX),
        json!(-5),
        json!("1h"),
        json!(8 * 24 * 60 * 60 * 1000_u64),
    ] {
        let refused = fixture
            .request(
                CLI,
                "inbox.ask",
                json!({"to": "claude-term", "body": "?", "inbox": "ext:ci", "expiresInMs": expires}),
            )
            .await;
        assert_eq!(
            refused["errorCode"], "inbox_invalid_expiry",
            "{expires}: {refused}"
        );
    }
    let threads = fixture.ok(CLI, "inbox.threads", json!({})).await;
    assert!(threads["items"].as_array().unwrap().is_empty());
}
