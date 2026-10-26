use alera_provider_codex::{CodexProvider, CodexProviderConfig, MockTransport};
use alera_provider_protocol::{Attachment, Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};

fn script() -> MockTransport {
    MockTransport::new([
        json!({ "id": 1, "result": { "codexHome": "/tmp/codex", "userAgent": "test" } }),
        json!({ "id": 2, "result": { "thread": { "id": "native-thread" } } }),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn" } } }),
        json!({ "id": 4, "result": { "turnId": "native-turn" } }),
    ])
}

fn sent_input(provider: &CodexProvider<MockTransport>, index: usize) -> Value {
    provider.transport().writes()[index]["params"]["input"].clone()
}

#[tokio::test]
async fn turn_start_and_steer_send_currency_mentions_as_dollar_mentions() {
    let mut provider = CodexProvider::new(script(), CodexProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();

    let mut turn = TurnInput::text("app", "€review the diff, it costs €25");
    turn.attachments.push(Attachment::Image {
        url: "https://example.test/screen.png".into(),
    });
    provider.send_turn(turn).await.unwrap();
    assert_eq!(provider.transport().writes()[3]["method"], "turn/start");
    assert_eq!(
        sent_input(&provider, 3),
        json!([
            { "type": "text", "text": "$review the diff, it costs €25" },
            { "type": "image", "url": "https://example.test/screen.png" },
        ])
    );

    provider
        .steer_turn(TurnInput::text("app", "also £review tests"), "native-turn")
        .await
        .unwrap();
    assert_eq!(provider.transport().writes()[4]["method"], "turn/steer");
    assert_eq!(
        sent_input(&provider, 4),
        json!([{ "type": "text", "text": "also $review tests" }])
    );
}
