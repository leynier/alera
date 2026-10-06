use serde_json::json;

use super::inbox_test_fixture::*;

#[tokio::test]
async fn ask_resolves_the_recipient_and_records_where_it_came_from() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            PHONE,
            "inbox.ask",
            json!({"workspaceId": "ws-1", "agent": "Claude", "body": "Which tests cover login?\nDetails"}),
        )
        .await;
    assert_eq!(asked["recipient"]["handle"], "claude-term");
    assert_eq!(asked["recipient"]["deliveryMode"], "paste");
    let message = &asked["message"];
    assert_eq!(message["from_handle"], "ext:user");
    assert_eq!(message["subject"], "Which tests cover login?");
    assert_eq!(message["priority"], "high");
    assert_eq!(message["workspace_id"], "ws-1");
    assert_eq!(message["external_meta"]["origin"]["surface"], "mobile");
    assert_eq!(message["external_meta"]["origin"]["deviceId"], "pixel");
    assert_eq!(message["external_meta"]["target"]["agent"], "claude");

    let desktop = fixture
        .ok(
            DESKTOP,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Status?", "inbox": "ext:ci"}),
        )
        .await;
    assert_eq!(
        desktop["message"]["external_meta"]["origin"]["surface"],
        "desktop"
    );

    let ambiguous = fixture
        .request(
            CLI,
            "inbox.ask",
            json!({"workspaceId": "ws-1", "body": "?"}),
        )
        .await;
    assert_eq!(ambiguous["errorCode"], "inbox_ambiguous_recipient");
    assert_eq!(
        ambiguous["errorDetails"]["candidates"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    let missing = fixture
        .request(
            CLI,
            "inbox.ask",
            json!({"workspaceId": "ws-1", "agent": "cursor", "body": "?"}),
        )
        .await;
    assert_eq!(missing["errorCode"], "inbox_no_recipient");
    let unknown = fixture
        .request(CLI, "inbox.ask", json!({"to": "ghost", "body": "?"}))
        .await;
    assert_eq!(unknown["errorCode"], "inbox_unknown_recipient");
    let single = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"workspaceId": "ws-2", "body": "?", "inbox": "ext:ci"}),
        )
        .await;
    assert_eq!(single["recipient"]["handle"], "lonely-term");
    assert_eq!(
        single["message"]["external_meta"]["origin"]["surface"],
        "cli"
    );
}

#[tokio::test]
async fn targets_list_running_agents_with_their_delivery_mode() {
    let mut fixture = fixture().await;
    let targets = fixture
        .ok(PHONE, "inbox.targets", json!({"workspaceId": "ws-1"}))
        .await;
    let handles: Vec<_> = targets["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["handle"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(handles, ["claude-term", "codex-term"]);
}

#[tokio::test]
async fn replies_correlate_wake_waiters_and_move_the_revision() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "Risky?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    assert!(fixture.events_named(PHONE, "inboxChanged") >= 1);

    let pending = fixture
        .ok(
            CLI,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 0}),
        )
        .await;
    assert_eq!(pending["outcome"], "pending");

    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    assert!(fixture.take_response(DESKTOP, wait_id).is_none());

    let reply = fixture.reply(&question_id, "Low risk").await;
    assert_eq!(reply["reply_to_id"], question_id);
    let woken = fixture
        .take_response(DESKTOP, wait_id)
        .expect("the reply woke the waiter");
    assert_eq!(woken["payload"]["outcome"], "answered");
    assert_eq!(woken["payload"]["messages"][0]["kind"], "reply");
    assert!(fixture.events_named(PHONE, "inboxChanged") >= 1);

    let thread = fixture
        .ok(PHONE, "inbox.thread", json!({"threadId": question_id}))
        .await;
    assert_eq!(thread["thread"]["status"], "answered");
    // The waiter that received the reply marked it read for everyone.
    assert_eq!(thread["thread"]["unreadReplyCount"], 0);
}

#[tokio::test]
async fn wait_times_out_after_a_final_check_and_reports_cancellation() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Later?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            CLI,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    let cancelled = fixture
        .ok(PHONE, "inbox.cancel", json!({"questionId": question_id}))
        .await;
    assert_eq!(cancelled["message"]["state"], "obsolete");
    assert_eq!(
        cancelled["message"]["external_meta"]["cancellation"]["surface"],
        "mobile"
    );
    let woken = fixture
        .take_response(CLI, wait_id)
        .expect("cancellation woke the waiter");
    assert_eq!(woken["payload"]["outcome"], "cancelled");

    let second = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Again?", "inbox": "ext:ci"}),
        )
        .await;
    let second_id = second["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            CLI,
            "inbox.wait",
            json!({"questionId": second_id, "timeoutMs": 60000}),
        )
        .await;
    let waiter = fixture
        .actor
        .orchestration_waiters
        .take_by_id(fixture.actor.orchestration_waiters.last_id())
        .unwrap();
    // A reply stored without a wake-up still reaches the caller at the deadline.
    let mut reply = alera_core::runtime::NewOrchestrationMessage {
        from_handle: "codex-term".into(),
        to_handle: "ext:ci".into(),
        subject: "Re".into(),
        body: "Yes".into(),
        thread_id: Some(second_id.clone()),
        reply_to_id: Some(second_id.clone()),
        ..Default::default()
    };
    reply.workspace_id = Some("ws-1".into());
    fixture
        .actor
        .runtime_store
        .insert_orchestration_message(reply)
        .await
        .unwrap();
    fixture.actor.finish_inbox_wait_timeout(waiter, 60000).await;
    let response = fixture.take_response(CLI, wait_id).unwrap();
    assert_eq!(response["payload"]["outcome"], "answered");
}

#[tokio::test]
async fn inbox_listener_receives_any_new_message_after_its_cursor() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "claude-term", "body": "One", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"inbox": "ext:ci", "after": 0, "timeoutMs": 60000}),
        )
        .await;
    fixture.reply(&question_id, "First").await;
    let woken = fixture.take_response(DESKTOP, wait_id).unwrap();
    assert_eq!(woken["payload"]["outcome"], "message");
    let cursor = woken["payload"]["cursor"].as_i64().unwrap();
    let quiet = fixture
        .ok(
            CLI,
            "inbox.wait",
            json!({"inbox": "ext:ci", "after": cursor, "timeoutMs": 0}),
        )
        .await;
    assert_eq!(quiet["outcome"], "pending");
}

#[tokio::test]
async fn the_expiry_sweep_wakes_waiters_and_announces_the_change() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Soon?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    fixture.events_named(PHONE, "inboxChanged");
    sqlx::query(
        "UPDATE orchestrationMessages SET expires_at = datetime('now', '-1 minute') WHERE id = ?",
    )
    .bind(&question_id)
    .execute(fixture.actor.runtime_store.pool())
    .await
    .unwrap();
    fixture.actor.expire_inbox_questions().await;
    let woken = fixture
        .take_response(DESKTOP, wait_id)
        .expect("expiry woke the waiter");
    assert_eq!(woken["payload"]["outcome"], "expired");
    assert!(fixture.events_named(PHONE, "inboxChanged") >= 1);
}

#[tokio::test]
async fn the_sweep_wakes_a_waiter_whose_question_another_read_expired() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Soon?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    sqlx::query(
        "UPDATE orchestrationMessages SET expires_at = datetime('now', '-1 minute') WHERE id = ?",
    )
    .bind(&question_id)
    .execute(fixture.actor.runtime_store.pool())
    .await
    .unwrap();
    // A summary read runs the lazy expiry first, so the sweep finds no row to change.
    fixture.ok(PHONE, "inbox.summary", json!({})).await;
    assert!(fixture.take_response(DESKTOP, wait_id).is_none());
    fixture.actor.expire_inbox_questions().await;
    let woken = fixture
        .take_response(DESKTOP, wait_id)
        .expect("the sweep re-checked the parked wait");
    assert_eq!(woken["payload"]["outcome"], "expired");
}

#[tokio::test]
async fn a_wait_does_not_report_expiry_while_the_question_is_being_pasted() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "inbox.ask",
            json!({"to": "codex-term", "body": "Now?", "inbox": "ext:ci"}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    let wait_id = fixture
        .send(
            DESKTOP,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    fixture
        .actor
        .orchestration_delivery_in_flight
        .insert("codex-term".to_string());
    sqlx::query(
        "UPDATE orchestrationMessages SET expires_at = datetime('now', '-1 minute') WHERE id = ?",
    )
    .bind(&question_id)
    .execute(fixture.actor.runtime_store.pool())
    .await
    .unwrap();
    fixture.actor.expire_inbox_questions().await;
    assert!(
        fixture.take_response(DESKTOP, wait_id).is_none(),
        "expiry during a paste is not final"
    );
    fixture
        .actor
        .runtime_store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&question_id))
        .await
        .unwrap();
    fixture
        .actor
        .orchestration_delivery_in_flight
        .remove("codex-term");
    fixture.reply(&question_id, "Yes").await;
    let woken = fixture.take_response(DESKTOP, wait_id).unwrap();
    assert_eq!(woken["payload"]["outcome"], "answered");
}
