use super::*;
use serde_json::json;

fn agent(index: u64, state: WorkflowAgentState) -> WorkflowAgent {
    WorkflowAgent {
        index,
        label: format!("alpha:{index}"),
        state,
        agent_id: None,
        phase_index: Some(1),
        phase_title: Some("Alpha".into()),
        model: None,
        attempt: None,
        total_tokens: None,
        tool_calls: None,
        duration_ms: None,
        queued_at: None,
        started_at: None,
        prompt: None,
        result: None,
    }
}

fn phase(index: u64, title: &str) -> WorkflowPhase {
    WorkflowPhase {
        index,
        title: title.into(),
    }
}

fn frame(phases: Vec<WorkflowPhase>, agents: Vec<WorkflowAgent>) -> SubagentWorkflow {
    SubagentWorkflow {
        phases,
        agents,
        ..Default::default()
    }
}

use WorkflowAgentState::*;

#[test]
fn usage_only_frames_keep_the_roster_and_name() {
    let first = SubagentWorkflow::merge(
        None,
        &SubagentWorkflow {
            name: Some("probe-wf".into()),
            total_tokens: Some(100),
            ..frame(vec![phase(1, "Alpha")], vec![agent(1, Running)])
        },
    );
    let second = SubagentWorkflow::merge(
        Some(&first),
        &SubagentWorkflow {
            total_tokens: Some(250),
            tool_calls: Some(2),
            ..Default::default()
        },
    );
    assert_eq!(second.agents.len(), 1);
    assert_eq!(second.phases.len(), 1);
    assert_eq!(second.name.as_deref(), Some("probe-wf"));
    assert_eq!(second.total_tokens, Some(250));
    assert_eq!(second.tool_calls, Some(2));
}

#[test]
fn a_phase_the_plan_reached_stays_when_a_later_frame_omits_it() {
    let first = SubagentWorkflow::merge(
        None,
        &frame(
            vec![phase(3, "Gamma"), phase(1, "Alpha"), phase(2, "Beta")],
            vec![],
        ),
    );
    let second = SubagentWorkflow::merge(Some(&first), &frame(vec![phase(1, "Alpha")], vec![]));
    let titles: Vec<_> = second
        .phases
        .iter()
        .map(|phase| phase.title.as_str())
        .collect();
    assert_eq!(titles, ["Alpha", "Beta", "Gamma"]);
}

#[test]
fn a_new_attempt_keeps_only_the_phase_and_other_members() {
    let mut failed = agent(1, Failed);
    failed.attempt = Some(1);
    failed.prompt = Some("First prompt".into());
    failed.result = Some("First result".into());
    failed.total_tokens = Some(100);
    let first = SubagentWorkflow::merge(None, &frame(vec![], vec![failed, agent(2, Completed)]));
    let mut retry = agent(1, Running);
    retry.attempt = Some(2);
    retry.phase_index = None;
    retry.phase_title = None;
    let second = SubagentWorkflow::merge(Some(&first), &frame(vec![], vec![retry]));
    let mut expected = agent(1, Running);
    expected.attempt = Some(2);
    assert_eq!(second.agents, vec![expected, first.agents[1].clone()]);
}

#[test]
fn an_older_attempt_is_ignored_after_a_retry() {
    let mut done = agent(1, Completed);
    done.attempt = Some(2);
    done.result = Some("New result".into());
    let first = SubagentWorkflow::merge(None, &frame(vec![], vec![done]));
    let mut stale = agent(1, Failed);
    stale.attempt = Some(1);
    stale.result = Some("Old result".into());
    let second = SubagentWorkflow::merge(Some(&first), &frame(vec![], vec![stale]));
    assert_eq!(second.agents, first.agents);
}

#[test]
fn a_member_never_regresses_within_an_attempt() {
    for (state, stale) in [
        (Completed, Running),
        (Completed, Queued),
        (Failed, Running),
        (Failed, Queued),
        (Running, Queued),
    ] {
        let mut current = agent(1, state);
        current.attempt = Some(2);
        current.result = Some("Current result".into());
        let first = SubagentWorkflow::merge(None, &frame(vec![], vec![current]));
        let mut old = agent(1, stale);
        old.attempt = Some(2);
        old.result = Some("Old result".into());
        let second = SubagentWorkflow::merge(Some(&first), &frame(vec![], vec![old]));
        assert_eq!(second.agents, first.agents, "{state:?} -> {stale:?}");
    }
}

#[test]
fn fields_a_later_frame_omits_are_kept_within_an_attempt() {
    let mut running = agent(1, Running);
    running.attempt = Some(2);
    running.prompt = Some("Current prompt".into());
    running.total_tokens = Some(100);
    let first = SubagentWorkflow::merge(None, &frame(vec![], vec![running]));
    let mut done = agent(1, Completed);
    done.result = Some("Current result".into());
    let second = SubagentWorkflow::merge(Some(&first), &frame(vec![], vec![done]));
    let member = &second.agents[0];
    assert_eq!(member.state, Completed);
    assert_eq!(member.attempt, Some(2));
    assert_eq!(member.prompt.as_deref(), Some("Current prompt"));
    assert_eq!(member.result.as_deref(), Some("Current result"));
    assert_eq!(member.total_tokens, Some(100));
}

#[test]
fn run_handles_merge_field_by_field() {
    let first = SubagentWorkflow::merge(
        None,
        &SubagentWorkflow {
            run_handles: Some(WorkflowRunHandles {
                run_id: Some("wf_abc".into()),
                transcript_dir: Some("/workflows/wf_abc".into()),
                script_path: None,
            }),
            ..Default::default()
        },
    );
    let second = SubagentWorkflow::merge(
        Some(&first),
        &SubagentWorkflow {
            run_handles: Some(WorkflowRunHandles {
                script_path: Some("/scripts/workflow.js".into()),
                ..Default::default()
            }),
            ..Default::default()
        },
    );
    assert_eq!(
        second.run_handles,
        Some(WorkflowRunHandles {
            run_id: Some("wf_abc".into()),
            transcript_dir: Some("/workflows/wf_abc".into()),
            script_path: Some("/scripts/workflow.js".into()),
        })
    );
}

#[test]
fn a_runaway_frame_is_bounded() {
    let mut long = agent(0, Running);
    long.prompt = Some("é".repeat(WORKFLOW_MAX_TEXT_CHARS + 10));
    let mut agents = vec![long];
    agents.extend((1..400).map(|index| agent(index, Queued)));
    let merged = SubagentWorkflow::merge(None, &frame(vec![], agents));
    assert_eq!(merged.agents.len(), WORKFLOW_MAX_AGENTS);
    assert_eq!(
        merged.agents[0].prompt.as_ref().unwrap().chars().count(),
        WORKFLOW_MAX_TEXT_CHARS
    );
}

#[test]
fn the_wire_shape_matches_t3_and_malformed_frames_are_ignored() {
    let mut member = agent(1, Completed);
    member.total_tokens = Some(7);
    let workflow = frame(vec![phase(1, "Alpha")], vec![member]);
    let value = serde_json::to_value(&workflow).unwrap();
    assert_eq!(
        value,
        json!({
            "phases": [{"index": 1, "title": "Alpha"}],
            "agents": [{
                "index": 1, "label": "alpha:1", "state": "completed",
                "phaseIndex": 1, "phaseTitle": "Alpha", "totalTokens": 7,
            }],
        })
    );
    let mut event = ProviderEvent::new(
        crate::ProviderKind::Claude,
        "claude",
        "thread",
        crate::EventKind::TaskProgress,
        json!({"workflow": value}),
        None,
    );
    assert_eq!(event.workflow(), Some(workflow));
    event.payload = json!({"workflow": {"agents": "nope"}});
    assert_eq!(event.workflow(), None);
}
