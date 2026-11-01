use super::*;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

const PNG: &[u8] = b"\x89PNG\r\n\x1a\nrest";

fn temp_dir() -> PathBuf {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "alera-claude-attachments-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn pdf(pages: u32) -> String {
    let kids = (0..pages)
        .map(|index| format!("{} 0 R", index + 3))
        .collect::<Vec<_>>()
        .join(" ");
    let mut pdf = format!(
        "%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Count {pages} /Kids [{kids}] >> endobj\n"
    );
    for index in 0..pages {
        pdf.push_str(&format!(
            "{} 0 obj << /Type /Page /Parent 2 0 R >> endobj\n",
            index + 3
        ));
    }
    pdf.push_str("%%EOF");
    pdf
}

fn file(dir: &Path, name: &str, bytes: &[u8]) -> Attachment {
    let path = dir.join(name);
    std::fs::write(&path, bytes).unwrap();
    if name.ends_with(".png") || name.ends_with(".heic") {
        Attachment::LocalImage { path }
    } else {
        Attachment::File {
            path,
            name: Some(name.into()),
        }
    }
}

fn kinds(prepared: &PreparedPrompt) -> Vec<&str> {
    prepared
        .media
        .iter()
        .flatten()
        .map(|block| block["type"].as_str().unwrap())
        .collect()
}

#[test]
fn a_turn_without_attachments_keeps_plain_text() {
    let prepared = prepare_prompt("hello", &[], AttachmentBudget::default()).unwrap();
    assert_eq!(prepared.text, "hello");
    assert!(prepared.media.is_none());
}

#[test]
fn images_and_pdfs_become_blocks_and_other_files_are_named() {
    let dir = temp_dir();
    let attachments = [
        file(&dir, "shot.png", PNG),
        file(&dir, "spec.pdf", pdf(1).as_bytes()),
        file(&dir, "notes.txt", b"notes"),
        file(&dir, "photo.heic", b"\0\0\0\x18ftypheic"),
    ];
    let prepared = prepare_prompt("Look", &attachments, AttachmentBudget::default()).unwrap();
    assert_eq!(kinds(&prepared), ["image", "document"]);
    let media = prepared.media.as_ref().unwrap();
    assert_eq!(media[0]["source"]["media_type"], "image/png");
    assert_eq!(media[1]["source"]["media_type"], "application/pdf");
    assert_eq!(prepared.used.pages, 1);
    for name in ["shot.png", "spec.pdf", "notes.txt", "photo.heic"] {
        assert!(
            prepared.text.contains(&format!("\"{name}\" is saved at:")),
            "{name}"
        );
    }
}

#[test]
fn a_missing_image_fails_the_turn() {
    let missing = Attachment::LocalImage {
        path: temp_dir().join("gone.png"),
    };
    let error = prepare_prompt("x", &[missing], AttachmentBudget::default()).unwrap_err();
    assert!(matches!(
        error,
        ProviderError::Rejected {
            class: FailureClass::AttachmentUnreadable,
            ..
        }
    ));
}

#[test]
fn pdfs_past_the_page_budget_are_named_only() {
    let dir = temp_dir();
    let big = [file(&dir, "big.pdf", pdf(101).as_bytes())];
    assert_eq!(
        kinds(&prepare_prompt("x", &big, AttachmentBudget::default()).unwrap()),
        Vec::<&str>::new()
    );
    let one = [file(&dir, "one.pdf", pdf(1).as_bytes())];
    let inherited = prepare_prompt("x", &one, AttachmentBudget::inherited()).unwrap();
    assert!(kinds(&inherited).is_empty());
    assert!(inherited.text.contains("one.pdf"));
    let two = [
        file(&dir, "a.pdf", pdf(60).as_bytes()),
        file(&dir, "b.pdf", pdf(60).as_bytes()),
    ];
    let prepared = prepare_prompt("x", &two, AttachmentBudget::default()).unwrap();
    assert_eq!(kinds(&prepared), ["document"]);
    assert_eq!(prepared.used.pages, 60);
}

#[test]
fn an_image_that_does_not_fit_is_named_only() {
    let dir = temp_dir();
    let attachments = [file(&dir, "shot.png", PNG)];
    let full = AttachmentBudget {
        pages: 0,
        bytes: MAX_RETAINED_BYTES - 100,
    };
    assert!(kinds(&prepare_prompt("x", &attachments, full).unwrap()).is_empty());
}

#[test]
fn data_url_images_are_blocks_and_remote_ones_are_refused() {
    let data = Attachment::Image {
        url: "data:image/png;base64,iVBORw0K".into(),
    };
    let prepared = prepare_prompt("x", &[data], AttachmentBudget::default()).unwrap();
    assert_eq!(prepared.media.unwrap()[0]["source"]["data"], "iVBORw0K");
    let remote = Attachment::Image {
        url: "https://example.com/a.png".into(),
    };
    assert!(matches!(
        prepare_prompt("x", &[remote], AttachmentBudget::default()),
        Err(ProviderError::Unsupported(_))
    ));
}

#[test]
fn only_a_full_compaction_frees_the_budget() {
    let used = AttachmentBudget {
        pages: 10,
        bytes: 100,
    };
    let mut budget = used;
    budget.observe_compaction(&json!({"compact_metadata": {"preserved_segment": {}}}));
    assert_eq!(budget, used);
    budget.observe_compaction(&json!({}));
    assert_eq!(budget, used);
    budget.observe_compaction(&json!({"compact_metadata": {"trigger": "auto"}}));
    assert_eq!(budget, AttachmentBudget::default());
}

#[test]
fn replayed_media_bytes_are_redacted() {
    let mut content = json!([
        {"type": "image", "source": {"type": "base64", "data": "abcd"}},
        {"type": "text", "text": "keep"},
    ]);
    redact_media(&mut content);
    assert!(content[0]["source"].get("data").is_none());
    assert_eq!(content[0]["source"]["omittedBytes"], 4);
    assert_eq!(content[1]["text"], "keep");
}
