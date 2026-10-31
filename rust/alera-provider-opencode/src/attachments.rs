//! Turn attachments as T3 Code's OpenCode adapters send them. PNG, JPEG,
//! GIF and WebP images, PDFs and plain text ride as file parts, their bytes
//! inline so the server need not share the host's filesystem. Anything else
//! (HTML, Markdown, archives, image formats model APIs reject, files over
//! OpenCode's attachment limit) would fail the turn as a file part, so it
//! rides only as its path in the prompt text.

use alera_provider_protocol::{Attachment, FailureClass, ProviderError, TurnInput};
use opencode_agent_sdk::inline_file_part;
use serde_json::{json, Value};
use std::path::Path;

/// OpenCode's own limit on an attachment's bytes.
const MAX_FILE_PART_BYTES: u64 = 20 * 1024 * 1024;

/// Byte signatures of the types model APIs accept as file parts.
const SIGNATURES: [(&[u8], &str); 5] = [
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"GIF87a", "image/gif"),
    (b"GIF89a", "image/gif"),
    (b"%PDF-", "application/pdf"),
];

/// The prompt parts of a turn: its text, then one file part per attachment
/// that can ride as one.
pub(crate) async fn prompt_parts(input: &TurnInput) -> Result<Vec<Value>, ProviderError> {
    let mut text = if input.input.trim().is_empty() {
        String::new()
    } else {
        input.input.clone()
    };
    let mut files = Vec::new();
    for attachment in &input.attachments {
        let (path, kind) = match attachment {
            Attachment::Image { url } => {
                files.push(json!({ "type": "file", "url": url, "mime": "image/*" }));
                continue;
            }
            Attachment::LocalImage { path } => (path, "image"),
            Attachment::File { path } => (path, "file"),
        };
        match local_file_part(path).await? {
            Some(part) => files.push(part),
            None => {
                if !text.is_empty() {
                    text.push_str("\n\n");
                }
                text.push_str(&format!(
                    "[Attached {kind} is saved at: {}]",
                    path.display()
                ));
            }
        }
    }
    let mut parts = Vec::with_capacity(files.len() + 1);
    if !text.is_empty() {
        parts.push(json!({ "type": "text", "text": text }));
    }
    parts.extend(files);
    if parts.is_empty() {
        return Err(ProviderError::Validation(
            "OpenCode turn requires text or an attachment".into(),
        ));
    }
    Ok(parts)
}

/// The file part of a local attachment, or `None` when it can only be
/// named by its path.
async fn local_file_part(path: &Path) -> Result<Option<Value>, ProviderError> {
    let unreadable = |reason: String| ProviderError::Rejected {
        class: FailureClass::AttachmentUnreadable,
        detail: format!("Couldn't read the attachment {}: {reason}", path.display()),
    };
    let metadata = tokio::fs::metadata(path)
        .await
        .map_err(|error| unreadable(error.to_string()))?;
    if !metadata.is_file() {
        return Err(unreadable("it is not a file".into()));
    }
    if metadata.len() > MAX_FILE_PART_BYTES {
        return Ok(None);
    }
    let bytes = tokio::fs::read(path)
        .await
        .map_err(|error| unreadable(error.to_string()))?;
    if bytes.len() as u64 > MAX_FILE_PART_BYTES {
        return Ok(None);
    }
    let Some(mime) = native_mime(path, &bytes) else {
        return Ok(None);
    };
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "attachment".into());
    Ok(Some(inline_file_part(mime, &name, &bytes)))
}

/// The type of a file OpenCode can take as a part, read from its bytes.
/// OpenCode reads plain text itself; other text types (HTML, Markdown, CSV)
/// reach the model API as raw file parts, which Anthropic and OpenAI reject.
fn native_mime(path: &Path, bytes: &[u8]) -> Option<&'static str> {
    if let Some((_, mime)) = SIGNATURES
        .iter()
        .find(|(signature, _)| bytes.starts_with(signature))
    {
        return Some(mime);
    }
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    let plain = path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("txt"));
    (plain && std::str::from_utf8(bytes).is_ok()).then_some("text/plain")
}
