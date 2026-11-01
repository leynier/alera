mod skill_fixtures;
mod support;

use alera_provider_protocol::{Attachment, Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use skill_fixtures::{write, TempDir};
use support::*;

const ONE_PAGE: &str = "%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Count 1 /Kids [3 0 R] >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R >> endobj\n%%EOF";

fn user_frame(writes: &[Value]) -> Value {
    writes
        .iter()
        .find(|frame| frame["type"] == "user")
        .expect("the prompt was written")
        .clone()
}

async fn sent_content(session: SessionStartInput, attachments: Vec<Attachment>) -> Value {
    let (mut provider, handle) = started_provider_with(
        [initialize_response(), result_message(false, None)],
        session,
    )
    .await;
    let mut turn = TurnInput::text("app-thread", "Look");
    turn.attachments = attachments;
    provider.send_turn(turn).await.unwrap();
    let writes = handle.writes.lock().unwrap();
    user_frame(&writes)["message"]["content"].clone()
}

#[tokio::test]
async fn images_and_pdfs_go_native_and_every_file_is_named() {
    let dir = TempDir::new();
    let png = dir.join("shot.png");
    std::fs::write(&png, b"\x89PNG\r\n\x1a\nrest").unwrap();
    let pdf = dir.join("spec.pdf");
    write(&pdf, ONE_PAGE);
    let notes = dir.join("notes.txt");
    write(&notes, "notes");
    let attachments = vec![
        Attachment::LocalImage { path: png.clone() },
        Attachment::File {
            path: pdf.clone(),
            name: None,
        },
        Attachment::File {
            path: notes.clone(),
            name: Some("notes.txt".into()),
        },
    ];
    let content = sent_content(SessionStartInput::new("app-thread"), attachments.clone()).await;
    let kinds = content
        .as_array()
        .unwrap()
        .iter()
        .map(|block| block["type"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(kinds, ["image", "document", "text"]);
    let text = content[2]["text"].as_str().unwrap();
    assert!(text.starts_with("Look\n\n[Attached image \"shot.png\" is saved at: "));
    assert!(text.ends_with(&format!(
        "[Attached file \"notes.txt\" is saved at: {}]",
        notes.display()
    )));

    // A resumed conversation may already hold documents.
    let resumed = SessionStartInput {
        resume_thread_id: Some("native-old".into()),
        ..SessionStartInput::new("app-thread")
    };
    let content = sent_content(resumed, attachments).await;
    let kinds = content
        .as_array()
        .unwrap()
        .iter()
        .map(|block| block["type"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(kinds, ["image", "text"]);
}

#[tokio::test]
async fn a_text_only_turn_still_sends_a_string() {
    let content = sent_content(SessionStartInput::new("app-thread"), Vec::new()).await;
    assert_eq!(content, json!("Look"));
}
