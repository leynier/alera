mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{EventKind, Provider, RuntimeMode, SessionStartInput};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
use support::{initialize_response, response, session_response, ScriptedTransport};

fn child_approval(id: &str, subject: &str, stage: u64) -> Value {
    json!({
        "approvalId": id, "sessionId": "muse-session", "turnId": "turn-1", "itemId": "item-1",
        "toolName": "shell", "subject": {"kind": subject, "command": "touch result.txt"},
        "subagentOrigin": {"childRunId": "run-1", "childSessionId": "child-1", "subagentId": "agent-1"},
        "availableChoices": [
            {"choiceId": "native-once", "decision": "approved", "label": "Allow once", "scope": "once"},
            {"choiceId": "native-abort", "decision": "abort", "label": "Cancel", "scope": "once"}
        ],
        "currentRequirementId": {"approvalId": id, "sourceIndex": stage}
    })
}

fn notification(method: &str, params: Value) -> Value {
    json!({"jsonrpc": "2.0", "method": method, "params": params})
}

fn marker() -> Value {
    notification(
        "item/delta",
        json!({"sessionId":"muse-session","turnId":"turn-1","itemId":"item-2","field":"text","delta":"done"}),
    )
}

async fn started(
    runtime_mode: RuntimeMode,
    frames: impl IntoIterator<Item = Value>,
) -> (MuseProvider, Arc<Mutex<Vec<Value>>>) {
    let transport = ScriptedTransport::new(
        [initialize_response(), session_response(2, "muse-session")]
            .into_iter()
            .chain(frames),
    );
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = runtime_mode;
    provider.start_session(input).await.unwrap();
    let _ = provider.next_event().await;
    let _ = provider.next_event().await;
    (provider, writes)
}

fn decisions(writes: &Arc<Mutex<Vec<Value>>>) -> Vec<Value> {
    writes
        .lock()
        .unwrap()
        .iter()
        .filter(|frame| frame["method"] == "approval/decide")
        .map(|frame| frame["params"].clone())
        .collect()
}

#[tokio::test]
async fn full_access_approves_workflow_children_without_showing_them() {
    let (mut provider, writes) = started(
        RuntimeMode::FullAccess,
        [
            json!({"jsonrpc":"2.0","id":77,"method":"approval/request","params":child_approval("approval-1", "shell", 0)}),
            notification("approval/requested", child_approval("approval-1", "shell", 0)),
            response(3, json!({"status":"accepted","terminal":false})),
            // A later stage of the same approval is decided again.
            notification("approval/requested", child_approval("approval-1", "shell", 1)),
            response(4, json!({"status":"accepted","terminal":true})),
            notification(
                "approval/resolved",
                json!({"approvalId":"approval-1","sessionId":"muse-session","turnId":"turn-1",
                    "decision":"approved","subagentOrigin":{"childRunId":"run-1"}}),
            ),
            marker(),
        ],
    )
    .await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::ContentDelta);
    let writes_now = writes.lock().unwrap().clone();
    assert_eq!(writes_now[3]["id"], 77);
    let decisions = decisions(&writes);
    assert_eq!(decisions.len(), 2);
    for (decision, stage) in decisions.iter().zip([0, 1]) {
        assert_eq!(decision["approvalId"], "approval-1");
        assert_eq!(decision["choiceId"], "native-once");
        assert_eq!(decision["requirementId"]["sourceIndex"], stage);
    }
    provider.close().await.unwrap();
}

#[tokio::test]
async fn shows_a_child_approval_muse_refuses_to_settle() {
    let (mut provider, writes) = started(
        RuntimeMode::FullAccess,
        [
            notification(
                "approval/requested",
                child_approval("approval-1", "shell", 0),
            ),
            json!({"jsonrpc":"2.0","id":3,"error":{"code":-32053,"message":"stale",
                "data":{"kind":"approvalRequirementStale"}}}),
        ],
    )
    .await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    assert_eq!(event.request_id.as_deref(), Some("approval-1"));
    assert_eq!(decisions(&writes).len(), 1);
    provider.close().await.unwrap();
}

#[tokio::test]
async fn shows_child_approvals_outside_full_access_and_unknown_subjects() {
    for (mode, subject) in [
        (RuntimeMode::ApprovalRequired, "shell"),
        (RuntimeMode::Auto, "fileAccess"),
        (RuntimeMode::FullAccess, "browser"),
    ] {
        let (mut provider, writes) = started(
            mode,
            [notification(
                "approval/requested",
                child_approval("approval-1", subject, 0),
            )],
        )
        .await;
        let event = provider.next_event().await.unwrap().unwrap();
        assert_eq!(event.kind, EventKind::RequestOpened, "{mode:?} {subject}");
        assert!(decisions(&writes).is_empty());
        provider.close().await.unwrap();
    }
}
