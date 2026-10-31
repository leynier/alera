//! Turn attachments for Pi's `prompt` command. As in T3 Code, the message
//! names every saved attachment by its path, so none is silently dropped,
//! and local images also travel as native image blocks when they fit.

use alera_provider_protocol::{Attachment, ProviderError, TurnInput};
use serde_json::{json, Value};
use std::path::Path;

/// T3 Code's per-image limit for provider turns.
const MAX_INLINE_IMAGE_BYTES: usize = 10 * 1024 * 1024;

pub(crate) struct PromptInput {
    pub message: String,
    pub images: Vec<Value>,
}

enum LocalImage {
    Inline { block: Value, encoded: usize },
    PathOnly(&'static str),
    Unreadable(String),
}

/// The prompt's message and native images. `image_budget` bounds the base64
/// bytes sent inline, because Pi echoes them in frames of the same limit.
pub(crate) async fn prompt_input(
    input: &TurnInput,
    image_budget: usize,
) -> Result<PromptInput, ProviderError> {
    let mut message = input.input.clone();
    let mut images = Vec::new();
    let mut remaining = image_budget;
    for attachment in &input.attachments {
        let context = match attachment {
            Attachment::Image { url } => {
                let block = data_url_image(url)?;
                let encoded = block["data"].as_str().map_or(0, str::len);
                remaining = remaining.checked_sub(encoded).ok_or_else(|| {
                    ProviderError::Validation(format!(
                        "Pi image attachments exceed the {image_budget}-byte inline limit"
                    ))
                })?;
                images.push(block);
                continue;
            }
            Attachment::LocalImage { path } => match local_image(path, remaining).await {
                LocalImage::Inline { block, encoded } => {
                    remaining -= encoded;
                    images.push(block);
                    saved("image", path, None)
                }
                LocalImage::PathOnly(reason) => saved("image", path, Some(reason)),
                LocalImage::Unreadable(error) => format!(
                    "[Attached image \"{}\" is unavailable: could not read {}: {error}.]",
                    name(path),
                    path.display()
                ),
            },
            Attachment::File { path } => saved("file", path, None),
        };
        message = if message.is_empty() {
            context
        } else {
            format!("{message}\n\n{context}")
        };
    }
    Ok(PromptInput { message, images })
}

fn saved(kind: &str, path: &Path, not_inline: Option<&str>) -> String {
    let note = not_inline.map_or_else(String::new, |reason| format!(" ({reason})"));
    format!(
        "[Attached {kind} \"{}\" is saved at: {}{note}]",
        name(path),
        path.display()
    )
}

fn name(path: &Path) -> String {
    path.file_name().map_or_else(
        || path.display().to_string(),
        |name| name.to_string_lossy().into_owned(),
    )
}

async fn local_image(path: &Path, budget: usize) -> LocalImage {
    const TOO_LARGE: &str = "too large to send inline";
    let fits = |bytes: usize| bytes <= MAX_INLINE_IMAGE_BYTES && encoded_len(bytes) <= budget;
    match tokio::fs::metadata(path).await {
        Ok(metadata) if !metadata.is_file() => return LocalImage::Unreadable("not a file".into()),
        Ok(metadata) if !fits(usize::try_from(metadata.len()).unwrap_or(usize::MAX)) => {
            return LocalImage::PathOnly(TOO_LARGE);
        }
        Ok(_) => {}
        Err(error) => return LocalImage::Unreadable(error.to_string()),
    }
    let bytes = match tokio::fs::read(path).await {
        Ok(bytes) => bytes,
        Err(error) => return LocalImage::Unreadable(error.to_string()),
    };
    // The file may have grown since its metadata was read.
    if !fits(bytes.len()) {
        return LocalImage::PathOnly(TOO_LARGE);
    }
    let Some(mime) = image_mime(&bytes) else {
        return LocalImage::PathOnly("not a PNG, JPEG, GIF or WebP image; not sent inline");
    };
    let data = base64(&bytes);
    LocalImage::Inline {
        encoded: data.len(),
        block: json!({ "type": "image", "data": data, "mimeType": mime }),
    }
}

/// The formats T3 Code sends to providers as images, read from the bytes.
fn image_mime(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if bytes.starts_with(b"\xff\xd8\xff") {
        Some("image/jpeg")
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("image/gif")
    } else if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

fn data_url_image(url: &str) -> Result<Value, ProviderError> {
    if !url.starts_with("data:") {
        return Err(ProviderError::Unsupported(
            "Pi cannot fetch remote image URLs through the RPC adapter".into(),
        ));
    }
    let (header, data) = url
        .split_once(',')
        .ok_or_else(|| ProviderError::Validation("Pi data image attachment is malformed".into()))?;
    let mime = header
        .strip_prefix("data:")
        .and_then(|value| value.strip_suffix(";base64"))
        .ok_or_else(|| {
            ProviderError::Unsupported("Pi image attachments must be base64 data URLs".into())
        })?;
    Ok(json!({ "type": "image", "data": data, "mimeType": mime }))
}

fn encoded_len(bytes: usize) -> usize {
    bytes.div_ceil(3).saturating_mul(4)
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(encoded_len(bytes.len()));
    for chunk in bytes.chunks(3) {
        let triple = chunk.iter().enumerate().fold(0u32, |acc, (index, byte)| {
            acc | (u32::from(*byte) << (16 - 8 * index))
        });
        for index in 0..4 {
            if index <= chunk.len() {
                output.push(ALPHABET[(triple >> (18 - 6 * index)) as usize & 0x3f] as char);
            } else {
                output.push('=');
            }
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::{base64, image_mime};

    #[test]
    fn base64_pads_every_tail_length() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(&[1, 2, 3]), "AQID");
        assert_eq!(base64(&[0xff, 0xfe, 0xfd, 0xfc]), "//79/A==");
    }

    #[test]
    fn image_mime_reads_the_signature_not_the_name() {
        assert_eq!(image_mime(b"\x89PNG\r\n\x1a\nrest"), Some("image/png"));
        assert_eq!(image_mime(b"\xff\xd8\xff\xe0"), Some("image/jpeg"));
        assert_eq!(image_mime(b"GIF89a.."), Some("image/gif"));
        assert_eq!(image_mime(b"RIFF\0\0\0\0WEBPVP8 "), Some("image/webp"));
        assert_eq!(image_mime(b"RIFF\0\0\0\0WAVE"), None);
        assert_eq!(image_mime(b"<svg/>"), None);
    }
}
