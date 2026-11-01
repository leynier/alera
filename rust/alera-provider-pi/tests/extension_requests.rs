use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput};
use serde_json::{json, Value};

async fn started(after_start: Vec<Value>) -> PiProvider<MockTransport> {
    let mut script = vec![json!({
        "type": "response",
        "id": "alera-pi-1",
        "command": "get_state",
        "success": true,
        "data": { "sessionFile": "/tmp/pi/session.jsonl", "isStreaming": false }
    })];
    script.extend(after_start);
    let mut provider = PiProvider::new(MockTransport::new(script), PiProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    for kind in [EventKind::SessionStarted, EventKind::ThreadStarted] {
        assert_eq!(next(&mut provider).await.kind, kind);
    }
    provider
}

async fn next(provider: &mut PiProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

#[tokio::test]
async fn notifications_are_notices_and_blank_ones_stay_native_records() {
    let warning = json!({
        "type": "extension_ui_request",
        "id": "ui-notify",
        "method": "notify",
        "message": "Command finished\nwith details",
        "notifyType": "warning"
    });
    let blank = json!({
        "type": "extension_ui_request",
        "method": "notify",
        "message": " \n"
    });
    let mut provider = started(vec![warning.clone(), blank.clone()]).await;
    let notice = next(&mut provider).await;
    assert_eq!(notice.kind, EventKind::RuntimeWarning);
    assert_eq!(notice.payload["message"], "Command finished\nwith details");
    assert_eq!(notice.payload["notifyType"], "warning");
    assert!(notice.request_id.is_none());
    let unknown = next(&mut provider).await;
    assert_eq!(
        unknown.kind,
        EventKind::Unknown("extension_ui_request".into())
    );
    assert_eq!(unknown.payload, blank);
}

#[tokio::test]
async fn blank_placeholders_fall_back_to_the_title() {
    let input = json!({
        "type": "extension_ui_request",
        "id": "ui-input",
        "method": "input",
        "title": "Branch name",
        "message": "",
        "placeholder": "  "
    });
    let described = json!({
        "type": "extension_ui_request",
        "id": "ui-editor",
        "method": "editor",
        "title": "Notes",
        "message": " ",
        "placeholder": "Describe the change"
    });
    let mut provider = started(vec![input, described]).await;
    let request = next(&mut provider).await;
    assert_eq!(request.kind, EventKind::UserInputRequested);
    let question = &request.runtime_request.unwrap().questions[0];
    assert_eq!(question.question, "Branch name");
    let request = next(&mut provider).await;
    let question = &request.runtime_request.unwrap().questions[0];
    assert_eq!(question.question, "Describe the change");
}
