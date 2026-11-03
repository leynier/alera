use std::sync::{Arc, Mutex};

use alera_core::runtime::{AutomationState, RuntimeStore};
use async_trait::async_trait;
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::schedules::{ScheduleHost, ScheduleOp, CHILD_CANNOT_SCHEDULE};
use super::service::ChatOrchestrationService;
use super::test_support::{error_code, human, TestHarness};
use crate::terminal_host::host_error::HostResult;

/// Saves and trashes in the store like the actor does, and records runs.
struct StoreHost {
    store: RuntimeStore,
    runs: Mutex<Vec<String>>,
}

#[async_trait]
impl ScheduleHost for StoreHost {
    async fn apply(&self, op: ScheduleOp) -> HostResult<Value> {
        Ok(match op {
            ScheduleOp::Save {
                definition,
                state,
                actor,
            } => {
                let saved = self
                    .store
                    .upsert_automation(*definition, actor.clone())
                    .await
                    .unwrap();
                match state.filter(|state| *state != saved.state) {
                    Some(state) => json!(self
                        .store
                        .set_automation_state(&saved.id, state, actor, None)
                        .await
                        .unwrap()),
                    None => json!(saved),
                }
            }
            ScheduleOp::Trash { id, actor } => json!(self
                .store
                .set_automation_state(&id, AutomationState::Trashed, actor, None)
                .await
                .unwrap()),
            ScheduleOp::RunNow { id, .. } => {
                self.runs.lock().unwrap().push(id);
                json!({"id": "run-1", "number": 1, "status": "dispatched", "chatId": "run-chat"})
            }
        })
    }
}

fn with_host(harness: &TestHarness) -> (ChatOrchestrationService, Arc<StoreHost>) {
    let host = Arc::new(StoreHost {
        store: harness.store.clone(),
        runs: Mutex::default(),
    });
    (harness.service.clone().with_schedules(host.clone()), host)
}

fn every_fifteen_minutes() -> Value {
    json!({"prompt": "Check the deploy.", "schedule": {"type": "interval", "everyMs": 900_000}})
}

#[tokio::test]
async fn an_agent_schedules_into_its_own_chat_at_most_at_its_mode() {
    let harness = TestHarness::new().await;
    let (service, _) = with_host(&harness);
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "live", "Schedule it.").await;
    let agent = harness.agent(&chat).await;

    let task = service
        .handle("scheduleTask", &every_fifteen_minutes(), &agent)
        .await
        .unwrap();
    assert_eq!(task["boundChatId"], chat.as_str());
    assert_eq!(task["runtimeModeCeiling"], "auto");
    assert_eq!(task["projectId"], "project-a");
    assert_eq!(task["enabled"], true);
    assert_eq!(task["schedule"]["everyMs"], 900_000);
    assert_eq!(task["lastRunStatus"], "never");
    assert_eq!(task["title"], "Check the deploy.");
    assert!(task["nextRunAt"].is_string());
    let id = task["scheduledTaskId"].as_str().unwrap().to_owned();

    let listed = service
        .handle("listScheduledTasks", &json!({}), &agent)
        .await
        .unwrap();
    assert_eq!(listed["tasks"].as_array().unwrap().len(), 1);

    let paused = service
        .handle(
            "scheduleTask",
            &json!({"scheduledTaskId": id, "enabled": false, "bindToCurrentChat": false}),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(paused["state"], "paused");
    assert!(paused["nextRunAt"].is_null());
    assert!(paused["boundChatId"].is_null());
    assert_eq!(paused["prompt"], "Check the deploy.");

    // A person schedules for a full-access chat; the auto agent's later
    // update lowers the ceiling to its own mode.
    let full = harness.create_chat("ws-a", "full-access").await;
    let mut payload = every_fifteen_minutes();
    payload["chatId"] = json!(full);
    let by_person = service
        .handle("scheduleTask", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(by_person["runtimeModeCeiling"], "full-access");
    let lowered = service
        .handle(
            "scheduleTask",
            &json!({"scheduledTaskId": by_person["scheduledTaskId"], "title": "Renamed"}),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(lowered["runtimeModeCeiling"], "auto");
    assert_eq!(lowered["title"], "Renamed");
    harness.finish().await;
}

#[tokio::test]
async fn a_delegated_child_may_only_list_scheduled_tasks() {
    let harness = TestHarness::new().await;
    let (service, _) = with_host(&harness);
    let parent = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&parent, "live", "Delegate.").await;
    let parent_agent = harness.agent(&parent).await;
    let task = service
        .handle("scheduleTask", &every_fifteen_minutes(), &parent_agent)
        .await
        .unwrap();
    let response = service
        .handle(
            "delegate",
            &delegate_payload(
                "schedule-child",
                json!({"workspace": {"workspaceId": "ws-a"}}),
            ),
            &parent_agent,
        )
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    let child_agent = harness.agent(&child).await;

    let refused = service
        .handle("scheduleTask", &every_fifteen_minutes(), &child_agent)
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "childCannotSchedule");
    assert!(refused.wire_message().contains(CHILD_CANNOT_SCHEDULE));
    let id = json!({"scheduledTaskId": task["scheduledTaskId"]});
    let refused = service
        .handle("deleteScheduledTask", &id, &child_agent)
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "childCannotSchedule");
    let listed = service
        .handle("listScheduledTasks", &json!({}), &child_agent)
        .await
        .unwrap();
    assert_eq!(listed["tasks"].as_array().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn run_now_needs_a_full_access_chat_in_the_default_mode() {
    let harness = TestHarness::new().await;
    let (service, host) = with_host(&harness);
    let limited = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&limited, "live", "Run it.").await;
    let limited_agent = harness.agent(&limited).await;
    let task = service
        .handle("scheduleTask", &every_fifteen_minutes(), &limited_agent)
        .await
        .unwrap();
    let id = json!({"scheduledTaskId": task["scheduledTaskId"]});
    let refused = service
        .handle("runScheduledTaskNow", &id, &limited_agent)
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "runNowNotAllowed");
    assert!(host.runs.lock().unwrap().is_empty());

    let full = harness.create_chat("ws-a", "full-access").await;
    harness.send_human(&full, "live-full", "Run it.").await;
    let full_agent = harness.agent(&full).await;
    let started = service
        .handle("runScheduledTaskNow", &id, &full_agent)
        .await
        .unwrap();
    assert_eq!(started["runId"], "run-1");
    assert_eq!(started["chatId"], "run-chat");
    assert_eq!(host.runs.lock().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn delete_moves_the_task_to_the_trash_and_out_of_the_list() {
    let harness = TestHarness::new().await;
    let (service, _) = with_host(&harness);
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "live", "Delete it.").await;
    let agent = harness.agent(&chat).await;
    let task = service
        .handle("scheduleTask", &every_fifteen_minutes(), &agent)
        .await
        .unwrap();
    let id = task["scheduledTaskId"].as_str().unwrap().to_owned();
    let deleted = service
        .handle(
            "deleteScheduledTask",
            &json!({"scheduledTaskId": id}),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(deleted["state"], "trashed");
    let stored = harness.store.find_automation(&id).await.unwrap().unwrap();
    assert_eq!(stored.state, AutomationState::Trashed);
    assert_eq!(stored.state_before_trash, Some(AutomationState::Active));
    let listed = service
        .handle("listScheduledTasks", &json!({}), &agent)
        .await
        .unwrap();
    assert!(listed["tasks"].as_array().unwrap().is_empty());
    let missing = service
        .handle(
            "deleteScheduledTask",
            &json!({"scheduledTaskId": id}),
            &agent,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&missing), "scheduledTaskNotFound");
    harness.finish().await;
}

#[tokio::test]
async fn webhook_schedules_are_refused_and_a_person_must_name_a_chat() {
    let harness = TestHarness::new().await;
    let (service, _) = with_host(&harness);
    let webhook = service
        .handle(
            "scheduleTask",
            &json!({"prompt": "Triage", "schedule": {"type": "webhook"}}),
            &human("desktop"),
        )
        .await
        .unwrap_err();
    assert!(webhook.wire_message().contains("no inbound webhook"));
    let unnamed = service
        .handle("scheduleTask", &every_fifteen_minutes(), &human("desktop"))
        .await
        .unwrap_err();
    assert!(unnamed.wire_message().contains("chatId is required"));
    harness.finish().await;
}
