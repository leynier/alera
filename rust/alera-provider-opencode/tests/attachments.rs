use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    Attachment, FailureClass, Provider, ProviderError, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\nimage";
const JPEG: &[u8] = b"\xff\xd8\xff\xe0jpeg";

/// A fresh directory for one test's attachment files.
fn scratch() -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let directory = std::env::temp_dir().join(format!(
        "alera-opencode-attachments-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&directory);
    std::fs::create_dir_all(&directory).unwrap();
    directory
}

fn write(directory: &Path, name: &str, bytes: &[u8]) -> PathBuf {
    let path = directory.join(name);
    std::fs::write(&path, bytes).unwrap();
    path
}

fn data_url(mime: &str, bytes: &[u8]) -> String {
    let part = alera_provider_opencode::opencode_agent_sdk::inline_file_part(mime, "x", bytes);
    part["url"].as_str().unwrap().to_owned()
}

async fn provider(generation: OpenCodeGeneration) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"s1"})).unwrap(),
    ));
    // The session start lists commands; a failed listing publishes nothing.
    transport.push_response(HttpResponse::new(404, Vec::new()));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"m1"})).unwrap(),
    ));
    transport.push_stream(Vec::<Vec<u8>>::new());
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
}

fn turn(text: &str, attachments: Vec<Attachment>) -> TurnInput {
    let mut input = TurnInput::text("thread", text);
    input.attachments = attachments;
    input
}

fn prompt_body(provider: &OpenCodeProvider<MockHttpTransport>) -> Value {
    let requests = provider.client().transport().captured_requests();
    let prompt = requests
        .iter()
        .find(|request| request.path.contains("/prompt"))
        .expect("prompt request");
    serde_json::from_slice(&prompt.body).unwrap()
}

#[tokio::test]
async fn v2_sends_a_pasted_image_inline_with_its_name() {
    let directory = scratch();
    let image = write(&directory, "paste.data.png", PNG);
    let mut provider = provider(OpenCodeGeneration::V2).await;
    provider
        .send_turn(turn(
            "What is this?",
            vec![Attachment::LocalImage { path: image }],
        ))
        .await
        .unwrap();
    assert_eq!(
        prompt_body(&provider)["files"],
        json!([{"uri": data_url("image/png", PNG), "name": "paste.data.png"}])
    );
    assert_eq!(prompt_body(&provider)["text"], "What is this?");
}

#[tokio::test]
async fn legacy_sends_images_pdfs_and_plain_text_as_typed_file_parts() {
    let directory = scratch();
    let image = write(&directory, "photo.data.png", JPEG);
    let pdf = write(&directory, "spec.data.pdf", b"%PDF-1.7");
    let text = write(&directory, "notes.data.txt", b"plain notes");
    let mut provider = provider(OpenCodeGeneration::Legacy1).await;
    provider
        .send_turn(turn(
            "",
            vec![
                Attachment::LocalImage { path: image },
                Attachment::File {
                    path: pdf,
                    name: None,
                },
                Attachment::File {
                    path: text,
                    name: None,
                },
            ],
        ))
        .await
        .unwrap();
    let parts = prompt_body(&provider)["parts"].clone();
    // The bytes decide the type, whatever the file is named.
    assert_eq!(
        parts,
        json!([
            {"type":"file","mime":"image/jpeg","filename":"photo.data.png","url":data_url("image/jpeg", JPEG)},
            {"type":"file","mime":"application/pdf","filename":"spec.data.pdf","url":data_url("application/pdf", b"%PDF-1.7")},
            {"type":"file","mime":"text/plain","filename":"notes.data.txt","url":data_url("text/plain", b"plain notes")}
        ])
    );
}

#[tokio::test]
async fn other_types_ride_only_as_their_path() {
    let directory = scratch();
    let markdown = write(&directory, "readme.data.md", b"# Title");
    let html = write(&directory, "page.data.html", b"<html></html>");
    let bitmap = write(&directory, "shot.data.bmp", b"BM\x00\x00");
    let large = write(&directory, "large.data.png", PNG);
    std::fs::File::options()
        .write(true)
        .open(&large)
        .unwrap()
        .set_len(20 * 1024 * 1024 + 1)
        .unwrap();
    let mut provider = provider(OpenCodeGeneration::V2).await;
    provider
        .send_turn(turn(
            "Read these",
            vec![
                Attachment::File {
                    path: markdown.clone(),
                    name: None,
                },
                Attachment::File {
                    path: html.clone(),
                    name: None,
                },
                Attachment::LocalImage {
                    path: bitmap.clone(),
                },
                Attachment::LocalImage {
                    path: large.clone(),
                },
            ],
        ))
        .await
        .unwrap();
    let body = prompt_body(&provider);
    assert!(body.get("files").is_none());
    assert_eq!(
        body["text"],
        format!(
            "Read these\n\n[Attached file is saved at: {}]\n\n[Attached file is saved at: {}]\n\n[Attached image is saved at: {}]\n\n[Attached image is saved at: {}]",
            markdown.display(),
            html.display(),
            bitmap.display(),
            large.display()
        )
    );
}

#[tokio::test]
async fn an_unreadable_attachment_fails_the_turn_before_it_is_sent() {
    let directory = scratch();
    let mut provider = provider(OpenCodeGeneration::V2).await;
    let error = provider
        .send_turn(turn(
            "Look",
            vec![Attachment::LocalImage {
                path: directory.join("missing.png"),
            }],
        ))
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Rejected { .. }));
    assert_eq!(error.failure_class(), FailureClass::AttachmentUnreadable);
    assert!(provider.session().unwrap().active_turn_id.is_none());
    assert!(!provider
        .client()
        .transport()
        .captured_requests()
        .iter()
        .any(|request| request.path.contains("/prompt")));
}
