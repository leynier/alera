use super::*;

mod message_limits;
mod support;
mod v2_contract;

use support::{message, store, task};

#[tokio::test]
async fn read_and_delivered_are_independent() {
    let (_dir, store) = store().await;
    let msg = store
        .insert_orchestration_message(message("a", "b", OrchestrationMessageType::Status))
        .await
        .unwrap();

    // Delivering does not consume the unread state.
    store
        .mark_orchestration_messages_delivered(std::slice::from_ref(&msg.id))
        .await
        .unwrap();
    let unread = store
        .unread_orchestration_messages("b", None)
        .await
        .unwrap();
    assert_eq!(unread.len(), 1);
    // But it is excluded from the push-on-idle queue.
    let undelivered = store
        .undelivered_unread_orchestration_messages("b")
        .await
        .unwrap();
    assert!(undelivered.is_empty());

    // Reading does not clear delivery state either.
    store
        .mark_orchestration_messages_read(std::slice::from_ref(&msg.id))
        .await
        .unwrap();
    let refreshed = store
        .orchestration_message_by_id(&msg.id)
        .await
        .unwrap()
        .unwrap();
    assert!(refreshed.read);
    assert!(refreshed.delivered_at.is_some());
}

#[tokio::test]
async fn unread_filter_by_type_and_order() {
    let (_dir, store) = store().await;
    store
        .insert_orchestration_message(message("a", "coord", OrchestrationMessageType::Status))
        .await
        .unwrap();
    store
        .insert_orchestration_message(message("a", "coord", OrchestrationMessageType::WorkerDone))
        .await
        .unwrap();
    store
        .insert_orchestration_message(message("a", "other", OrchestrationMessageType::WorkerDone))
        .await
        .unwrap();

    let filtered = store
        .unread_orchestration_messages("coord", Some(&[OrchestrationMessageType::WorkerDone]))
        .await
        .unwrap();
    assert_eq!(filtered.len(), 1);
    assert_eq!(
        filtered[0].message_type,
        OrchestrationMessageType::WorkerDone
    );

    let all = store
        .unread_orchestration_messages("coord", None)
        .await
        .unwrap();
    assert_eq!(all.len(), 2);
    assert!(all[0].sequence < all[1].sequence);

    let historical = store
        .all_orchestration_messages_for_handle(
            "coord",
            Some(&[OrchestrationMessageType::WorkerDone]),
            100,
        )
        .await
        .unwrap();
    assert_eq!(historical.len(), 1);
    assert_eq!(
        historical[0].message_type,
        OrchestrationMessageType::WorkerDone
    );
}

#[tokio::test]
async fn coordinator_unread_messages_include_only_actionable_types() {
    let (_dir, store) = store().await;
    store
        .insert_orchestration_message(message("a", "coord", OrchestrationMessageType::Status))
        .await
        .unwrap();
    store
        .insert_orchestration_message(message(
            "a",
            "coord",
            OrchestrationMessageType::DecisionGate,
        ))
        .await
        .unwrap();
    let gate = store
        .insert_orchestration_message(NewOrchestrationMessage {
            payload: Some(serde_json::json!({"taskId": "task_1"}).to_string()),
            ..message("a", "coord", OrchestrationMessageType::DecisionGate)
        })
        .await
        .unwrap();
    let done = store
        .insert_orchestration_message(message("a", "coord", OrchestrationMessageType::WorkerDone))
        .await
        .unwrap();

    let actionable = store
        .unread_orchestration_coordinator_messages("coord")
        .await
        .unwrap();
    assert_eq!(
        actionable
            .iter()
            .map(|message| message.id.as_str())
            .collect::<Vec<_>>(),
        vec![gate.id.as_str(), done.id.as_str()]
    );

    let all_unread = store
        .unread_orchestration_messages("coord", None)
        .await
        .unwrap();
    assert_eq!(all_unread.len(), 4);
}

#[tokio::test]
async fn thread_messages_scoped_to_recipient_after_sequence() {
    let (_dir, store) = store().await;
    let question = store
        .insert_orchestration_message(NewOrchestrationMessage {
            thread_id: Some("thread_1".to_string()),
            ..message("worker", "coord", OrchestrationMessageType::DecisionGate)
        })
        .await
        .unwrap();
    // Reply addressed to worker in the same thread.
    store
        .insert_orchestration_message(NewOrchestrationMessage {
            thread_id: Some("thread_1".to_string()),
            ..message("coord", "worker", OrchestrationMessageType::Status)
        })
        .await
        .unwrap();
    // Unrelated message in the thread addressed elsewhere.
    store
        .insert_orchestration_message(NewOrchestrationMessage {
            thread_id: Some("thread_1".to_string()),
            ..message("coord", "someone", OrchestrationMessageType::Status)
        })
        .await
        .unwrap();

    let replies = store
        .orchestration_thread_messages_for("thread_1", "worker", question.sequence)
        .await
        .unwrap();
    assert_eq!(replies.len(), 1);
    assert_eq!(replies[0].to_handle, "worker");
}

#[tokio::test]
async fn task_initial_status_derived_from_deps() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    assert_eq!(root.status, OrchestrationTaskStatus::Ready);

    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    assert_eq!(child.status, OrchestrationTaskStatus::Pending);
}

#[tokio::test]
async fn task_with_unknown_dep_is_rejected() {
    let (_dir, store) = store().await;
    let error = store
        .create_orchestration_task(task("child", vec!["missing_task".to_string()]))
        .await
        .unwrap_err();

    assert!(error
        .to_string()
        .contains("unknown orchestration task dependency: missing_task"));
    assert!(store
        .list_orchestration_tasks(None)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn task_with_already_completed_deps_starts_ready() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    store
        .update_orchestration_task_status(&root.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();

    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    assert_eq!(child.status, OrchestrationTaskStatus::Ready);
}

#[tokio::test]
async fn completing_task_promotes_dependents_when_all_deps_done() {
    let (_dir, store) = store().await;
    let a = store
        .create_orchestration_task(task("a", vec![]))
        .await
        .unwrap();
    let b = store
        .create_orchestration_task(task("b", vec![]))
        .await
        .unwrap();
    let c = store
        .create_orchestration_task(task("c", vec![a.id.clone(), b.id.clone()]))
        .await
        .unwrap();

    store
        .update_orchestration_task_status(&a.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    let c_after_first = store
        .orchestration_task_by_id(&c.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(c_after_first.status, OrchestrationTaskStatus::Pending);

    store
        .update_orchestration_task_status(&b.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    let c_after_both = store
        .orchestration_task_by_id(&c.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(c_after_both.status, OrchestrationTaskStatus::Ready);
}

#[tokio::test]
async fn failed_dependency_marks_pending_dependents_failed() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    let grandchild = store
        .create_orchestration_task(task("grandchild", vec![child.id.clone()]))
        .await
        .unwrap();

    store
        .update_orchestration_task_status(&root.id, OrchestrationTaskStatus::Failed, Some("boom"))
        .await
        .unwrap();
    let child = store
        .orchestration_task_by_id(&child.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(child.status, OrchestrationTaskStatus::Failed);
    let expected_result = format!("dependency failed: {}", root.id);
    assert_eq!(child.result.as_deref(), Some(expected_result.as_str()));
    let grandchild = store
        .orchestration_task_by_id(&grandchild.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(grandchild.status, OrchestrationTaskStatus::Failed);
    let expected_result = format!("dependency failed: {}", child.id);
    assert_eq!(grandchild.result.as_deref(), Some(expected_result.as_str()));
}

#[tokio::test]
async fn task_with_already_failed_dep_starts_failed() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    store
        .update_orchestration_task_status(&root.id, OrchestrationTaskStatus::Failed, Some("boom"))
        .await
        .unwrap();

    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    assert_eq!(child.status, OrchestrationTaskStatus::Failed);
}

#[tokio::test]
async fn completing_task_closes_active_dispatch() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("work", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();
    assert_eq!(dispatch.status, OrchestrationDispatchStatus::Dispatched);

    store
        .update_orchestration_task_status(&created.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    let refreshed = store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(refreshed.status, OrchestrationDispatchStatus::Completed);
    assert!(refreshed.completed_at.is_some());
}

#[tokio::test]
async fn resetting_dispatched_task_to_ready_closes_active_dispatch() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("work", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    let updated = store
        .update_orchestration_task_status(&created.id, OrchestrationTaskStatus::Ready, None)
        .await
        .unwrap();
    assert_eq!(updated.status, OrchestrationTaskStatus::Ready);

    let refreshed = store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(refreshed.status, OrchestrationDispatchStatus::Failed);
    assert_eq!(
        refreshed.last_failure.as_deref(),
        Some("task status changed to ready")
    );
    assert!(refreshed.completed_at.is_some());
    assert!(store
        .active_orchestration_dispatch_for_task(&created.id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn dispatch_requires_ready_task_and_free_terminal() {
    let (_dir, store) = store().await;
    let ready = store
        .create_orchestration_task(task("ready", vec![]))
        .await
        .unwrap();
    let dep = store
        .create_orchestration_task(task("dep", vec![ready.id.clone()]))
        .await
        .unwrap();

    // Pending task cannot be dispatched.
    assert!(store
        .create_orchestration_dispatch(&dep.id, "term_1")
        .await
        .is_err());

    store
        .create_orchestration_dispatch(&ready.id, "term_1")
        .await
        .unwrap();

    // Same terminal cannot take a second active dispatch.
    let other = store
        .create_orchestration_task(task("other", vec![]))
        .await
        .unwrap();
    let error = store
        .create_orchestration_dispatch(&other.id, "term_1")
        .await
        .unwrap_err();
    assert!(error.to_string().contains("active dispatch"));
}

#[tokio::test]
async fn circuit_breaker_carries_failures_across_retries() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("flaky", vec![]))
        .await
        .unwrap();

    // Failure 1: task returns to ready, dispatch failed.
    let first = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();
    let failed_first = store
        .fail_orchestration_dispatch(&first.id, "boom")
        .await
        .unwrap();
    assert_eq!(failed_first.status, OrchestrationDispatchStatus::Failed);
    assert_eq!(failed_first.failure_count, 1);
    let task_after_first = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task_after_first.status, OrchestrationTaskStatus::Ready);
    assert!(task_after_first.completed_at.is_none());

    // Failure 2 on a different terminal: count carried forward.
    let second = store
        .create_orchestration_dispatch(&created.id, "term_2")
        .await
        .unwrap();
    assert_eq!(second.failure_count, 1);
    let failed_second = store
        .fail_orchestration_dispatch(&second.id, "boom")
        .await
        .unwrap();
    assert_eq!(failed_second.failure_count, 2);

    // Failure 3: circuit breaks and the task fails.
    let third = store
        .create_orchestration_dispatch(&created.id, "term_3")
        .await
        .unwrap();
    let failed_third = store
        .fail_orchestration_dispatch(&third.id, "boom")
        .await
        .unwrap();
    assert_eq!(
        failed_third.status,
        OrchestrationDispatchStatus::CircuitBroken
    );
    assert_eq!(
        failed_third.failure_count,
        ORCHESTRATION_CIRCUIT_BREAKER_THRESHOLD
    );
    let task_after_third = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task_after_third.status, OrchestrationTaskStatus::Failed);
    assert!(task_after_third.completed_at.is_some());
}

#[tokio::test]
async fn heartbeat_recorded_only_while_dispatched() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("hb", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    assert!(store
        .record_orchestration_heartbeat(&dispatch.id)
        .await
        .unwrap());

    store
        .update_orchestration_task_status(&created.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    // Straggler heartbeat from a completed dispatch is ignored.
    assert!(!store
        .record_orchestration_heartbeat(&dispatch.id)
        .await
        .unwrap());
}

#[tokio::test]
async fn stale_dispatch_query_uses_heartbeat_and_dispatch_time() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("stale", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    // Threshold in the future: the dispatch (created now) is stale.
    let stale = store
        .stale_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap();
    assert_eq!(stale.len(), 1);
    assert_eq!(stale[0].id, dispatch.id);

    // Threshold in the past: nothing stale.
    let fresh = store
        .stale_orchestration_dispatches("2000-01-01 00:00:00")
        .await
        .unwrap();
    assert!(fresh.is_empty());
}

#[tokio::test]
async fn gate_blocks_task_and_resolution_returns_it_to_ready() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("gated", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    let gate = store
        .create_orchestration_gate(
            &created.id,
            "Proceed?",
            &["yes".to_string(), "no".to_string()],
        )
        .await
        .unwrap();
    assert_eq!(gate.status, OrchestrationGateStatus::Pending);

    let blocked = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(blocked.status, OrchestrationTaskStatus::Blocked);
    let released = store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(released.status, OrchestrationDispatchStatus::Completed);
    assert!(store
        .complete_orchestration_dispatch(&dispatch.id, "term_1", r#"{"summary":"late"}"#)
        .await
        .is_err());
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Blocked
    );

    let resolved = store
        .resolve_orchestration_gate(&gate.id, "yes")
        .await
        .unwrap();
    assert_eq!(resolved.status, OrchestrationGateStatus::Resolved);
    assert_eq!(resolved.resolution.as_deref(), Some("yes"));
    let ready = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(ready.status, OrchestrationTaskStatus::Ready);

    // A gate cannot be resolved twice.
    assert!(store
        .resolve_orchestration_gate(&gate.id, "no")
        .await
        .is_err());
}

#[tokio::test]
async fn resolving_stale_gate_does_not_reopen_terminal_task() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("gated", vec![]))
        .await
        .unwrap();
    let _dispatch = store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();
    let gate = store
        .create_orchestration_gate(&created.id, "Proceed?", &["yes".to_string()])
        .await
        .unwrap();

    store
        .update_orchestration_task_status(
            &created.id,
            OrchestrationTaskStatus::Completed,
            Some("manual completion"),
        )
        .await
        .unwrap();

    let resolved = store
        .resolve_orchestration_gate(&gate.id, "yes")
        .await
        .unwrap();
    assert_eq!(resolved.status, OrchestrationGateStatus::Resolved);
    let completed = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(completed.status, OrchestrationTaskStatus::Completed);
    assert_eq!(completed.result.as_deref(), Some("manual completion"));
}

#[tokio::test]
async fn gate_rejects_inactive_or_terminal_tasks() {
    let (_dir, store) = store().await;
    let dep = store
        .create_orchestration_task(task("dep", vec![]))
        .await
        .unwrap();
    let pending = store
        .create_orchestration_task(task("pending", vec![dep.id.clone()]))
        .await
        .unwrap();
    assert!(store
        .create_orchestration_gate(&pending.id, "Proceed?", &[])
        .await
        .is_err());

    store
        .update_orchestration_task_status(&dep.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    store
        .update_orchestration_task_status(&pending.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();
    assert!(store
        .create_orchestration_gate(&pending.id, "Proceed?", &[])
        .await
        .is_err());

    let ready = store
        .create_orchestration_task(task("ready", vec![]))
        .await
        .unwrap();
    store
        .create_orchestration_gate(&ready.id, "Pause?", &[])
        .await
        .unwrap();
}

#[tokio::test]
async fn gates_with_same_timestamp_keep_creation_order() {
    let (_dir, store) = store().await;
    let task = store
        .create_orchestration_task(task("needs decisions", vec![]))
        .await
        .unwrap();

    let first = store
        .create_orchestration_gate(&task.id, "first?", &[])
        .await
        .unwrap();
    store
        .resolve_orchestration_gate(&first.id, "first answer")
        .await
        .unwrap();
    let second = store
        .create_orchestration_gate(&task.id, "second?", &[])
        .await
        .unwrap();
    store
        .resolve_orchestration_gate(&second.id, "second answer")
        .await
        .unwrap();

    let timestamp = "2026-07-05 12:00:00";
    sqlx::query(
        "UPDATE orchestrationDecisionGates \
         SET id = 'gate_z_old', created_at = ?, resolved_at = ? WHERE id = ?",
    )
    .bind(timestamp)
    .bind(timestamp)
    .bind(&first.id)
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "UPDATE orchestrationDecisionGates \
         SET id = 'gate_a_new', created_at = ?, resolved_at = ? WHERE id = ?",
    )
    .bind(timestamp)
    .bind(timestamp)
    .bind(&second.id)
    .execute(store.pool())
    .await
    .unwrap();

    let gates = store
        .list_orchestration_gates(Some(&task.id), Some(OrchestrationGateStatus::Resolved))
        .await
        .unwrap();
    assert_eq!(gates[0].id, "gate_z_old");
    assert_eq!(gates[1].id, "gate_a_new");
    assert_eq!(
        gates.last().unwrap().resolution.as_deref(),
        Some("second answer")
    );
}

#[tokio::test]
async fn single_active_coordinator_run() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("build things", Some("coord"), 2000)
        .await
        .unwrap();
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Running);

    assert!(store
        .create_orchestration_coordinator_run("another", None, 2000)
        .await
        .is_err());

    store
        .finish_orchestration_coordinator_run(&run.id, OrchestrationCoordinatorStatus::Completed)
        .await
        .unwrap();
    assert!(store
        .active_orchestration_coordinator_run()
        .await
        .unwrap()
        .is_none());

    // A new run can start once the previous one finished.
    store
        .create_orchestration_coordinator_run("next", None, 2000)
        .await
        .unwrap();
}

#[tokio::test]
async fn list_tasks_includes_active_dispatch_fields() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("visible", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "term_9")
        .await
        .unwrap();

    let tasks = store.list_orchestration_tasks(None).await.unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].assignee_handle.as_deref(), Some("term_9"));
    assert_eq!(tasks[0].dispatch_id.as_deref(), Some(dispatch.id.as_str()));

    let ready_only = store
        .list_orchestration_tasks(Some(OrchestrationTaskStatus::Ready))
        .await
        .unwrap();
    assert!(ready_only.is_empty());
}

#[tokio::test]
async fn reset_scopes_tasks_and_messages_independently() {
    let (_dir, store) = store().await;
    store
        .insert_orchestration_message(message("a", "b", OrchestrationMessageType::Status))
        .await
        .unwrap();
    let created = store
        .create_orchestration_task(task("t", vec![]))
        .await
        .unwrap();
    store
        .create_orchestration_dispatch(&created.id, "term_1")
        .await
        .unwrap();

    store.reset_orchestration_tasks().await.unwrap();
    assert!(store
        .list_orchestration_tasks(None)
        .await
        .unwrap()
        .is_empty());
    assert_eq!(store.orchestration_inbox(10).await.unwrap().len(), 1);

    store.reset_orchestration_messages().await.unwrap();
    assert!(store.orchestration_inbox(10).await.unwrap().is_empty());
}
