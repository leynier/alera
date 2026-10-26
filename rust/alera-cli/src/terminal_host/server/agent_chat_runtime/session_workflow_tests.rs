use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::fixture::*;

async fn call_where(
    runtime: &AgentChatRuntime,
    chat: &str,
    test: impl Fn(&Value) -> bool,
) -> Value {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    loop {
        let snapshot = runtime.snapshot(chat).await.unwrap();
        if let Some(item) = snapshot["items"]
            .as_array()
            .unwrap()
            .iter()
            .find(|item| test(&item["normalized"]["subagent"]))
        {
            return item.clone();
        }
        assert!(
            std::time::Instant::now() < deadline,
            "no matching call in {:#}",
            snapshot["items"]
        );
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
}

async fn command(runtime: &AgentChatRuntime, chat: &str, op: ChatOp) -> Result<Value, String> {
    runtime
        .command(chat, op, CallerCtx::runtime(), None)
        .await
        .map_err(|error| format!("{error:?}"))
}

fn task(kind: EventKind) -> Value {
    json!({
        "taskId": "wf", "taskType": "local_workflow",
        "nativeTask": {"nativeTaskId": "wf", "nativeToolCallId": "call-wf"},
        "awaited": (kind == EventKind::TaskStarted).then_some(true),
    })
}

fn with_workflow(mut payload: Value, workflow: Value) -> Value {
    payload["workflow"] = workflow;
    if payload["awaited"].is_null() {
        payload.as_object_mut().unwrap().remove("awaited");
    }
    payload
}

#[tokio::test]
async fn a_workflow_folds_its_frames_and_serves_its_script_and_answers() {
    let files = tempfile::tempdir().unwrap();
    let root = files.path().join("projects");
    std::fs::create_dir_all(root.join("p/wf")).unwrap();
    std::fs::write(
        root.join("p/run.js"),
        "export const meta = {name: 'probe'};\n",
    )
    .unwrap();
    std::fs::write(
        root.join("p/wf/agent-a1.jsonl"),
        format!(
            "{}\n",
            json!({"type": "assistant", "message": {"id": "m", "content": [{"type": "text", "text": "the answer"}]}})
        ),
    )
    .unwrap();
    let (_harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Run the workflow").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.item_event(
        EventKind::ItemStarted,
        1,
        "call-wf",
        json!({"itemType": "dynamic_tool_call", "status": "inProgress", "title": "Workflow"}),
    );
    control.event(
        EventKind::TaskStarted,
        1,
        with_workflow(
            task(EventKind::TaskStarted),
            json!({"name": "probe-wf", "phases": [], "agents": []}),
        ),
    );
    control.event(
        EventKind::TaskUpdated,
        1,
        with_workflow(
            task(EventKind::TaskUpdated),
            json!({
                "runHandles": {
                    "runId": "wf_abc",
                    "transcriptDir": root.join("p/wf"),
                    "scriptPath": root.join("p/run.js"),
                },
                "filesRoot": root,
            }),
        ),
    );
    control.event(
        EventKind::TaskProgress,
        1,
        with_workflow(
            task(EventKind::TaskProgress),
            json!({
                "phases": [{"index": 1, "title": "Alpha"}],
                "agents": [
                    {"index": 1, "label": "alpha:one", "state": "completed", "agentId": "a1", "phaseIndex": 1, "result": "A1"},
                    {"index": 2, "label": "alpha:two", "state": "running", "phaseIndex": 1},
                ],
                "totalTokens": 900,
            }),
        ),
    );
    let call = call_where(&runtime, &chat, |subagent| {
        subagent["workflow"]["totalTokens"] == 900
    })
    .await;
    let call_id = call["itemId"].as_str().unwrap().to_owned();
    let subagent = &call["normalized"]["subagent"];
    assert_eq!(subagent["status"], "running");
    assert_eq!(subagent["taskType"], "local_workflow");
    assert_eq!(subagent["workflow"]["name"], "probe-wf");
    assert_eq!(subagent["workflow"]["runHandles"]["runId"], "wf_abc");
    assert_eq!(subagent["workflow"]["agents"].as_array().unwrap().len(), 2);

    let script = command(
        &runtime,
        &chat,
        ChatOp::WorkflowScript {
            item_id: call_id.clone(),
        },
    )
    .await
    .unwrap();
    assert!(script["contents"].as_str().unwrap().contains("probe"));
    assert_eq!(script["truncated"], false);
    let answers = command(
        &runtime,
        &chat,
        ChatOp::WorkflowAgent {
            item_id: call_id.clone(),
            agent_index: 1,
        },
    )
    .await
    .unwrap();
    assert_eq!(answers["answers"], json!(["the answer"]));
    for (index, code) in [
        (2, "workflowTranscriptUnavailable"),
        (9, "workflowAgentNotFound"),
    ] {
        let error = command(
            &runtime,
            &chat,
            ChatOp::WorkflowAgent {
                item_id: call_id.clone(),
                agent_index: index,
            },
        )
        .await
        .unwrap_err();
        assert!(error.contains(code), "{error}");
    }

    control.event(
        EventKind::TaskCompleted,
        1,
        with_workflow(
            json!({"taskId": "wf", "status": "completed", "summary": "Done"}),
            json!({"agents": [{"index": 2, "label": "alpha:two", "state": "completed"}]}),
        ),
    );
    // A late frame with no status of its own does not revive the run.
    control.event(
        EventKind::TaskProgress,
        1,
        with_workflow(json!({"taskId": "wf"}), json!({"totalTokens": 1000})),
    );
    let settled = call_where(&runtime, &chat, |subagent| {
        subagent["workflow"]["totalTokens"] == 1000
    })
    .await;
    let subagent = &settled["normalized"]["subagent"];
    assert_eq!(subagent["status"], "completed");
    assert!(subagent["completedAt"].is_string());
    assert_eq!(subagent["workflow"]["agents"][1]["state"], "completed");
    assert_eq!(subagent["workflow"]["phases"][0]["title"], "Alpha");

    control.complete(1, "Launched it");
    let answer = runtime.snapshot(&chat).await.unwrap()["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["type"] == "user_message")
        .unwrap()["itemId"]
        .as_str()
        .unwrap()
        .to_owned();
    let error = command(&runtime, &chat, ChatOp::WorkflowScript { item_id: answer })
        .await
        .unwrap_err();
    assert!(error.contains("notWorkflow"), "{error}");
}

#[tokio::test]
async fn a_stopped_turn_stops_the_workflow_it_started() {
    let (_harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Run the workflow").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.item_event(
        EventKind::ItemStarted,
        1,
        "call-wf",
        json!({"itemType": "dynamic_tool_call", "status": "inProgress", "title": "Workflow"}),
    );
    control.event(
        EventKind::TaskStarted,
        1,
        with_workflow(
            task(EventKind::TaskStarted),
            json!({"name": "probe-wf", "phases": [], "agents": []}),
        ),
    );
    call_where(&runtime, &chat, |subagent| {
        subagent["workflow"]["name"] == "probe-wf"
    })
    .await;
    control.event(EventKind::TurnCompleted, 1, json!({"state": "interrupted"}));
    let stopped = call_where(&runtime, &chat, |subagent| subagent["status"] == "stopped").await;
    assert!(stopped["normalized"]["subagent"]["completedAt"].is_string());
    assert_eq!(*control.stopped_subagents.lock().unwrap(), ["wf"]);
}
