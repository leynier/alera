mod support;

use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput};

use serde_json::{json, Value};

async fn observe(frames: Vec<Value>) -> Vec<ProviderEvent> {
    observe_with(frames).await.1
}

async fn observe_with(frames: Vec<Value>) -> (CodexProvider<MockTransport>, Vec<ProviderEvent>) {
    let count = frames.len();
    let mut transport = vec![
        json!({ "id": 1, "result": { "codexHome": "/tmp/codex", "platformFamily": "unix", "platformOs": "linux", "userAgent": "test" } }),
        json!({ "id": 2, "result": { "thread": { "id": "native" } } }),
    ];
    transport.extend(frames);
    let mut provider = CodexProvider::new(
        MockTransport::new(transport),
        CodexProviderConfig::default(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let mut events = Vec::new();
    for _ in 0..count {
        let event = support::next_event(&mut provider).await.unwrap().unwrap();
        event.validate().unwrap();
        events.push(event);
    }
    (provider, events)
}

fn spawn(sender: &str, child: &str, prompt: &str) -> Value {
    json!({
        "method": "item/completed",
        "params": {
            "threadId": sender,
            "turnId": format!("{sender}-turn"),
            "item": {
                "type": "collabAgentToolCall",
                "id": format!("spawn-{child}"),
                "tool": "spawnAgent",
                "status": "completed",
                "senderThreadId": sender,
                "receiverThreadIds": [child],
                "prompt": prompt,
            },
        }
    })
}

fn turn(thread: &str, method: &str, status: &str) -> Value {
    json!({
        "method": method,
        "params": { "threadId": thread, "turn": { "id": format!("{thread}-turn"), "status": status } }
    })
}

fn answer(thread: &str, text: &str, phase: &str) -> Value {
    json!({
        "method": "item/completed",
        "params": {
            "threadId": thread,
            "turnId": format!("{thread}-turn"),
            "item": { "type": "agentMessage", "id": format!("{thread}-{phase}"), "text": text, "phase": phase },
        }
    })
}

#[tokio::test]
async fn a_direct_child_reports_its_outcome_and_wakes_its_parent() {
    let events = observe(vec![
        spawn("native", "child", "Count the files"),
        turn("child", "turn/started", "inProgress"),
        turn("native", "turn/completed", "completed"),
        answer("child", "Looking", "commentary"),
        answer("child", "42 files", "final_answer"),
        turn("child", "turn/completed", "completed"),
    ])
    .await;
    assert_eq!(events[2].kind, EventKind::TurnCompleted);
    let done = &events[5];
    assert_eq!(done.kind, EventKind::TaskCompleted);
    assert_eq!(done.payload["taskId"], "child");
    assert_eq!(done.payload["status"], "completed");
    assert_eq!(done.payload["description"], "Count the files");
    assert_eq!(done.payload["summary"], "42 files");
    assert!(done.payload.get("parentTaskId").is_none());
    assert!(done.task_wakes_parent());
}

#[tokio::test]
async fn failed_children_wake_and_interrupted_ones_do_not() {
    let events = observe(vec![
        spawn("native", "failing", ""),
        spawn("native", "stopped", "Stop me"),
        turn("failing", "turn/completed", "failed"),
        turn("stopped", "turn/completed", "interrupted"),
        turn("stopped", "turn/aborted", "interrupted"),
    ])
    .await;
    assert_eq!(events[2].payload["status"], "failed");
    // A spawn without a prompt leaves the child unnamed.
    assert!(events[2].payload.get("description").is_none());
    assert!(events[2].task_wakes_parent());
    for stopped in &events[3..] {
        assert_eq!(stopped.kind, EventKind::TaskCompleted);
        assert_eq!(stopped.payload["status"], "stopped");
        assert!(!stopped.task_wakes_parent());
    }
}

#[tokio::test]
async fn grandchildren_are_tasks_of_their_parent_and_never_end_the_root_turn() {
    let events = observe(vec![
        spawn("native", "child", "Delegate further"),
        spawn("child", "grandchild", "Dig"),
        turn("grandchild", "turn/started", "inProgress"),
        answer("grandchild", "found it", "final_answer"),
        turn("grandchild", "turn/completed", "completed"),
    ])
    .await;
    let kinds: Vec<_> = events[2..].iter().map(|event| event.kind.clone()).collect();
    assert_eq!(
        kinds,
        [
            EventKind::TaskStarted,
            EventKind::ItemCompleted,
            EventKind::TaskCompleted
        ]
    );
    for event in [&events[2], &events[4]] {
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.payload["taskId"], "grandchild");
        assert_eq!(event.payload["parentTaskId"], "child");
        assert!(event.task_awaited());
    }
    // The grandchild's own answer is an item under the call that spawned it.
    assert_eq!(events[3].thread_id, "app");
    assert_eq!(events[3].payload["parentToolUseId"], "spawn-grandchild");
    assert_eq!(events[3].payload["subagentThreadId"], "grandchild");
    assert_eq!(events[4].payload["summary"], "found it");
    assert!(!events[4].task_wakes_parent());
}

fn child_delta(thread: &str, item: &str, delta: &str) -> Value {
    json!({
        "method": "item/agentMessage/delta",
        "params": { "threadId": thread, "turnId": format!("{thread}-turn"), "itemId": item, "delta": delta }
    })
}

fn child_prompt(thread: &str) -> Value {
    json!({
        "method": "item/completed",
        "params": {
            "threadId": thread,
            "turnId": format!("{thread}-turn"),
            "item": { "type": "userMessage", "id": format!("{thread}-prompt"), "content": [{"type": "text", "text": "Count"}] },
        }
    })
}

#[tokio::test]
async fn a_childs_own_items_stream_under_the_call_that_spawned_it() {
    let mut spawn = spawn("native", "child", "Count the files");
    spawn["params"]["item"]["model"] = json!("gpt-6-luna");
    spawn["params"]["item"]["reasoningEffort"] = json!("high");
    // A later call naming the same child does not take it over.
    let mut wait = super_spawn_wait("native", "child");
    wait["params"]["item"]["id"] = json!("wait-child");
    let events = observe(vec![
        spawn,
        wait,
        turn("child", "turn/started", "inProgress"),
        child_prompt("child"),
        child_delta("child", "child-answer", "42"),
        answer("child", "42 files", "final_answer"),
    ])
    .await;
    assert_eq!(events[2].kind, EventKind::TaskStarted);
    assert_eq!(events[2].payload["model"], "gpt-6-luna");
    assert_eq!(events[2].payload["reasoningEffort"], "high");
    // The child's prompt is already on the spawning call.
    assert_eq!(events[3].kind, EventKind::TaskProgress);
    assert_eq!(events[4].kind, EventKind::ContentDelta);
    assert_eq!(events[4].item_id.as_deref(), Some("child-answer"));
    assert_eq!(events[5].kind, EventKind::ItemCompleted);
    for event in &events[4..] {
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.payload["parentToolUseId"], "spawn-child");
        assert_eq!(event.payload["subagentThreadId"], "child");
    }
}

fn super_spawn_wait(sender: &str, child: &str) -> Value {
    let mut wait = spawn(sender, child, "");
    wait["params"]["item"]["tool"] = json!("wait");
    wait
}

#[tokio::test]
async fn stopping_a_child_interrupts_only_its_running_turn() {
    let (mut provider, _) = observe_with(vec![
        spawn("native", "child", "Count the files"),
        turn("child", "turn/started", "inProgress"),
    ])
    .await;
    let next = provider
        .transport()
        .writes()
        .iter()
        .filter_map(|write| write["id"].as_i64())
        .max()
        .unwrap()
        + 1;
    provider
        .transport_mut()
        .push_response(json!({ "id": next, "result": {} }));
    provider.stop_subagent("child").await.unwrap();
    let interrupt = provider.transport().writes().last().unwrap().clone();
    assert_eq!(interrupt["method"], "turn/interrupt");
    assert_eq!(interrupt["params"]["threadId"], "child");
    assert_eq!(interrupt["params"]["turnId"], "child-turn");
    assert!(provider.stop_subagent("stranger").await.is_err());
}
