use std::time::Duration;

use alera_provider_protocol::RuntimeResponse;
use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp};
use super::super::AgentChatRuntime;
use super::fixture::*;

async fn pending_request(runtime: &AgentChatRuntime, chat: &str) -> Option<String> {
    runtime.snapshot(chat).await.unwrap()["pendingRequests"]
        .as_array()
        .unwrap()
        .first()
        .map(|request| request["requestId"].as_str().unwrap().to_owned())
}

fn answer(request_id: &str, answers: Value) -> ChatOp {
    ChatOp::Respond {
        runtime_request_id: request_id.to_owned(),
        response: json!({"type": "userInput", "answers": answers}),
    }
}

#[tokio::test]
async fn an_unusable_answer_leaves_the_question_open() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Ask me").await;
    let control = provider_control(&factory, &chat).await;
    control.wait_turns(1).await;
    control.request_input(1, "native-question");
    let request_id = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(id) = pending_request(&runtime, &chat).await {
                break id;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    for answers in [
        json!({"other": "x"}),
        json!({"choice": "  "}),
        json!({"choice": 3}),
    ] {
        let error = runtime
            .command(
                &chat,
                answer(&request_id, answers),
                CallerCtx::runtime(),
                None,
            )
            .await
            .unwrap_err();
        assert_eq!(error.wire_response(1)["errorCode"], "invalidAnswers");
        assert_eq!(
            pending_request(&runtime, &chat).await.as_deref(),
            Some(request_id.as_str())
        );
    }
    assert!(control.responses.lock().unwrap().is_empty());
    let resolved = runtime
        .command(
            &chat,
            answer(&request_id, json!({"choice": {"answers": ["Staging"]}})),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(resolved["resolved"], true);
    let responses = control.responses.lock().unwrap().clone();
    assert!(matches!(
        &responses[..],
        [RuntimeResponse::UserInput { answers, .. }] if answers["choice"] == json!(["Staging"])
    ));
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_slash_command_reaches_the_provider_verbatim_and_the_merge_waits() {
    let (harness, runtime, factory) = fixture().await;
    let source = create(&runtime, None).await;
    let first = send(&runtime, &source, "first", "Plan the cache").await;
    let control = provider_control(&factory, &source).await;
    control.wait_turns(1).await;
    finish_turn(&runtime, &factory, &source, 1).await;
    let forked = runtime
        .fork(
            &source,
            first["turnId"].as_str().unwrap(),
            Some("Cache experiment".into()),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let fork = forked["chatId"].as_str().unwrap().to_owned();
    send(&runtime, &fork, "fork-first", "Try an LRU cache").await;
    provider_control(&factory, &fork).await.wait_turns(1).await;
    finish_turn(&runtime, &factory, &fork, 1).await;
    runtime
        .merge_back(&fork, CallerCtx::runtime(), None)
        .await
        .unwrap();

    send(&runtime, &source, "compact", "/compact").await;
    control.wait_turns(2).await;
    assert_eq!(control.turns.lock().unwrap()[1].input, "/compact");
    finish_turn(&runtime, &factory, &source, 2).await;
    send(&runtime, &source, "second", "Which one wins?").await;
    control.wait_turns(3).await;
    let input = control.turns.lock().unwrap()[2].input.clone();
    assert!(input.starts_with("Work merged back from forks of this conversation."));
    assert!(input.ends_with("New message:\nWhich one wins?"));
    finish_turn(&runtime, &factory, &source, 3).await;
    runtime.shutdown().await;
    harness.finish().await;
}
