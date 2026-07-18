use alera_core::runtime::{
    OrchestrationDispatchStatus, OrchestrationMessage, OrchestrationMessageType,
    OrchestrationTaskStatus, RuntimeStore,
};
use anyhow::Result;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LifecycleReconciliation {
    Ignored,
    Completed {
        task_id: String,
        dispatch_id: String,
    },
    Failed {
        task_id: String,
        dispatch_id: String,
    },
    HeartbeatRecorded {
        dispatch_id: String,
    },
}

fn object_payload(message: &OrchestrationMessage) -> serde_json::Map<String, Value> {
    message
        .payload
        .as_deref()
        .and_then(|payload| serde_json::from_str::<Value>(payload).ok())
        .and_then(|value| match value {
            Value::Object(map) => Some(map),
            _ => None,
        })
        .unwrap_or_default()
}

fn payload_string(payload: &serde_json::Map<String, Value>, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn worker_done_indicates_failure(subject: &str) -> bool {
    let subject = subject.trim();
    subject.eq_ignore_ascii_case("failed")
        || subject
            .get(..7)
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case("failed:"))
}

fn failure_summary(message: &OrchestrationMessage) -> String {
    let body = message.body.trim();
    if body.is_empty() {
        message.subject.clone()
    } else {
        format!("{}: {body}", message.subject)
    }
}

/// Applies a lifecycle message (worker_done / heartbeat) to the store with
/// full authority checks. Non-lifecycle messages are ignored.
pub async fn reconcile_lifecycle_message(
    store: &RuntimeStore,
    message: &OrchestrationMessage,
    log: &mut impl FnMut(String),
) -> Result<LifecycleReconciliation> {
    match message.message_type {
        OrchestrationMessageType::WorkerDone => reconcile_worker_done(store, message, log).await,
        OrchestrationMessageType::Heartbeat => reconcile_heartbeat(store, message, log).await,
        _ => Ok(LifecycleReconciliation::Ignored),
    }
}

async fn reconcile_heartbeat(
    store: &RuntimeStore,
    message: &OrchestrationMessage,
    log: &mut impl FnMut(String),
) -> Result<LifecycleReconciliation> {
    let payload = object_payload(message);
    let Some(dispatch_id) = payload_string(&payload, "dispatchId") else {
        log(format!(
            "Heartbeat from {} missing dispatchId; ignored",
            message.from_handle
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    let Some(task_id) = payload_string(&payload, "taskId") else {
        log(format!(
            "Heartbeat from {} missing taskId; ignored",
            message.from_handle
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    let Some(dispatch) = store.orchestration_dispatch_by_id(&dispatch_id).await? else {
        log(format!(
            "Warning: heartbeat for unknown dispatch {dispatch_id}"
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    if dispatch.task_id != task_id {
        log(format!(
            "Warning: heartbeat dispatch {dispatch_id} belongs to {}, not {task_id}",
            dispatch.task_id
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }
    if dispatch.assignee_handle.as_deref() != Some(message.from_handle.as_str()) {
        log(format!(
            "Warning: heartbeat for dispatch {dispatch_id} came from {}, expected {}",
            message.from_handle,
            dispatch.assignee_handle.as_deref().unwrap_or("<unknown>")
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }
    // dispatchId-specific writes let the store ignore late heartbeats for
    // completed/failed retries without masking a newer hung dispatch.
    if store.record_orchestration_heartbeat(&dispatch_id).await? {
        Ok(LifecycleReconciliation::HeartbeatRecorded { dispatch_id })
    } else {
        log(format!(
            "Warning: heartbeat for inactive dispatch {dispatch_id} ignored"
        ));
        Ok(LifecycleReconciliation::Ignored)
    }
}

/// taskId alone is not a completion authority; retried tasks can have stale
/// worker_done messages racing the current active dispatch. All of taskId,
/// dispatchId, and the sender handle must match the active dispatch.
async fn reconcile_worker_done(
    store: &RuntimeStore,
    message: &OrchestrationMessage,
    log: &mut impl FnMut(String),
) -> Result<LifecycleReconciliation> {
    log(format!(
        "Worker done: {} - {}",
        message.from_handle, message.subject
    ));
    let payload = object_payload(message);
    let Some(task_id) = payload_string(&payload, "taskId") else {
        log(format!(
            "Warning: worker_done without taskId from {}",
            message.from_handle
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    let Some(dispatch_id) = payload_string(&payload, "dispatchId") else {
        log(format!(
            "Warning: worker_done without dispatchId from {}",
            message.from_handle
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    let Some(task) = store.orchestration_task_by_id(&task_id).await? else {
        log(format!("Warning: worker_done for unknown task {task_id}"));
        return Ok(LifecycleReconciliation::Ignored);
    };
    let Some(dispatch) = store.orchestration_dispatch_by_id(&dispatch_id).await? else {
        log(format!(
            "Warning: worker_done for unknown dispatch {dispatch_id}"
        ));
        return Ok(LifecycleReconciliation::Ignored);
    };
    if dispatch.task_id != task_id {
        log(format!(
            "Warning: worker_done dispatch {dispatch_id} belongs to {}, not {task_id}",
            dispatch.task_id
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }
    if dispatch.assignee_handle.as_deref() != Some(message.from_handle.as_str()) {
        log(format!(
            "Warning: worker_done for dispatch {dispatch_id} came from {}, expected {}",
            message.from_handle,
            dispatch.assignee_handle.as_deref().unwrap_or("<unknown>")
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }
    // send-time reconciliation can complete the pair before the coordinator
    // reads the message; the later read still needs to observe completion.
    if dispatch.status == OrchestrationDispatchStatus::Completed
        && task.status == OrchestrationTaskStatus::Completed
    {
        return Ok(LifecycleReconciliation::Completed {
            task_id,
            dispatch_id,
        });
    }
    if dispatch.status != OrchestrationDispatchStatus::Dispatched {
        log(format!(
            "Warning: worker_done for inactive dispatch {dispatch_id} ignored"
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }
    let active = store
        .active_orchestration_dispatch_for_task(&task_id)
        .await?;
    if active.map(|active| active.id) != Some(dispatch_id.clone())
        || task.status != OrchestrationTaskStatus::Dispatched
    {
        log(format!(
            "Warning: worker_done for stale dispatch {dispatch_id} ignored"
        ));
        return Ok(LifecycleReconciliation::Ignored);
    }

    if worker_done_indicates_failure(&message.subject) {
        let failed = store
            .fail_orchestration_dispatch(&dispatch_id, &failure_summary(message))
            .await?;
        log(format!(
            "Task {task_id} worker_done failed dispatch {dispatch_id} ({} failures)",
            failed.failure_count
        ));
        return Ok(LifecycleReconciliation::Failed {
            task_id,
            dispatch_id,
        });
    }

    let files_modified: Vec<String> = payload
        .get("filesModified")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    let result = serde_json::json!({
        "completedBy": message.from_handle,
        "filesModified": files_modified,
        "completedAt": message.created_at,
    })
    .to_string();
    store
        .update_orchestration_task_status(
            &task_id,
            OrchestrationTaskStatus::Completed,
            Some(&result),
        )
        .await?;
    log(format!("Task {task_id} completed"));
    Ok(LifecycleReconciliation::Completed {
        task_id,
        dispatch_id,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::runtime::{
        NewOrchestrationMessage, NewOrchestrationTask, OrchestrationMessagePriority,
    };

    async fn store() -> (tempfile::TempDir, RuntimeStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        (dir, store)
    }

    async fn insert_message(
        store: &RuntimeStore,
        from: &str,
        message_type: OrchestrationMessageType,
        payload: Option<Value>,
    ) -> OrchestrationMessage {
        insert_message_with_subject(store, from, message_type, "done", "summary", payload).await
    }

    async fn insert_message_with_subject(
        store: &RuntimeStore,
        from: &str,
        message_type: OrchestrationMessageType,
        subject: &str,
        body: &str,
        payload: Option<Value>,
    ) -> OrchestrationMessage {
        store
            .insert_orchestration_message(NewOrchestrationMessage {
                from_handle: from.to_string(),
                to_handle: "coord".to_string(),
                subject: subject.to_string(),
                body: body.to_string(),
                message_type,
                priority: OrchestrationMessagePriority::Normal,
                thread_id: None,
                payload: payload.map(|value| value.to_string()),
                run_id: None,
                workspace_id: Some("workspace_1".to_string()),
                task_id: None,
                dispatch_id: None,
                expires_at: None,
            })
            .await
            .unwrap()
    }

    async fn dispatched_task(store: &RuntimeStore, handle: &str) -> (String, String) {
        let task = store
            .create_orchestration_task(NewOrchestrationTask {
                spec: "work".to_string(),
                task_title: None,
                display_name: None,
                deps: vec![],
                parent_id: None,
                created_by_terminal_handle: None,
                run_id: None,
                workspace_id: "workspace_1".to_string(),
                coordinator_handle: "coord".to_string(),
                result_schema: None,
            })
            .await
            .unwrap();
        let dispatch = store
            .create_orchestration_dispatch(&task.id, handle)
            .await
            .unwrap();
        (task.id, dispatch.id)
    }

    #[tokio::test]
    async fn worker_done_with_full_authority_completes_task() {
        let (_dir, store) = store().await;
        let (task_id, dispatch_id) = dispatched_task(&store, "term_1").await;
        let message = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            Some(serde_json::json!({
                "taskId": task_id,
                "dispatchId": dispatch_id,
                "filesModified": ["a.rs", "b.rs"],
            })),
        )
        .await;

        let mut logs = Vec::new();
        let outcome = reconcile_lifecycle_message(&store, &message, &mut |line| logs.push(line))
            .await
            .unwrap();
        assert_eq!(
            outcome,
            LifecycleReconciliation::Completed {
                task_id: task_id.clone(),
                dispatch_id
            }
        );
        let task = store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(task.status, OrchestrationTaskStatus::Completed);
        assert!(task.result.unwrap().contains("a.rs"));
    }

    #[tokio::test]
    async fn failed_worker_done_consumes_dispatch_failure_instead_of_completing() {
        let (_dir, store) = store().await;
        let (task_id, dispatch_id) = dispatched_task(&store, "term_1").await;
        let message = insert_message_with_subject(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            "Failed: tests did not pass",
            "cargo test failed",
            Some(serde_json::json!({
                "taskId": task_id,
                "dispatchId": dispatch_id,
            })),
        )
        .await;

        let mut logs = Vec::new();
        let outcome = reconcile_lifecycle_message(&store, &message, &mut |line| logs.push(line))
            .await
            .unwrap();
        assert_eq!(
            outcome,
            LifecycleReconciliation::Failed {
                task_id: task_id.clone(),
                dispatch_id: dispatch_id.clone(),
            }
        );
        let dispatch = store
            .orchestration_dispatch_by_id(&dispatch_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(dispatch.status, OrchestrationDispatchStatus::Failed);
        assert_eq!(dispatch.failure_count, 1);
        assert!(dispatch.last_failure.unwrap().contains("cargo test failed"));
        let task = store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(task.status, OrchestrationTaskStatus::Ready);
    }

    #[tokio::test]
    async fn worker_done_missing_ids_is_ignored() {
        let (_dir, store) = store().await;
        let (task_id, _dispatch_id) = dispatched_task(&store, "term_1").await;

        let no_payload =
            insert_message(&store, "term_1", OrchestrationMessageType::WorkerDone, None).await;
        let missing_dispatch = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            Some(serde_json::json!({"taskId": task_id})),
        )
        .await;

        let mut sink = |_line: String| {};
        for message in [no_payload, missing_dispatch] {
            let outcome = reconcile_lifecycle_message(&store, &message, &mut sink)
                .await
                .unwrap();
            assert_eq!(outcome, LifecycleReconciliation::Ignored);
        }
        let task = store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(task.status, OrchestrationTaskStatus::Dispatched);
    }

    #[tokio::test]
    async fn worker_done_from_wrong_handle_is_ignored() {
        let (_dir, store) = store().await;
        let (task_id, dispatch_id) = dispatched_task(&store, "term_1").await;
        let message = insert_message(
            &store,
            "impostor",
            OrchestrationMessageType::WorkerDone,
            Some(serde_json::json!({"taskId": task_id, "dispatchId": dispatch_id})),
        )
        .await;

        let mut sink = |_line: String| {};
        let outcome = reconcile_lifecycle_message(&store, &message, &mut sink)
            .await
            .unwrap();
        assert_eq!(outcome, LifecycleReconciliation::Ignored);
    }

    #[tokio::test]
    async fn worker_done_for_stale_dispatch_is_ignored() {
        let (_dir, store) = store().await;
        let (task_id, first_dispatch) = dispatched_task(&store, "term_1").await;
        // First dispatch fails; a retry becomes the active dispatch.
        store
            .fail_orchestration_dispatch(&first_dispatch, "crash")
            .await
            .unwrap();
        store
            .create_orchestration_dispatch(&task_id, "term_2")
            .await
            .unwrap();

        let message = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            Some(serde_json::json!({"taskId": task_id, "dispatchId": first_dispatch})),
        )
        .await;
        let mut sink = |_line: String| {};
        let outcome = reconcile_lifecycle_message(&store, &message, &mut sink)
            .await
            .unwrap();
        assert_eq!(outcome, LifecycleReconciliation::Ignored);
        let task = store
            .orchestration_task_by_id(&task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(task.status, OrchestrationTaskStatus::Dispatched);
    }

    #[tokio::test]
    async fn worker_done_is_idempotent_after_completion() {
        let (_dir, store) = store().await;
        let (task_id, dispatch_id) = dispatched_task(&store, "term_1").await;
        let payload = serde_json::json!({"taskId": task_id, "dispatchId": dispatch_id});
        let first = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            Some(payload.clone()),
        )
        .await;
        let second = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::WorkerDone,
            Some(payload),
        )
        .await;

        let mut sink = |_line: String| {};
        reconcile_lifecycle_message(&store, &first, &mut sink)
            .await
            .unwrap();
        let replay = reconcile_lifecycle_message(&store, &second, &mut sink)
            .await
            .unwrap();
        assert_eq!(
            replay,
            LifecycleReconciliation::Completed {
                task_id,
                dispatch_id
            }
        );
    }

    #[tokio::test]
    async fn heartbeat_requires_current_dispatch_authority() {
        let (_dir, store) = store().await;
        let (task_id, dispatch_id) = dispatched_task(&store, "term_1").await;

        let missing =
            insert_message(&store, "term_1", OrchestrationMessageType::Heartbeat, None).await;
        let missing_task = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::Heartbeat,
            Some(serde_json::json!({"dispatchId": dispatch_id})),
        )
        .await;
        let wrong_task = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::Heartbeat,
            Some(serde_json::json!({"taskId": "other_task", "dispatchId": dispatch_id})),
        )
        .await;
        let wrong_handle = insert_message(
            &store,
            "term_2",
            OrchestrationMessageType::Heartbeat,
            Some(serde_json::json!({"taskId": task_id, "dispatchId": dispatch_id})),
        )
        .await;
        let valid = insert_message(
            &store,
            "term_1",
            OrchestrationMessageType::Heartbeat,
            Some(serde_json::json!({"taskId": task_id, "dispatchId": dispatch_id})),
        )
        .await;

        let mut sink = |_line: String| {};
        for message in [missing, missing_task, wrong_task, wrong_handle] {
            assert_eq!(
                reconcile_lifecycle_message(&store, &message, &mut sink)
                    .await
                    .unwrap(),
                LifecycleReconciliation::Ignored
            );
        }
        assert_eq!(
            reconcile_lifecycle_message(&store, &valid, &mut sink)
                .await
                .unwrap(),
            LifecycleReconciliation::HeartbeatRecorded { dispatch_id }
        );
    }

    #[tokio::test]
    async fn non_lifecycle_messages_are_ignored() {
        let (_dir, store) = store().await;
        let message =
            insert_message(&store, "term_1", OrchestrationMessageType::Status, None).await;
        let mut sink = |_line: String| {};
        assert_eq!(
            reconcile_lifecycle_message(&store, &message, &mut sink)
                .await
                .unwrap(),
            LifecycleReconciliation::Ignored
        );
    }
}
