use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, RequestId, RuntimeResponse, SessionStartInput,
};
use serde_json::{json, Value};

fn initialize_response(id: i64) -> Value {
    json!({ "id": id, "result": { "userAgent": "test" } })
}

fn thread_response(id: i64, native_id: &str) -> Value {
    json!({ "id": id, "result": { "thread": { "id": native_id } } })
}

fn approval(id: i64, method: &str, item: &str) -> Value {
    json!({
        "id": id,
        "method": method,
        "params": { "itemId": item, "threadId": "native", "turnId": "turn" }
    })
}

fn delta(text: &str) -> Value {
    json!({
        "method": "item/agentMessage/delta",
        "params": { "itemId": "msg", "threadId": "native", "turnId": "turn", "delta": text }
    })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-test".into(),
        ..CodexProviderConfig::default()
    }
}

async fn answer(
    provider: &mut CodexProvider<MockTransport>,
    item: &str,
    decision: ApprovalDecision,
) {
    provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::String(item.into()),
            decision,
            updated_input: None,
            feedback: None,
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn allowing_commands_for_the_session_answers_later_commands_only() {
    let command = "item/commandExecution/requestApproval";
    let file_change = "item/fileChange/requestApproval";
    let mut provider = CodexProvider::new(
        MockTransport::new([
            initialize_response(1),
            thread_response(2, "native"),
            approval(10, command, "first"),
            approval(11, command, "second"),
            delta("after"),
            approval(12, file_change, "patch"),
        ]),
        config(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    let first = provider.next_event().await.unwrap().unwrap();
    assert_eq!(first.kind, EventKind::RequestOpened);
    answer(&mut provider, "first", ApprovalDecision::AcceptForSession).await;

    // The second command is answered for the session without surfacing.
    let next = provider.next_event().await.unwrap().unwrap();
    assert_eq!(next.kind, EventKind::ContentDelta);
    // A different kind still asks.
    let patch = provider.next_event().await.unwrap().unwrap();
    assert_eq!(patch.kind, EventKind::RequestOpened);
    assert_eq!(patch.request_id.as_deref(), Some("patch"));

    let writes = provider.transport().writes();
    let responses: Vec<_> = writes
        .iter()
        .filter(|write| write.get("result").is_some())
        .map(|write| (write["id"].clone(), write["result"]["decision"].clone()))
        .collect();
    assert_eq!(
        responses,
        vec![
            (json!(10), json!("acceptForSession")),
            (json!(11), json!("acceptForSession")),
        ]
    );
}

#[tokio::test]
async fn a_one_time_accept_does_not_allow_the_session() {
    let command = "item/commandExecution/requestApproval";
    let mut provider = CodexProvider::new(
        MockTransport::new([
            initialize_response(1),
            thread_response(2, "native"),
            approval(10, command, "first"),
            approval(11, command, "second"),
        ]),
        config(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    provider.next_event().await.unwrap().unwrap();
    answer(&mut provider, "first", ApprovalDecision::Accept).await;
    let second = provider.next_event().await.unwrap().unwrap();
    assert_eq!(second.kind, EventKind::RequestOpened);
    assert_eq!(second.request_id.as_deref(), Some("second"));
}

#[tokio::test]
async fn legacy_approvals_answer_with_review_decisions() {
    let mut provider = CodexProvider::new(
        MockTransport::new([
            initialize_response(1),
            thread_response(2, "native"),
            json!({ "id": 10, "method": "execCommandApproval", "params": { "callId": "exec", "conversationId": "native" } }),
            json!({ "id": 11, "method": "applyPatchApproval", "params": { "callId": "patch", "conversationId": "native" } }),
            json!({ "id": 12, "method": "execCommandApproval", "params": { "callId": "again", "conversationId": "native" } }),
            delta("done"),
        ]),
        config(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    provider.next_event().await.unwrap().unwrap();
    answer(&mut provider, "exec", ApprovalDecision::AcceptForSession).await;
    provider.next_event().await.unwrap().unwrap();
    answer(&mut provider, "patch", ApprovalDecision::Decline).await;
    let done = provider.next_event().await.unwrap().unwrap();
    assert_eq!(done.kind, EventKind::ContentDelta);

    let decisions: Vec<_> = provider
        .transport()
        .writes()
        .iter()
        .filter(|write| write.get("result").is_some())
        .map(|write| write["result"]["decision"].clone())
        .collect();
    assert_eq!(
        decisions,
        vec![
            json!("approved_for_session"),
            json!({ "denied": { "rejection": "User declined the request." } }),
            json!("approved_for_session"),
        ]
    );
}
