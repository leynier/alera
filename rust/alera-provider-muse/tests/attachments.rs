mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{
    Attachment, FailureClass, Provider, ProviderError, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use support::{initialize_response, response, session_response, ScriptedTransport};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\nmuse!";
const PNG_BASE64: &str = "iVBORw0KGgptdXNlIQ==";

struct Started {
    provider: MuseProvider,
    writes: Arc<Mutex<Vec<Value>>>,
}

async fn started(config: MuseProviderConfig) -> Started {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "muse-session"),
        response(
            3,
            json!({"status":"accepted","turnId":"turn-1","startedNewTurn":true,"disposition":"started"}),
        ),
    ]);
    let writes = transport.writes.clone();
    let mut provider = MuseProvider::with_transport(transport, config).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    Started { provider, writes }
}

fn scratch_dir() -> PathBuf {
    let path = std::env::temp_dir().join(format!("muse-attachments-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn turn(text: &str, attachments: Vec<Attachment>) -> TurnInput {
    let mut input = TurnInput::text("app-thread", text);
    input.attachments = attachments;
    input
}

fn turn_start(writes: &Arc<Mutex<Vec<Value>>>) -> Option<Value> {
    writes
        .lock()
        .unwrap()
        .iter()
        .find(|frame| frame["method"] == "turn/start")
        .map(|frame| frame["params"].clone())
}

#[tokio::test]
async fn sends_images_natively_and_names_every_local_attachment_by_path() {
    let dir = scratch_dir();
    let image = dir.join("upload.data.png");
    let bitmap = dir.join("upload.data.bmp");
    let document = dir.join("upload.data.pdf");
    std::fs::write(&image, PNG).unwrap();
    std::fs::write(&bitmap, b"BM").unwrap();
    std::fs::write(&document, b"%PDF").unwrap();
    let Started {
        mut provider,
        writes,
    } = started(MuseProviderConfig::default()).await;
    provider
        .send_turn(turn(
            "Review these.",
            vec![
                Attachment::LocalImage {
                    path: image.clone(),
                },
                Attachment::LocalImage {
                    path: bitmap.clone(),
                },
                Attachment::File {
                    path: document.clone(),
                    name: None,
                },
            ],
        ))
        .await
        .unwrap();
    let params = turn_start(&writes).unwrap();
    let text = params["input"][0]["text"].as_str().unwrap();
    assert!(text.starts_with("Review these.\n\n"));
    for (kind, path) in [("image", &image), ("image", &bitmap), ("file", &document)] {
        assert!(text.contains(&format!(
            "[Attached {kind} is saved at: {}]",
            path.display()
        )));
    }
    // Only the types Muse decodes ride as image parts; the bitmap goes by path.
    assert_eq!(
        params["input"][1],
        json!({"type":"image","base64Data":PNG_BASE64,"mediaType":"image/png"})
    );
    assert_eq!(params["input"].as_array().unwrap().len(), 2);
    assert_eq!(params["displayText"], "Review these.");
    provider.close().await.unwrap();
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
async fn sends_an_image_only_turn_and_inline_image_data() {
    let dir = scratch_dir();
    let image = dir.join("paste.data.JPG");
    std::fs::write(&image, PNG).unwrap();
    let Started {
        mut provider,
        writes,
    } = started(MuseProviderConfig::default()).await;
    provider
        .send_turn(turn(
            "",
            vec![
                Attachment::LocalImage {
                    path: image.clone(),
                },
                Attachment::Image {
                    url: format!("data:image/webp;base64,{PNG_BASE64}"),
                },
            ],
        ))
        .await
        .unwrap();
    let params = turn_start(&writes).unwrap();
    assert_eq!(
        params["input"][0]["text"],
        format!("[Attached image is saved at: {}]", image.display())
    );
    assert_eq!(params["input"][1]["mediaType"], "image/jpeg");
    assert_eq!(
        params["input"][2],
        json!({"type":"image","base64Data":PNG_BASE64,"mediaType":"image/webp"})
    );
    assert_eq!(params["displayText"], "Image attachment");
    provider.close().await.unwrap();
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
async fn text_turns_keep_their_plain_input() {
    let Started {
        mut provider,
        writes,
    } = started(MuseProviderConfig::default()).await;
    provider.send_turn(turn("hello", Vec::new())).await.unwrap();
    let params = turn_start(&writes).unwrap();
    assert_eq!(params["input"], json!([{"type":"text","text":"hello"}]));
    assert!(params.get("displayText").is_none());
    provider.close().await.unwrap();
}

#[tokio::test]
async fn refuses_attachments_it_cannot_send_before_starting_a_turn() {
    let dir = scratch_dir();
    let large = dir.join("large.data.png");
    std::fs::write(&large, vec![0_u8; 8 * 1024]).unwrap();
    let mut config = MuseProviderConfig::default();
    config.options.max_frame_bytes = 20 * 1024;
    let Started {
        mut provider,
        writes,
    } = started(config).await;
    let missing = provider
        .send_turn(turn(
            "look",
            vec![Attachment::LocalImage {
                path: dir.join("missing.data.png"),
            }],
        ))
        .await
        .unwrap_err();
    assert_eq!(missing.failure_class(), FailureClass::AttachmentUnreadable);
    let remote = provider
        .send_turn(turn(
            "look",
            vec![Attachment::Image {
                url: "https://example.test/cat.png".into(),
            }],
        ))
        .await
        .unwrap_err();
    assert!(matches!(remote, ProviderError::Unsupported(_)));
    // Past the frame limit the transport would close, so the turn is refused.
    let oversized = provider
        .send_turn(turn("look", vec![Attachment::LocalImage { path: large }]))
        .await
        .unwrap_err();
    assert!(matches!(oversized, ProviderError::Validation(_)));
    assert!(turn_start(&writes).is_none());
    assert!(provider.session().unwrap().active_turn_id.is_none());
    provider.close().await.unwrap();
    std::fs::remove_dir_all(dir).unwrap();
}
