use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput};
use serde_json::{json, Value};

async fn observe(frames: Vec<Value>) -> Vec<ProviderEvent> {
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
        let event = provider.next_event().await.unwrap().unwrap();
        event.validate().unwrap();
        events.push(event);
    }
    events
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
            EventKind::TaskProgress,
            EventKind::TaskCompleted
        ]
    );
    for event in &events[2..] {
        assert_eq!(event.thread_id, "app");
        assert_eq!(event.payload["taskId"], "grandchild");
        assert_eq!(event.payload["parentTaskId"], "child");
        assert!(event.task_awaited());
    }
    assert_eq!(events[4].payload["summary"], "found it");
    assert!(!events[4].task_wakes_parent());
}
