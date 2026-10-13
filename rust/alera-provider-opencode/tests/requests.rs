use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    EventKind, Provider, RequestKind, RuntimeResponse, SessionStartInput, TurnInput,
};
use serde_json::json;
use std::collections::BTreeMap;

fn response(value: serde_json::Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).unwrap())
}

#[tokio::test]
async fn permission_request_keeps_native_id_and_replies_on_v2_route() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(response(json!({"id":"m1"})));
    transport.push_response(response(json!({"ok":true})));
    transport.push_stream([br#"data: {"type":"permission.asked","data":{"sessionID":"s1","id":"permission-7","permission":"bash","patterns":["ls"]}}

"#.to_vec()]);
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "run"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::RequestOpened);
    assert_eq!(request.request_id.as_deref(), Some("permission-7"));
    assert_eq!(
        request.runtime_request.as_ref().unwrap().kind,
        RequestKind::CommandExecutionApproval
    );
    provider
        .respond(RuntimeResponse::Approval {
            request_id: "permission-7".into(),
            decision: alera_provider_protocol::ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    let requests = provider.client().transport().captured_requests();
    assert_eq!(
        requests.last().unwrap().path,
        "http://127.0.0.1:4096/api/session/s1/permission/permission-7/reply"
    );
    let body: serde_json::Value = serde_json::from_slice(&requests.last().unwrap().body).unwrap();
    assert_eq!(body["decision"], "once");
}

#[tokio::test]
async fn question_request_maps_answers_by_question_id() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(response(json!({"id":"m1"})));
    transport.push_response(response(json!({"ok":true})));
    transport.push_stream([br#"data: {"type":"question.asked","data":{"sessionID":"s1","id":"question-2","questions":[{"header":"choice","question":"Pick","options":[{"label":"A","value":"a"}]}]}}

"#.to_vec()]);
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "choose"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    let question_id = request.runtime_request.as_ref().unwrap().questions[0]
        .id
        .clone();
    let mut answers = BTreeMap::new();
    answers.insert(question_id, json!("a"));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: "question-2".into(),
            answers,
        })
        .await
        .unwrap();
    let requests = provider.client().transport().captured_requests();
    let request = requests.last().unwrap();
    assert_eq!(
        request.path,
        "http://127.0.0.1:4096/api/session/s1/form/question-2/reply"
    );
    let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
    assert_eq!(body["answer"]["choice"][0], "a");
}

#[tokio::test]
async fn v2_form_request_maps_fields_and_replies_with_form_id() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(response(json!({"id":"m1"})));
    transport.push_response(response(json!({"ok":true})));
    transport.push_stream([br#"data: {"type":"form.created","data":{"form":{"id":"form-2","sessionID":"s1","title":"Choose","fields":[{"key":"choice","title":"Choice","description":"Pick one","type":"string","options":[{"label":"A","value":"a"}]}]}}}

"#.to_vec()]);
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "choose"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::UserInputRequested);
    assert_eq!(request.request_id.as_deref(), Some("form-2"));
    assert_eq!(
        request.runtime_request.as_ref().unwrap().questions[0].id,
        "choice"
    );
    let mut answers = BTreeMap::new();
    answers.insert("choice".into(), json!("a"));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: "form-2".into(),
            answers,
        })
        .await
        .unwrap();
    let requests = provider.client().transport().captured_requests();
    let request = requests.last().unwrap();
    assert_eq!(
        request.path,
        "http://127.0.0.1:4096/api/session/s1/form/form-2/reply"
    );
    let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
    assert_eq!(body["answer"]["choice"], "a");
}
