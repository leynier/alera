mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, StreamKind};
use serde_json::json;
use support::{initialize_response, session_response, ScriptedTransport};

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
async fn maps_stream_delta_and_retains_full_native_frame() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        json!({
            "jsonrpc":"2.0","method":"item/delta","params":{
                "sessionId":"muse-session","turnId":"turn-1","itemId":"item-1",
                "field":"text","delta":"hello","viewCursor":"v:4"
            }
        }),
    ]);
    let mut provider = started(transport).await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::ContentDelta);
    assert_eq!(
        event.payload["streamKind"],
        json!(StreamKind::AssistantText)
    );
    assert_eq!(event.payload["delta"], "hello");
    assert_eq!(
        event.raw.as_ref().unwrap().payload["params"]["itemId"],
        "item-1"
    );
    provider.close().await.unwrap();
}

#[tokio::test]
async fn maps_failed_turn_with_canonical_error_message() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        json!({
            "jsonrpc":"2.0","method":"turn/completed","params":{
                "sessionId":"muse-session","turnId":"turn-1","terminal":"failed",
                "error":{"message":"native failure"}
            }
        }),
    ]);
    let mut provider = started(transport).await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::TurnCompleted);
    assert_eq!(event.payload["state"], "failed");
    assert_eq!(event.payload["errorMessage"], "native failure");
    assert_eq!(
        event.raw.as_ref().unwrap().message_type.as_deref(),
        Some("turn/completed")
    );
    provider.close().await.unwrap();
}

#[tokio::test]
async fn surfaces_view_gap_as_warning_without_losing_raw_cursors() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        json!({
            "jsonrpc":"2.0","method":"view/gap","params":{
                "sessionId":"muse-session","after":"v:2","next":"v:5"
            }
        }),
    ]);
    let mut provider = started(transport).await;
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RuntimeWarning);
    assert_eq!(event.payload["gap"]["after"], "v:2");
    assert_eq!(event.payload["gap"]["next"], "v:5");
    provider.close().await.unwrap();
}
