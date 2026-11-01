use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig, PI_MAX_FRAME_BYTES};
use alera_provider_protocol::{
    Attachment, EventKind, Provider, ProviderError, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\n\x01\x02\x03";
const PNG_BASE64: &str = "iVBORw0KGgoBAgM=";

/// A scratch directory removed when the test ends.
struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "alera-pi-attachments-{}-{name}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn file(&self, name: &str, bytes: &[u8]) -> PathBuf {
        let path = self.0.join(name);
        std::fs::write(&path, bytes).unwrap();
        path
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

async fn started(max_frame_bytes: usize) -> PiProvider<MockTransport> {
    let state = json!({
        "type": "response",
        "id": "alera-pi-1",
        "command": "get_state",
        "success": true,
        "data": { "sessionFile": "/tmp/pi/session.jsonl", "isStreaming": false }
    });
    let mut provider = PiProvider::new(
        MockTransport::new(vec![state]),
        PiProviderConfig {
            max_frame_bytes,
            ..PiProviderConfig::default()
        },
    );
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    for kind in [EventKind::SessionStarted, EventKind::ThreadStarted] {
        assert_eq!(provider.next_event().await.unwrap().unwrap().kind, kind);
    }
    provider
}

async fn prompt(max_frame_bytes: usize, text: &str, attachments: Vec<Attachment>) -> Value {
    let mut provider = started(max_frame_bytes).await;
    let mut input = TurnInput::text("thread", text);
    input.attachments = attachments;
    provider.send_turn(input).await.unwrap();
    let prompt = provider.transport().writes().last().unwrap().clone();
    assert_eq!(prompt["type"], "prompt");
    prompt
}

fn saved(kind: &str, path: &Path, note: &str) -> String {
    let name = path.file_name().unwrap().to_string_lossy();
    format!(
        "[Attached {kind} \"{name}\" is saved at: {}{note}]",
        path.display()
    )
}

#[tokio::test]
async fn local_images_travel_as_native_images_and_name_their_saved_path() {
    let scratch = Scratch::new("inline");
    let image = scratch.file("shot.png", PNG);
    let prompt = prompt(
        PI_MAX_FRAME_BYTES,
        "What is this?",
        vec![Attachment::LocalImage {
            path: image.clone(),
        }],
    )
    .await;
    assert_eq!(
        prompt["message"],
        format!("What is this?\n\n{}", saved("image", &image, ""))
    );
    assert_eq!(
        prompt["images"],
        json!([{ "type": "image", "data": PNG_BASE64, "mimeType": "image/png" }])
    );
}

#[tokio::test]
async fn files_and_unreadable_images_are_named_instead_of_failing_the_turn() {
    let scratch = Scratch::new("named");
    let notes = scratch.file("notes.txt", b"remember the parser");
    let missing = scratch.0.join("missing.png");
    let prompt = prompt(
        PI_MAX_FRAME_BYTES,
        "",
        vec![
            Attachment::File {
                path: notes.clone(),
                name: None,
            },
            Attachment::LocalImage {
                path: missing.clone(),
            },
        ],
    )
    .await;
    let message = prompt["message"].as_str().unwrap();
    let (file, image) = message.split_once("\n\n").unwrap();
    assert_eq!(file, saved("file", &notes, ""));
    let unavailable = format!(
        "[Attached image \"missing.png\" is unavailable: could not read {}: ",
        missing.display()
    );
    assert!(image.starts_with(&unavailable), "{image}");
    assert!(prompt.get("images").is_none());
}

#[tokio::test]
async fn images_that_cannot_go_inline_keep_their_saved_path() {
    let scratch = Scratch::new("path-only");
    let text = scratch.file("diagram.png", b"hi");
    let image = scratch.file("shot.png", PNG);
    // Half of a 16-byte frame holds the text but not the image in base64.
    let prompt = prompt(
        16,
        "Compare",
        vec![
            Attachment::LocalImage { path: text.clone() },
            Attachment::LocalImage {
                path: image.clone(),
            },
        ],
    )
    .await;
    assert_eq!(
        prompt["message"],
        format!(
            "Compare\n\n{}\n\n{}",
            saved(
                "image",
                &text,
                " (not a PNG, JPEG, GIF or WebP image; not sent inline)"
            ),
            saved("image", &image, " (too large to send inline)")
        )
    );
    assert!(prompt.get("images").is_none());
}

#[tokio::test]
async fn data_url_images_share_the_inline_budget() {
    let image = |data: &str| Attachment::Image {
        url: format!("data:image/png;base64,{data}"),
    };
    let prompt = prompt(64, "Look", vec![image("AQID")]).await;
    assert_eq!(prompt["message"], "Look");
    assert_eq!(
        prompt["images"],
        json!([{ "type": "image", "data": "AQID", "mimeType": "image/png" }])
    );

    let mut provider = started(64).await;
    let writes = provider.transport().writes().len();
    let mut input = TurnInput::text("thread", "Look");
    input.attachments = vec![image("AQID"), image(&"A".repeat(32))];
    assert!(matches!(
        provider.send_turn(input).await,
        Err(ProviderError::Validation(_))
    ));
    assert_eq!(provider.transport().writes().len(), writes);
    assert!(provider.session().unwrap().active_turn_id.is_none());
}
