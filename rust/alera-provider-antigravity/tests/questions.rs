//! Antigravity's `interaction_*` permission requests are single-choice
//! questions, ported from T3 Code's `AntigravityProtocol.test.ts` fixture.

use alera_agent_transport::MockTransport;
use alera_provider_antigravity::{AntigravityProvider, AntigravityProviderConfig};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, InterruptInput, Provider, ProviderError, ProviderEvent,
    RequestKind, RuntimeResponse, SessionStartInput, TurnInput, UserInputAnswers,
};
use serde_json::{json, Value};
use std::time::Duration;

fn question(options: Value, title: Value) -> Value {
    json!({"jsonrpc":"2.0","id":"q1","method":"session/request_permission","params":{
        "sessionId":"agy-session",
        "toolCall":{"toolCallId":"interaction_9960062f","status":"pending","title":title,"rawInput":{}},
        "options":options
    }})
}

fn captured() -> Value {
    question(
        json!([
            {"optionId":"1","name":"Verified","kind":"allow_once"},
            {"optionId":"2","name":"Needs review","kind":"allow_once"}
        ]),
        json!("Which result label should be used for the verification?"),
    )
}

async fn opened(request: Value) -> (AntigravityProvider<MockTransport>, ProviderEvent) {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},
            "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({"jsonrpc":"2.0","id":3,"result":{"sessionId":"agy-session"}}),
        request,
    ]);
    let config = AntigravityProviderConfig {
        request_timeout: Duration::from_millis(200),
        ..Default::default()
    };
    let mut provider = AntigravityProvider::with_transport(transport, config).unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "verify"))
        .await
        .unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if matches!(
            event.kind,
            EventKind::UserInputRequested | EventKind::RequestOpened
        ) {
            return (provider, event);
        }
    }
}

fn answer(event: &ProviderEvent, answers: UserInputAnswers) -> RuntimeResponse {
    RuntimeResponse::UserInput {
        request_id: event.runtime_request.as_ref().unwrap().request_id.clone(),
        answers,
    }
}

fn answers(value: Value) -> UserInputAnswers {
    UserInputAnswers::from([("interaction_9960062f".to_owned(), value)])
}

fn last_write(provider: &AntigravityProvider<MockTransport>) -> Value {
    provider
        .inner()
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone()
}

#[tokio::test]
async fn an_interaction_opens_a_single_choice_question() {
    let (_, event) = opened(captured()).await;
    assert_eq!(event.kind, EventKind::UserInputRequested);
    let request = event.runtime_request.as_ref().unwrap();
    assert_eq!(request.kind, RequestKind::ToolUserInput);
    let question = &request.questions[0];
    assert_eq!(question.id, "interaction_9960062f");
    assert_eq!(question.header, "Question");
    assert_eq!(
        question.question,
        "Which result label should be used for the verification?"
    );
    assert_eq!(question.allow_custom_answer, Some(false));
    assert!(!question.multi_select);
    let options: Vec<_> = question
        .options
        .iter()
        .map(|option| (option.value.clone().unwrap(), option.label.clone()))
        .collect();
    assert_eq!(
        options,
        vec![
            ("1".to_owned(), "Verified".to_owned()),
            ("2".to_owned(), "Needs review".to_owned())
        ]
    );
}

#[tokio::test]
async fn the_answer_selects_the_native_option_by_id_or_unique_label() {
    for value in [json!("1"), json!(["1"]), json!("Verified")] {
        let (mut provider, event) = opened(captured()).await;
        provider
            .respond(answer(&event, answers(value)))
            .await
            .unwrap();
        let write = last_write(&provider);
        assert_eq!(write["id"], "q1");
        assert_eq!(
            write["result"],
            json!({"outcome":{"outcome":"selected","optionId":"1"}})
        );
    }
}

#[tokio::test]
async fn ambiguous_or_unknown_answers_are_refused_and_the_question_stays_open() {
    let same_label = question(
        json!([
            {"optionId":"1","name":"Same label","kind":"allow_once"},
            {"optionId":"2","name":"Same label","kind":"allow_once"}
        ]),
        json!("Pick"),
    );
    let (mut provider, event) = opened(same_label).await;
    for value in [
        json!("Same label"),
        json!("free text"),
        json!(["1", "2"]),
        json!(1),
    ] {
        let error = provider
            .respond(answer(&event, answers(value)))
            .await
            .unwrap_err();
        assert!(matches!(error, ProviderError::Validation(_)), "{error:?}");
    }
    assert_eq!(provider.inner().pending_request_count(), 1);
    provider
        .respond(answer(&event, answers(json!("2"))))
        .await
        .unwrap();
    assert_eq!(
        last_write(&provider)["result"],
        json!({"outcome":{"outcome":"selected","optionId":"2"}})
    );
}

#[tokio::test]
async fn skip_and_interrupt_cancel_the_question() {
    let (mut provider, event) = opened(captured()).await;
    provider
        .respond(answer(&event, UserInputAnswers::new()))
        .await
        .unwrap();
    assert_eq!(
        last_write(&provider)["result"],
        json!({"outcome":{"outcome":"cancelled"}})
    );

    let (mut provider, _) = opened(captured()).await;
    provider
        .interrupt(InterruptInput {
            thread_id: "app-thread".into(),
            turn_id: None,
        })
        .await
        .unwrap();
    let writes = provider.inner().client().transport().writes();
    let response = writes.iter().find(|write| write["id"] == "q1").unwrap();
    assert_eq!(
        response["result"],
        json!({"outcome":{"outcome":"cancelled"}})
    );
}

#[tokio::test]
async fn an_approval_cannot_answer_a_question() {
    let (mut provider, event) = opened(captured()).await;
    let error = provider
        .respond(RuntimeResponse::Approval {
            request_id: event.runtime_request.unwrap().request_id,
            decision: ApprovalDecision::Accept,
            updated_input: None,
            feedback: None,
        })
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Validation(_)));
    assert_eq!(provider.inner().pending_request_count(), 1);
}

#[tokio::test]
async fn malformed_interactions_and_other_permissions_stay_approvals() {
    for request in [
        question(
            json!([
                {"optionId":"1","name":"A","kind":"allow_once"},
                {"optionId":"1","name":"B","kind":"allow_once"}
            ]),
            json!("Pick"),
        ),
        question(
            json!([{"optionId":" ","name":"A","kind":"allow_once"}]),
            json!("Pick"),
        ),
        question(json!([]), json!("Pick")),
        json!({"jsonrpc":"2.0","id":"q1","method":"session/request_permission","params":{
            "sessionId":"agy-session",
            "toolCall":{"toolCallId":"tool-1","title":"Run ls","kind":"execute"},
            "options":[{"optionId":"1","name":"Allow","kind":"allow_once"}]
        }}),
    ] {
        let (_, event) = opened(request).await;
        assert_eq!(event.kind, EventKind::RequestOpened);
        assert_ne!(
            event.runtime_request.unwrap().kind,
            RequestKind::ToolUserInput
        );
    }
}

#[tokio::test]
async fn question_text_and_labels_are_bounded_without_changing_ids() {
    let (_, event) = opened(question(
        json!([{"optionId":"opaque id","name":"x".repeat(600),"kind":"allow_once"}]),
        json!("q".repeat(9_000)),
    ))
    .await;
    let question = &event.runtime_request.unwrap().questions[0];
    assert_eq!(question.question.chars().count(), 8_000);
    assert!(question.question.ends_with("..."));
    assert_eq!(question.options[0].label.chars().count(), 512);
    assert_eq!(question.options[0].value.as_deref(), Some("opaque id"));
}
