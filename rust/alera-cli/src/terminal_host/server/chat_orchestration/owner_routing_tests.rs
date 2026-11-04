use alera_core::runtime::AutomationState;
use serde_json::{json, Value};

use super::test_support::{error_code, human, TestHarness};
use crate::terminal_host::server::chat_orchestration_remote::handle_owner_orchestration;

const PR: &str = "https://github.com/acme/app/pull/7";

fn every_fifteen_minutes(chat_id: &str) -> Value {
    json!({
        "prompt": "Check the deploy.",
        "schedule": {"type": "interval", "everyMs": 900_000},
        "chatId": chat_id,
        "requestId": "schedule-1",
    })
}

#[tokio::test]
async fn a_remote_chats_scheduled_tasks_live_on_its_host() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-b", "auto").await;
    let person = human("desktop");
    let task = harness
        .service
        .handle("scheduleTask", &every_fifteen_minutes(&chat), &person)
        .await
        .unwrap();
    assert_eq!(task["boundChatId"], chat.as_str());
    assert_eq!(task["workspaceId"], "ws-b");
    let id = task["scheduledTaskId"].as_str().unwrap().to_owned();
    // A retried save with the same request id answers the same task.
    let again = harness
        .service
        .handle("scheduleTask", &every_fifteen_minutes(&chat), &person)
        .await
        .unwrap();
    assert_eq!(again["scheduledTaskId"], id.as_str());
    let satellite = harness.satellites.store("ws-b").await;
    assert_eq!(satellite.list_automations(false).await.unwrap().len(), 1);
    assert!(harness
        .store
        .list_automations(false)
        .await
        .unwrap()
        .is_empty());

    let listed = harness
        .service
        .handle("listScheduledTasks", &json!({"chatId": chat}), &person)
        .await
        .unwrap();
    assert_eq!(listed["tasks"].as_array().unwrap().len(), 1);
    // Without a chat, a person lists this host's tasks only.
    let here = harness
        .service
        .handle("listScheduledTasks", &json!({}), &person)
        .await
        .unwrap();
    assert!(here["tasks"].as_array().unwrap().is_empty());

    let ran = harness
        .service
        .handle(
            "runScheduledTaskNow",
            &json!({"scheduledTaskId": id, "chatId": chat}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(ran["runId"], format!("run-{id}"));
    let deleted = harness
        .service
        .handle(
            "deleteScheduledTask",
            &json!({"scheduledTaskId": id, "chatId": chat}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(deleted["state"], "trashed");
    assert_eq!(
        satellite.find_automation(&id).await.unwrap().unwrap().state,
        AutomationState::Trashed
    );
    harness.finish().await;
}

#[tokio::test]
async fn a_remote_chats_pull_requests_live_on_its_host() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-b", "auto").await;
    let person = human("mobile:phone");
    let linked = harness
        .service
        .handle(
            "linkPullRequest",
            &json!({"chatId": chat, "url": PR}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(linked["number"], 7);
    assert_eq!(linked["alreadyLinked"], false);
    let watched = harness
        .service
        .handle(
            "watchPullRequest",
            &json!({"chatId": chat, "url": PR}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(watched["watching"], true);
    let satellite = harness.satellites.store("ws-b").await;
    let rows = satellite
        .list_agent_chat_pull_requests(&chat)
        .await
        .unwrap();
    assert_eq!(rows.len(), 1);
    assert!(rows[0].watching);
    assert!(harness
        .store
        .list_agent_chat_pull_requests(&chat)
        .await
        .unwrap()
        .is_empty());
    let listed = harness
        .service
        .handle("listPullRequests", &json!({"chatId": chat}), &person)
        .await
        .unwrap();
    assert_eq!(listed["pullRequests"][0]["watching"], true);
    harness
        .service
        .handle(
            "unwatchPullRequest",
            &json!({"chatId": chat, "url": PR}),
            &person,
        )
        .await
        .unwrap();
    let unlinked = harness
        .service
        .handle(
            "unlinkPullRequest",
            &json!({"chatId": chat, "url": PR}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(unlinked["wasLinked"], true);
    assert!(satellite
        .list_agent_chat_pull_requests(&chat)
        .await
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn an_older_satellite_answers_not_supported_on_this_host() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-b", "auto").await;
    let person = human("desktop");
    harness
        .satellites
        .advertise(&[crate::chat_schedule_commands::SCHEDULES_CAPABILITY]);
    let error = harness
        .service
        .handle(
            "linkPullRequest",
            &json!({"chatId": chat, "url": PR}),
            &person,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "unsupported");
    assert!(error.wire_message().contains("not supported on this host"));
    // The flag it does advertise still forwards.
    harness
        .service
        .handle("scheduleTask", &every_fifteen_minutes(&chat), &person)
        .await
        .unwrap();
    harness.satellites.advertise(&[]);
    for (verb, payload) in [
        ("scheduleTask", every_fifteen_minutes(&chat)),
        ("listScheduledTasks", json!({"chatId": chat})),
        ("listPullRequests", json!({"chatId": chat})),
    ] {
        let error = harness
            .service
            .handle(verb, &payload, &person)
            .await
            .unwrap_err();
        assert_eq!(error_code(&error), "unsupported", "{verb}");
        assert!(
            error.wire_message().contains("not supported on this host"),
            "{verb}"
        );
    }
    harness.finish().await;
}

#[tokio::test]
async fn a_satellite_runs_only_owner_scoped_verbs_for_the_hub() {
    let harness = TestHarness::new().await;
    let caller = json!({"scope": "desktop", "actor": "desktop", "mobile": false});
    let refused = handle_owner_orchestration(
        Some(harness.service.clone()),
        &json!({"operation": "orchestration", "verb": "delegate", "payload": {}, "caller": caller}),
    )
    .await
    .unwrap_err();
    assert_eq!(error_code(&refused), "chat_scope_denied");
    let unavailable = handle_owner_orchestration(
        None,
        &json!({"operation": "orchestration", "verb": "listPullRequests", "payload": {}, "caller": caller}),
    )
    .await
    .unwrap_err();
    assert_eq!(error_code(&unavailable), "unsupported");
    harness.finish().await;
}

#[test]
fn phones_may_call_the_owner_scoped_verbs() {
    for verb in [
        "scheduleTask",
        "listScheduledTasks",
        "deleteScheduledTask",
        "runScheduledTaskNow",
        "linkPullRequest",
        "unlinkPullRequest",
        "listPullRequests",
        "watchPullRequest",
        "unwatchPullRequest",
    ] {
        assert!(super::is_owner_scoped_verb(verb));
        assert!(
            super::super::mobile_gateway_surface::mobile_request_allowed(&format!(
                "chatOrchestration.{verb}"
            )),
            "{verb}"
        );
    }
}
