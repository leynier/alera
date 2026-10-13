mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, RuntimeResponse, SessionStartInput, UserInputAnswers,
};
use serde_json::json;
use support::{initialize_response, response, session_response, ScriptedTransport};

async fn started(transport: ScriptedTransport) -> MuseProvider {
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await;
    let _ = provider.next_event().await;
    provider
}

#[tokio::test]
async fn approval_preserves_wire_id_and_selects_an_offered_choice() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        json!({
            "jsonrpc":"2.0","id":77,"method":"approval/request",
            "params":{
                "approvalId":"approval-1","sessionId":"muse-session","turnId":"turn-1",
                "itemId":"item-1","toolName":"shell","availableChoices":[
                    {"choiceId":"native-once","decision":"approved","label":"Allow once","scope":"once"},
                    {"choiceId":"native-abort","decision":"abort","label":"Cancel","scope":"once"}
                ],"currentRequirementId":{"approvalId":"approval-1","sourceIndex":0},
                "subject":{"kind":"command"}
            }
        }),
        response(3, json!({"status":"accepted"})),
    ]);
    let writes = transport.writes.clone();
    let mut provider = started(transport).await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    assert_eq!(event.request_id.as_deref(), Some("approval-1"));
    assert_eq!(event.raw.as_ref().unwrap().payload["id"], 77);
    provider
        .respond(RuntimeResponse::Approval {
            request_id: "approval-1".into(),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(writes[3]["id"], 77);
    assert_eq!(writes[3]["result"], json!({}));
    assert_eq!(writes[4]["method"], "approval/decide");
    assert_eq!(writes[4]["params"]["approvalId"], "approval-1");
    assert_eq!(writes[4]["params"]["choiceId"], "native-once");
    provider.close().await.unwrap();
}

#[tokio::test]
async fn user_input_answers_keep_native_labels() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        json!({
            "jsonrpc":"2.0","method":"userInput/request","params":{
                "userInputId":"input-1","sessionId":"muse-session","turnId":"turn-1",
                "itemId":"item-1","toolName":"ask","questions":[{
                    "id":"q-1","header":"Choice","question":"Pick one",
                    "options":[{"label":"Alpha","description":"A"}],
                    "selection":{"mode":"single"}
                }]
            }
        }),
        response(3, json!({"status":"accepted"})),
    ]);
    let writes = transport.writes.clone();
    let mut provider = started(transport).await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::UserInputRequested);
    let mut answers = UserInputAnswers::new();
    answers.insert("q-1".into(), json!("Alpha"));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: "input-1".into(),
            answers,
        })
        .await
        .unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(writes[3]["method"], "userInput/answer");
    assert_eq!(writes[3]["params"]["answers"][0]["selectedLabel"], "Alpha");
    provider.close().await.unwrap();
}
