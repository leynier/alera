use std::time::Duration;

use alera_provider_protocol::{ApprovalDecision, RuntimeResponse};
use serde_json::{json, Value};

use super::super::commands::{decline_request_ids, CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::fixture::*;
use crate::terminal_host::host_error::HostError;

fn redirect(id: &str, text: &str, request_ids: &[&str]) -> ChatOp {
    ChatOp::SendDecliningRequests {
        input: input(id, text),
        request_ids: request_ids.iter().map(|id| id.to_string()).collect(),
    }
}

fn pending_ids(snapshot: &Value) -> Vec<String> {
    snapshot["pendingRequests"]
        .as_array()
        .unwrap()
        .iter()
        .map(|request| request["requestId"].as_str().unwrap().to_owned())
        .collect()
}

fn conflict_code(error: HostError) -> String {
    match error {
        HostError::Conflict { code, .. } => code,
        other => panic!("expected a conflict, got {other:?}"),
    }
}

async fn wait_for_pending(runtime: &AgentChatRuntime, chat: &str, count: usize) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = runtime.snapshot(chat).await.unwrap();
            if pending_ids(&snapshot).len() >= count {
                break snapshot;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn a_redirect_declines_the_seen_approvals_and_admits_the_message_once() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Running prompt").await;
    let control = provider_control(&factory, &chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    control.request_approval(1, "native-approval-a");
    control.request_approval(1, "native-approval-b");
    let seen = pending_ids(&wait_for_pending(&runtime, &chat, 2).await);
    let seen: Vec<&str> = seen.iter().map(String::as_str).collect();

    let op = redirect("redirect", "Use the release build instead.", &seen);
    let response = runtime
        .command(&chat, op.clone(), CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert_eq!(response["delivery"], "queued");
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert!(pending_ids(&snapshot).is_empty());
    assert_eq!(snapshot["queue"][0]["clientMessageId"], "redirect");
    let declined = |responses: &[RuntimeResponse]| {
        responses
            .iter()
            .filter(|response| {
                matches!(
                    response,
                    RuntimeResponse::Approval {
                        decision: ApprovalDecision::Decline,
                        feedback: None,
                        ..
                    }
                )
            })
            .count()
    };
    assert_eq!(declined(&control.responses.lock().unwrap()), 2);

    // A retry of the same message replays its receipt without declining
    // again or queueing a second copy.
    assert_eq!(
        runtime
            .command(&chat, op, CallerCtx::runtime(), None)
            .await
            .unwrap(),
        response
    );
    assert_eq!(declined(&control.responses.lock().unwrap()), 2);
    assert_eq!(
        runtime.snapshot(&chat).await.unwrap()["queue"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_redirect_is_refused_whole_when_the_seen_approvals_are_stale() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Running prompt").await;
    let control = provider_control(&factory, &chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    control.request_approval(1, "native-approval-a");
    let first = pending_ids(&wait_for_pending(&runtime, &chat, 1).await).remove(0);
    control.request_approval(1, "native-approval-b");
    wait_for_pending(&runtime, &chat, 2).await;

    let arrived = runtime
        .command(
            &chat,
            redirect("arrived", "Stop there.", &[&first]),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert_eq!(conflict_code(arrived), "approvalsChanged");
    let answered = runtime
        .command(
            &chat,
            redirect("answered", "Stop there.", &[&first, "request-gone"]),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert_eq!(conflict_code(answered), "approvalsChanged");

    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(pending_ids(&snapshot).len(), 2);
    assert!(snapshot["queue"].as_array().unwrap().is_empty());
    assert!(control.responses.lock().unwrap().is_empty());
    runtime.shutdown().await;
    harness.finish().await;
}

#[test]
fn decline_requests_parse_strictly() {
    assert_eq!(decline_request_ids(&json!({})).unwrap(), None);
    assert_eq!(
        decline_request_ids(&json!({"declineRequests": {"requestIds": ["a", " a ", "b"]}}))
            .unwrap(),
        Some(vec!["a".to_owned(), "b".to_owned()])
    );
    for invalid in [
        json!({"declineRequests": {"requestIds": []}}),
        json!({"declineRequests": {"requestIds": [""]}}),
        json!({"declineRequests": {"requestIds": [3]}}),
        json!({"declineRequests": {"requestIds": ["a"], "feedback": "no"}}),
        json!({"declineRequests": ["a"]}),
    ] {
        assert!(decline_request_ids(&invalid).is_err(), "{invalid}");
    }
}
