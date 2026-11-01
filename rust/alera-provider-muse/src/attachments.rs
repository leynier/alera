//! Turn attachments. Supported images ride as native `image` parts, and every
//! local attachment is also named by path in the prompt, so none is dropped.

use alera_provider_protocol::{Attachment, FailureClass, ProviderError, TurnInput};
use serde_json::{json, Value};
use std::path::Path;

/// Image types Muse accepts as `image` parts; others reach it by path only.
const IMAGE_MEDIA_TYPES: [&str; 4] = ["image/gif", "image/jpeg", "image/png", "image/webp"];
/// Room in the frame for the JSON-RPC envelope around the turn input.
const ENVELOPE_BYTES: usize = 16 * 1024;

pub(crate) struct TurnParts {
    pub input: Vec<Value>,
    /// The prompt as typed, for Muse's transcript, when attachments extend it.
    pub display_text: Option<String>,
}

/// `turn/start` input for `input`, sized to fit one transport frame: an
/// oversized frame would close the connection instead of failing the turn.
pub(crate) async fn turn_parts(
    input: &TurnInput,
    max_frame_bytes: usize,
) -> Result<TurnParts, ProviderError> {
    let limit = max_frame_bytes.saturating_sub(ENVELOPE_BYTES);
    let mut text = input.input.clone();
    let mut images = Vec::new();
    let mut image_bytes = 0;
    for attachment in &input.attachments {
        let (media_type, data) = match attachment {
            Attachment::Image { url } => {
                let (media_type, data) = data_url_image(url)?;
                (media_type, data.to_owned())
            }
            Attachment::LocalImage { path } => {
                append_path(&mut text, "image", path);
                let Some(media_type) = image_media_type(path) else {
                    continue;
                };
                let data = read_image(path, limit.saturating_sub(image_bytes)).await?;
                (media_type, data)
            }
            Attachment::File { path, .. } => {
                append_path(&mut text, "file", path);
                continue;
            }
        };
        image_bytes += data.len();
        images.push(json!({"type": "image", "base64Data": data, "mediaType": media_type}));
    }
    let display_text = (!input.attachments.is_empty()).then(|| {
        if !input.input.trim().is_empty() {
            input.input.clone()
        } else if images.is_empty() {
            "File attachment".to_owned()
        } else {
            "Image attachment".to_owned()
        }
    });
    let mut parts = Vec::with_capacity(images.len() + 1);
    if !text.trim().is_empty() {
        parts.push(json!({"type": "text", "text": text}));
    }
    parts.extend(images);
    let encoded = serde_json::to_vec(&json!({"input": parts, "displayText": display_text}))
        .map_or(usize::MAX, |bytes| bytes.len());
    if encoded > limit {
        return Err(too_large(max_frame_bytes));
    }
    Ok(TurnParts {
        input: parts,
        display_text,
    })
}

fn append_path(text: &mut String, kind: &str, path: &Path) {
    if !text.is_empty() {
        text.push_str("\n\n");
    }
    text.push_str(&format!(
        "[Attached {kind} is saved at: {}]",
        path.display()
    ));
}

fn data_url_image(url: &str) -> Result<(&'static str, &str), ProviderError> {
    let parsed = url
        .strip_prefix("data:")
        .and_then(|rest| rest.split_once(','))
        .and_then(|(header, data)| Some((header.strip_suffix(";base64")?, data)))
        .and_then(|(media_type, data)| {
            let media_type = IMAGE_MEDIA_TYPES
                .into_iter()
                .find(|supported| supported.eq_ignore_ascii_case(media_type))?;
            Some((media_type, data))
        });
    parsed.ok_or_else(|| {
        ProviderError::Unsupported(
            "Muse accepts GIF, JPEG, PNG or WebP base64 data URLs, not remote image URLs".into(),
        )
    })
}

fn image_media_type(path: &Path) -> Option<&'static str> {
    let extension = path.extension()?.to_str()?.to_ascii_lowercase();
    match extension.as_str() {
        "gif" => Some("image/gif"),
        "jpeg" | "jpg" => Some("image/jpeg"),
        "png" => Some("image/png"),
        "webp" => Some("image/webp"),
        _ => None,
    }
}

async fn read_image(path: &Path, budget: usize) -> Result<String, ProviderError> {
    let unreadable = |error: std::io::Error| ProviderError::Rejected {
        class: FailureClass::AttachmentUnreadable,
        detail: format!("read Muse image {}: {error}", path.display()),
    };
    let size = tokio::fs::metadata(path).await.map_err(unreadable)?.len();
    if size.div_ceil(3) * 4 > budget as u64 {
        return Err(ProviderError::Validation(format!(
            "Muse image {} does not fit in one turn",
            path.display()
        )));
    }
    let bytes = tokio::fs::read(path).await.map_err(unreadable)?;
    Ok(base64(&bytes))
}

fn too_large(max_frame_bytes: usize) -> ProviderError {
    ProviderError::Validation(format!(
        "Muse turn attachments exceed the {max_frame_bytes}-byte frame limit"
    ))
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let triple = chunk.iter().enumerate().fold(0u32, |acc, (index, byte)| {
            acc | (u32::from(*byte) << (16 - 8 * index))
        });
        for index in 0..4 {
            if index <= chunk.len() {
                let sextet = (triple >> (18 - 6 * index)) & 0x3f;
                output.push(ALPHABET[sextet as usize] as char);
            } else {
                output.push('=');
            }
        }
    }
    output
}
