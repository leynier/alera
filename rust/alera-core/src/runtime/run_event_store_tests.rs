use super::{
    NewOrchestrationMessage, NewOrchestrationTask, OrchestrationDispatchContext,
    OrchestrationMessageType, RunGateKind, RunTimelineQuery, RuntimeStore,
};

fn task(spec: &str, run_id: &str) -> NewOrchestrationTask {
    NewOrchestrationTask {
        spec: spec.into(),
        task_title: None,
        display_name: None,
        deps: vec![],
        parent_id: None,
        created_by_terminal_handle: None,
        run_id: Some(run_id.into()),
        workspace_id: "ws".into(),
        coordinator_handle: "coord".into(),
        result_schema: None,
    }
}

#[tokio::test]
async fn run_timeline_records_dispatch_completion_and_gates() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let run = store
        .create_scoped_orchestration_coordinator_run("Ship it", Some("coord"), 2_000, "ws", 4)
        .await
        .unwrap();
    let gated = store
        .create_orchestration_task(task("Decide", &run.id))
        .await
        .unwrap();
    let gate = store
        .create_orchestration_gate(&gated.id, "Proceed?", &["yes".into(), "no".into()])
        .await
        .unwrap();
    assert_eq!(gate.kind, RunGateKind::Decision);
    assert_eq!(gate.run_id.as_deref(), Some(run.id.as_str()));
    store.resolve_gate(&gate.id, "yes", None).await.unwrap();

    let work = store
        .create_orchestration_task(task("Build", &run.id))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &work.id,
            "term_1",
            Some(&run.id),
            "ws",
            "coord",
            None,
            "keep-open",
        )
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&dispatch.id, "term_1", "")
        .await
        .unwrap();
    store
        .complete_orchestration_dispatch(&dispatch.id, "term_1", "done")
        .await
        .unwrap();

    let events = store.run_events(&run.id, 50).await.unwrap();
    let kinds: Vec<&str> = events.iter().map(|event| event.kind.as_str()).collect();
    assert_eq!(
        kinds,
        [
            "created",
            "gateOpened",
            "gateResolved",
            "dispatched",
            "accepted",
            "taskCompleted"
        ]
    );
    assert_eq!(events[1].gate_id.as_deref(), Some(gate.id.as_str()));
    assert_eq!(events[3].dispatch_id.as_deref(), Some(dispatch.id.as_str()));
    assert_eq!(events[4].actor_id.as_deref(), Some("term_1"));
    assert_eq!(events[5].task_id.as_deref(), Some(work.id.as_str()));
}

#[tokio::test]
async fn run_event_limits_trim_the_summary_and_replace_oversized_payloads() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    let summary = "é".repeat(400);
    let mut event = super::NewRunEvent::new("run_x", super::RunEventKind::Attention);
    event.summary = &summary;
    event.payload = Some(serde_json::json!({ "blob": "x".repeat(10_000) }));
    super::record_run_event(&mut tx, &event).await.unwrap();
    tx.commit().await.unwrap();
    let recorded = store.run_events("run_x", 1).await.unwrap().remove(0);
    assert_eq!(recorded.summary.len(), 512);
    assert_eq!(
        recorded.payload,
        Some(serde_json::json!({ "truncated": true }))
    );
}

async fn dispatch(
    store: &RuntimeStore,
    run_id: &str,
    spec: &str,
    terminal: &str,
    accept: bool,
) -> OrchestrationDispatchContext {
    let task = store
        .create_orchestration_task(task(spec, run_id))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &task.id,
            terminal,
            Some(run_id),
            "ws",
            "coord",
            None,
            "keep-open",
        )
        .await
        .unwrap();
    if accept {
        store
            .accept_orchestration_dispatch(&dispatch.id, terminal, "")
            .await
            .unwrap();
    }
    dispatch
}

#[tokio::test]
async fn run_timeline_records_failures_stalls_cancellations_and_escalations() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let run = store
        .create_scoped_orchestration_coordinator_run("Ship it", Some("coord"), 2_000, "ws", 4)
        .await
        .unwrap();

    let failed = dispatch(&store, &run.id, "Fail", "term_1", true).await;
    store
        .fail_orchestration_dispatch(&failed.id, "tests failed")
        .await
        .unwrap();
    let stalled = dispatch(&store, &run.id, "Stall", "term_2", true).await;
    store
        .stall_expired_orchestration_dispatches("9999-12-31 00:00:00")
        .await
        .unwrap();
    let escalation = store
        .insert_orchestration_message(NewOrchestrationMessage {
            from_handle: "term_2".into(),
            to_handle: "coord".into(),
            subject: "The API key is missing".into(),
            body: "Set OAUTH_SECRET before the next attempt.".into(),
            message_type: OrchestrationMessageType::Escalation,
            run_id: Some(run.id.clone()),
            task_id: Some(stalled.task_id.clone()),
            dispatch_id: Some(stalled.id.clone()),
            ..NewOrchestrationMessage::default()
        })
        .await
        .unwrap();
    let startup = dispatch(&store, &run.id, "Start", "term_3", false).await;
    store
        .fail_orchestration_startup(&startup.id, "codex: command not found")
        .await
        .unwrap();
    let cancelled = store
        .create_orchestration_task(task("Cancel", &run.id))
        .await
        .unwrap();
    store
        .cancel_orchestration_task(&cancelled.id, "No longer needed")
        .await
        .unwrap();

    let events = store.run_events(&run.id, 100).await.unwrap();
    let find = |kind: &str, task_id: &str| {
        events
            .iter()
            .find(|event| event.kind == kind && event.task_id.as_deref() == Some(task_id))
            .unwrap_or_else(|| panic!("no {kind} event for {task_id}"))
    };
    let failure = find("taskFailed", &failed.task_id);
    assert_eq!(failure.summary, "tests failed");
    assert_eq!(failure.payload.as_ref().unwrap()["willRetry"], true);
    assert_eq!(
        find("taskStalled", &stalled.task_id).summary,
        "No activity within the lease."
    );
    let escalated = find("escalation", &stalled.task_id);
    assert_eq!(escalated.summary, "The API key is missing");
    assert_eq!(escalated.actor_id.as_deref(), Some("term_2"));
    assert_eq!(
        find("taskFailed", &startup.task_id).summary,
        "Startup failed: codex: command not found"
    );
    assert_eq!(
        find("taskCancelled", &cancelled.id).summary,
        "No longer needed"
    );
    assert!(events.iter().all(
        |event| event.kind != "accepted" || event.task_id.as_deref() != Some(&startup.task_id)
    ));

    // The escalation shows once: as the event, carrying its message.
    let timeline = store
        .run_timeline(&RunTimelineQuery {
            run_id: run.id.clone(),
            ..RunTimelineQuery::default()
        })
        .await
        .unwrap();
    let escalations = timeline
        .items
        .iter()
        .filter(|entry| entry.kind == "escalation" || entry.id == escalation.id)
        .collect::<Vec<_>>();
    assert_eq!(escalations.len(), 1);
    assert_eq!(escalations[0].source, "event");
    assert_eq!(escalations[0].from.as_deref(), Some("term_2"));
    assert_eq!(escalations[0].to.as_deref(), Some("coord"));
    assert_eq!(
        escalations[0].body.as_deref(),
        Some("Set OAUTH_SECRET before the next attempt.")
    );
    assert_eq!(escalations[0].message_type.as_deref(), Some("escalation"));
}
