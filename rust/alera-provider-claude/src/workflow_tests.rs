use super::*;
use serde_json::json;

fn start_frame() -> Value {
    json!({
        "type": "system", "subtype": "task_started", "task_id": "w1",
        "task_type": "local_workflow", "workflow_name": "probe-wf",
    })
}

fn snapshot_frame(entries: Vec<Value>, usage: Option<Value>) -> Value {
    let mut frame = json!({
        "type": "system", "subtype": "task_progress", "task_id": "w1",
        "description": "Alpha: alpha:one", "workflow_progress": entries,
    });
    if let Some(usage) = usage {
        frame["usage"] = usage;
    }
    frame
}

fn phase(index: u64, title: &str) -> Value {
    json!({"type": "workflow_phase", "index": index, "title": title})
}

fn agent(overrides: Value) -> Value {
    let mut agent = json!({
        "type": "workflow_agent", "index": 1, "label": "alpha:one", "state": "start",
        "phaseIndex": 1, "phaseTitle": "Alpha",
    });
    for (key, value) in overrides.as_object().unwrap() {
        agent[key] = value.clone();
    }
    agent
}

#[test]
fn a_coordinator_is_a_workflow_before_any_member_exists() {
    let workflow = frame(&start_frame(), false).unwrap();
    assert_eq!(
        serde_json::to_value(workflow).unwrap(),
        json!({"name": "probe-wf", "phases": [], "agents": []})
    );
}

#[test]
fn an_ordinary_subagents_frames_are_left_alone() {
    let usage = json!({
        "type": "system", "subtype": "task_progress", "task_id": "t1",
        "description": "reading files",
        "usage": {"total_tokens": 500, "tool_uses": 2, "duration_ms": 90},
    });
    assert_eq!(frame(&usage, false), None);
    // The same frame of a known workflow carries its usage.
    let known = frame(&usage, true).unwrap();
    assert_eq!(known.total_tokens, Some(500));
    assert_eq!(known.tool_calls, Some(2));
    assert_eq!(known.duration_ms, Some(90));
    assert_eq!(known.name, None);
}

#[test]
fn provider_states_and_member_metrics_map_to_the_t3_shape() {
    let workflow = frame(
        &snapshot_frame(
            vec![
                phase(1, "Alpha"),
                agent(json!({
                    "state": "done", "agentId": "a1", "model": "claude-opus-5[1m]",
                    "attempt": 2, "tokens": 71_141, "toolCalls": 3, "durationMs": 1277,
                    "startedAt": 1_700_000_000_000_u64, "queuedAt": 1_699_999_999_000_u64,
                    "promptPreview": "Reply with exactly: A1", "resultPreview": "A1",
                })),
                agent(json!({"index": 2, "label": "alpha:two", "state": "queued"})),
            ],
            None,
        ),
        false,
    )
    .unwrap();
    let value = serde_json::to_value(&workflow).unwrap();
    assert_eq!(value["phases"], json!([{"index": 1, "title": "Alpha"}]));
    assert_eq!(
        value["agents"][0],
        json!({
            "index": 1, "label": "alpha:one", "agentId": "a1", "state": "completed",
            "phaseIndex": 1, "phaseTitle": "Alpha", "model": "claude-opus-5[1m]",
            "attempt": 2, "totalTokens": 71_141, "toolCalls": 3, "durationMs": 1277,
            "queuedAt": 1_699_999_999_000_u64, "startedAt": 1_700_000_000_000_u64,
            "prompt": "Reply with exactly: A1", "result": "A1",
        })
    );
    assert_eq!(value["agents"][1]["state"], "queued");
}

#[test]
fn an_unknown_state_counts_as_running() {
    for state in [
        json!("something-new"),
        json!("toString"),
        json!("__proto__"),
        json!(7),
        Value::Null,
    ] {
        let workflow = frame(
            &snapshot_frame(vec![agent(json!({"state": state}))], None),
            false,
        )
        .unwrap();
        assert_eq!(workflow.agents[0].state, WorkflowAgentState::Running);
    }
    let mut missing = agent(json!({}));
    missing.as_object_mut().unwrap().remove("state");
    let workflow = frame(&snapshot_frame(vec![missing], None), false).unwrap();
    assert_eq!(workflow.agents[0].state, WorkflowAgentState::Running);
}

#[test]
fn excerpts_keep_their_whitespace_and_labels_are_trimmed() {
    let workflow = frame(
        &snapshot_frame(
            vec![agent(json!({
                "label": "  alpha:one ", "promptPreview": "  indented\n",
                "resultPreview": "\n  answer\n",
            }))],
            None,
        ),
        false,
    )
    .unwrap();
    assert_eq!(workflow.agents[0].label, "alpha:one");
    assert_eq!(workflow.agents[0].prompt.as_deref(), Some("  indented\n"));
    assert_eq!(workflow.agents[0].result.as_deref(), Some("\n  answer\n"));
}

#[test]
fn timestamps_outside_the_date_range_are_dropped() {
    let workflow = frame(
        &snapshot_frame(
            vec![
                agent(
                    json!({"startedAt": 8_640_000_000_000_001_u64, "queuedAt": MAX_SAFE_INTEGER}),
                ),
                agent(json!({"index": 2, "startedAt": 8_640_000_000_000_000_u64, "queuedAt": 0})),
                agent(json!({"index": 3, "startedAt": -5, "tokens": 1.5, "attempt": 2.0})),
            ],
            None,
        ),
        false,
    )
    .unwrap();
    assert_eq!(workflow.agents[0].started_at, None);
    assert_eq!(workflow.agents[0].queued_at, None);
    assert_eq!(workflow.agents[1].started_at, Some(8_640_000_000_000_000));
    assert_eq!(workflow.agents[1].queued_at, Some(0));
    assert_eq!(workflow.agents[2].started_at, None);
    assert_eq!(workflow.agents[2].total_tokens, None);
    assert_eq!(workflow.agents[2].attempt, Some(2));
}

#[test]
fn malformed_entries_are_dropped_instead_of_failing_the_frame() {
    let workflow = frame(
        &snapshot_frame(
            vec![
                json!({"type": "workflow_phase", "title": "No index"}),
                json!({"type": "workflow_agent", "index": 4}),
                json!({"type": "something_else", "index": 1, "title": "Ignored"}),
                json!("not an object"),
                phase(1, "Alpha"),
            ],
            None,
        ),
        false,
    )
    .unwrap();
    assert_eq!(
        serde_json::to_value(workflow).unwrap(),
        json!({"phases": [{"index": 1, "title": "Alpha"}], "agents": []})
    );
    // A snapshot with nothing that parses does not mark a task.
    let empty = snapshot_frame(vec![json!({"type": "workflow_agent"})], None);
    assert_eq!(frame(&empty, false), None);
    let not_a_list = json!({"workflow_progress": {"type": "workflow_phase"}});
    assert_eq!(frame(&not_a_list, false), None);
}

#[test]
fn run_handles_come_only_from_a_workflow_acknowledgement() {
    let handles = run_handles(&json!({
        "status": "async_launched", "taskType": "local_workflow", "runId": "wf_abc",
        "transcriptDir": "/root/.claude/projects/p/s/subagents/workflows/wf_abc",
        "scriptPath": "/root/.claude/projects/p/s/workflows/scripts/x.js",
    }))
    .unwrap();
    assert_eq!(handles.run_id.as_deref(), Some("wf_abc"));
    assert_eq!(
        handles.transcript_dir.as_deref(),
        Some("/root/.claude/projects/p/s/subagents/workflows/wf_abc")
    );
    assert_eq!(
        run_handles(&json!({"status": "async_launched", "taskType": "local_agent"})),
        None
    );
    assert_eq!(run_handles(&json!({"taskType": "local_workflow"})), None);
    assert_eq!(run_handles(&json!("local_workflow")), None);
}
