use alera_provider_protocol::ProviderError;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp, ReceiptKey};
use super::super::AgentChatRuntime;
use super::fixture::*;
use crate::terminal_host::host_error::HostResult;

fn feedback(reason: Option<&str>) -> ChatOp {
    ChatOp::Feedback {
        reason: reason.map(str::to_owned),
    }
}

fn key(request_id: &str, digest: &str) -> Option<ReceiptKey> {
    Some(ReceiptKey {
        verb: "agentChat.feedback".into(),
        request_id: request_id.into(),
        digest: digest.into(),
    })
}

async fn upload(
    runtime: &AgentChatRuntime,
    chat: &str,
    reason: Option<&str>,
    receipt: Option<ReceiptKey>,
) -> HostResult<Value> {
    runtime
        .command(chat, feedback(reason), CallerCtx::runtime(), receipt)
        .await
}

fn code(result: HostResult<Value>) -> String {
    let error = result.expect_err("feedback should be refused");
    error.wire_response(0)["errorCode"]
        .as_str()
        .unwrap_or_default()
        .to_owned()
}

#[tokio::test]
async fn a_chat_without_a_message_refuses_feedback_as_t3_code_does() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    let error = upload(&runtime, &chat, None, None)
        .await
        .expect_err("a never-sent chat has no thread");
    assert_eq!(
        error.wire_response(0)["errorCode"],
        "feedbackNeedsConversation"
    );
    assert_eq!(
        error.wire_message(),
        "Send a message before you submit feedback."
    );
    assert!(factory.recorded.feedback.lock().unwrap().is_empty());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn an_idle_chat_uploads_once_per_request_and_keeps_its_transcript() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Explain the bug").await;
    provider_control(&factory, &chat).await.wait_turns(1).await;
    finish_turn(&runtime, &factory, &chat, 1).await;
    let before = runtime.snapshot(&chat).await.unwrap();

    let answer = upload(
        &runtime,
        &chat,
        Some("  The diff was empty. "),
        key("fb-1", "a"),
    )
    .await
    .unwrap();
    assert_eq!(answer, json!({"feedbackId": "feedback-1"}));
    let replay = upload(
        &runtime,
        &chat,
        Some("  The diff was empty. "),
        key("fb-1", "a"),
    )
    .await
    .unwrap();
    assert_eq!(replay, answer, "a retried request replays its receipt");
    assert_eq!(
        code(upload(&runtime, &chat, None, key("fb-1", "b")).await),
        "request_conflict"
    );
    {
        let uploads = factory.recorded.feedback.lock().unwrap();
        assert_eq!(uploads.len(), 1);
        assert_eq!(uploads[0].reason.as_deref(), Some("The diff was empty."));
    }
    let after = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(after["items"], before["items"]);
    assert_eq!(after["turns"], before["turns"]);

    let second = upload(&runtime, &chat, Some("   "), key("fb-2", "c"))
        .await
        .unwrap();
    assert_eq!(second["feedbackId"], "feedback-2");
    assert_eq!(factory.recorded.feedback.lock().unwrap()[1].reason, None);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_running_turn_refuses_feedback_until_it_ends() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Explain the bug").await;
    provider_control(&factory, &chat).await.wait_turns(1).await;
    assert_eq!(
        code(upload(&runtime, &chat, None, None).await),
        "turnActive"
    );
    assert!(factory.recorded.feedback.lock().unwrap().is_empty());
    finish_turn(&runtime, &factory, &chat, 1).await;
    upload(&runtime, &chat, None, None).await.unwrap();
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn upload_failures_and_a_stopped_agent_come_back_as_their_own_errors() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Explain the bug").await;
    provider_control(&factory, &chat).await.wait_turns(1).await;
    finish_turn(&runtime, &factory, &chat, 1).await;

    *factory.recorded.feedback_error.lock().unwrap() = Some(ProviderError::Rpc {
        code: -32603,
        message: "feedback upload failed: offline".into(),
        data: None,
    });
    let error = upload(&runtime, &chat, None, None).await.unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "feedbackFailed");
    assert_eq!(error.wire_message(), "feedback upload failed: offline");

    *factory.recorded.feedback_error.lock().unwrap() =
        Some(ProviderError::Unsupported("feedback upload".into()));
    assert_eq!(
        code(upload(&runtime, &chat, None, None).await),
        "unsupported"
    );

    runtime
        .command(&chat, ChatOp::Stop, CallerCtx::runtime(), None)
        .await
        .unwrap();
    assert_eq!(
        code(upload(&runtime, &chat, None, None).await),
        "providerUnavailable"
    );
    assert!(factory.recorded.feedback.lock().unwrap().is_empty());
    runtime.shutdown().await;
    harness.finish().await;
}
