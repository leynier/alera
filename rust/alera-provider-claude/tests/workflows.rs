mod support;

use alera_provider_claude::{ClaudeProvider, ClaudeProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, SessionStartInput, WorkflowAgentState,
};
use serde_json::{json, Value};
use support::*;

/// Events up to and including the `count`th task event.
async fn task_events(provider: &mut ClaudeProvider, count: usize) -> Vec<ProviderEvent> {
    let mut tasks = Vec::new();
    while tasks.len() < count {
        let event = provider.next_event().await.unwrap().unwrap();
        if matches!(
            event.kind,
            EventKind::TaskStarted
                | EventKind::TaskProgress
                | EventKind::TaskUpdated
                | EventKind::TaskCompleted
        ) {
            tasks.push(event);
        }
    }
    tasks
}

fn progress(task: &str, entries: Value, usage: Value) -> Value {
    json!({
        "type": "system", "subtype": "task_progress", "task_id": task,
        "session_id": "native-session", "description": "Alpha: alpha:one",
        "workflow_progress": entries, "usage": usage,
    })
}

#[tokio::test]
async fn a_workflow_reports_its_name_handles_phases_members_and_usage() {
    let mut config = ClaudeProviderConfig::default();
    config
        .options
        .env
        .insert("CLAUDE_CONFIG_DIR".into(), "/claude-config".into());
    let (transport, _handle) = ScriptedTransport::new([
        initialize_response(),
        json!({
            "type": "system", "subtype": "task_started", "task_id": "wf",
            "tool_use_id": "toolu_workflow", "session_id": "native-session",
            "task_type": "local_workflow", "workflow_name": "probe-wf",
            "description": "Run probe-wf",
        }),
        json!({
            "type": "user", "session_id": "native-session",
            "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "toolu_workflow", "content": "Launched"},
            ]},
            "tool_use_result": {
                "status": "async_launched", "taskType": "local_workflow", "runId": "wf_abc",
                "transcriptDir": "/claude-config/projects/p/s/subagents/workflows/wf_abc",
                "scriptPath": "/claude-config/projects/p/s/workflows/scripts/probe.js",
            },
        }),
        progress(
            "wf",
            json!([
                {"type": "workflow_phase", "index": 1, "title": "Alpha"},
                {"type": "workflow_agent", "index": 1, "label": "alpha:one", "state": "done",
                 "agentId": "a1", "phaseIndex": 1, "resultPreview": "A1"},
                {"type": "workflow_agent", "index": 2, "label": "alpha:two", "state": "novel"},
                {"type": "workflow_agent", "label": "no index"},
            ]),
            json!({"total_tokens": 900, "tool_uses": 4, "duration_ms": 1200}),
        ),
        // Usage only: still the workflow's, as the task is known to be one.
        json!({
            "type": "system", "subtype": "task_progress", "task_id": "wf",
            "session_id": "native-session", "description": "",
            "usage": {"total_tokens": 1500},
        }),
        // An ordinary sub-agent's usage never reads as a workflow.
        json!({
            "type": "system", "subtype": "task_progress", "task_id": "plain",
            "tool_use_id": "toolu_task", "session_id": "native-session",
            "description": "reading", "usage": {"total_tokens": 10},
        }),
        json!({
            "type": "system", "subtype": "task_notification", "task_id": "wf",
            "session_id": "native-session", "status": "completed", "summary": "Done",
        }),
    ]);
    let mut provider = ClaudeProvider::with_transport(transport, config).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let events = task_events(&mut provider, 6).await;

    let started = &events[0];
    assert_eq!(started.kind, EventKind::TaskStarted);
    assert_eq!(started.payload["taskType"], "local_workflow");
    assert_eq!(
        started.payload["workflow"],
        json!({"name": "probe-wf", "phases": [], "agents": []})
    );

    let handles = &events[1];
    assert_eq!(handles.kind, EventKind::TaskUpdated);
    assert_eq!(handles.payload.get("status"), None);
    assert_eq!(
        handles.payload["nativeTask"]["nativeToolCallId"],
        "toolu_workflow"
    );
    let workflow = handles.workflow().unwrap();
    let run = workflow.run_handles.unwrap();
    assert_eq!(run.run_id.as_deref(), Some("wf_abc"));
    assert!(run.script_path.unwrap().ends_with("probe.js"));
    assert_eq!(
        workflow.files_root.as_deref(),
        Some(
            std::path::Path::new("/claude-config")
                .join("projects")
                .to_str()
                .unwrap()
        )
    );

    let snapshot = events[2].workflow().unwrap();
    assert_eq!(snapshot.phases.len(), 1);
    assert_eq!(snapshot.agents.len(), 2);
    assert_eq!(snapshot.agents[0].state, WorkflowAgentState::Completed);
    assert_eq!(snapshot.agents[0].agent_id.as_deref(), Some("a1"));
    assert_eq!(snapshot.agents[1].state, WorkflowAgentState::Running);
    assert_eq!(snapshot.total_tokens, Some(900));

    let usage = events[3].workflow().unwrap();
    assert!(usage.agents.is_empty());
    assert_eq!(usage.total_tokens, Some(1500));

    assert_eq!(events[4].payload.get("workflow"), None);

    let completed = &events[5];
    assert_eq!(completed.kind, EventKind::TaskCompleted);
    assert_eq!(completed.payload["status"], "completed");
    assert!(completed.workflow().is_some());
}

#[tokio::test]
async fn a_running_workflow_stops_through_stop_task() {
    let (mut provider, handle) = started_provider([
        initialize_response(),
        json!({
            "type": "system", "subtype": "task_started", "task_id": "wf",
            "session_id": "native-session", "task_type": "local_workflow",
        }),
        json!({"type":"control_response","response":{"subtype":"success","request_id":"req_2","response":{}}}),
    ])
    .await;
    task_events(&mut provider, 1).await;
    provider.stop_subagent("wf").await.unwrap();
    let writes = handle.writes.lock().unwrap().clone();
    let stop = writes
        .iter()
        .find(|write| write["request"]["subtype"] == "stop_task")
        .expect("stop_task control request");
    assert_eq!(stop["request"]["task_id"], "wf");
}

#[tokio::test]
async fn handles_that_arrive_before_the_task_wait_for_its_start() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "user", "session_id": "native-session",
            "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "toolu_workflow", "content": "Launched"},
            ]},
            "tool_use_result": {"taskType": "local_workflow", "scriptPath": "/p/run.js"},
        }),
        json!({
            "type": "system", "subtype": "task_started", "task_id": "wf",
            "tool_use_id": "toolu_workflow", "session_id": "native-session",
            "task_type": "local_workflow",
        }),
    ])
    .await;
    let started = task_events(&mut provider, 1).await.remove(0);
    assert_eq!(started.kind, EventKind::TaskStarted);
    let workflow = started.workflow().unwrap();
    assert_eq!(
        workflow.run_handles.unwrap().script_path.as_deref(),
        Some("/p/run.js")
    );
    assert!(workflow.files_root.is_some());
}
