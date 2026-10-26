use alera_agent_transport::MockTransport;
use alera_provider_antigravity::{AntigravityProvider, AntigravityProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use serde_json::json;
use std::path::PathBuf;

#[tokio::test]
async fn eager_auth_and_model_do_not_elevate_explicit_session_approval() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "capabilities":{},
                "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({
            "jsonrpc":"2.0",
            "id":3,
            "result":{
                "sessionId":"agy-session",
                "configOptions":[
                    {"id":"model","type":"select","currentValue":"default","options":[]},
                    {"id":"mode","type":"select","currentValue":"default","options":[]}
                ]
            }
        }),
        json!({"jsonrpc":"2.0","id":4,"result":{}}),
    ]);
    let config = AntigravityProviderConfig {
        profile_dir: Some(PathBuf::from("/tmp/agy-profile")),
        model: Some("agy-model".into()),
        runtime_mode: alera_provider_protocol::RuntimeMode::FullAccess,
        ..Default::default()
    };
    let mut provider = AntigravityProvider::with_transport(transport, config).unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(session.native_thread_id, "agy-session");
    assert_eq!(session.model.as_deref(), Some("agy-model"));
    let writes = provider.inner().client().transport().writes();
    assert_eq!(writes[1]["method"], "auth/login");
    assert_eq!(writes[3]["method"], "session/set_config_option");
    assert_eq!(writes[3]["params"]["configId"], "model");
    assert!(writes
        .iter()
        .all(|write| write["params"]["configId"] != "mode"));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
}

#[tokio::test]
async fn full_access_session_maps_to_yolo_mode() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "capabilities":{},
                "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({
            "jsonrpc":"2.0",
            "id":3,
            "result":{
                "sessionId":"agy-session",
                "configOptions":[
                    {"id":"model","type":"select","currentValue":"default","options":[]},
                    {"id":"mode","type":"select","currentValue":"default","options":[]}
                ]
            }
        }),
        json!({"jsonrpc":"2.0","id":4,"result":{}}),
    ]);
    let mut provider =
        AntigravityProvider::with_transport(transport, AntigravityProviderConfig::default())
            .unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = alera_provider_protocol::RuntimeMode::FullAccess;
    provider.start_session(input).await.unwrap();
    let writes = provider.inner().client().transport().writes();
    assert_eq!(writes[3]["method"], "session/set_config_option");
    assert_eq!(writes[3]["params"]["configId"], "mode");
    assert_eq!(writes[3]["params"]["value"], "yolo");
}

#[tokio::test]
async fn skill_mentions_reach_antigravity_unchanged() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":true}},
                "capabilities":{},
                "authMethods":[{"id":"oauth-personal","name":"Personal OAuth"}]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({
            "jsonrpc":"2.0",
            "id":3,
            "result":{
                "sessionId":"agy-session",
                "configOptions":[{"id":"mode","type":"select","currentValue":"default","options":[]}]
            }
        }),
    ]);
    let mut provider =
        AntigravityProvider::with_transport(transport, AntigravityProviderConfig::default())
            .unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(alera_provider_protocol::TurnInput::text(
            "app-thread",
            "$review fix it",
        ))
        .await
        .unwrap();
    let writes = provider.inner().client().transport().writes();
    let prompt = writes
        .iter()
        .find(|write| write["method"] == "session/prompt")
        .expect("prompt request");
    assert_eq!(prompt["params"]["prompt"][0]["text"], "$review fix it");
}
