//! Turn attachments for Claude, as T3 Code: local and data-URL images as
//! base64 image blocks, PDFs as document blocks within a per-session budget
//! of 28 MiB and 100 pages, and every local attachment also named by its
//! saved path in the prompt text, so a file Claude cannot take natively is
//! still read with its own tools.

#[path = "pdf_pages.rs"]
mod pdf_pages;

use alera_provider_protocol::{
    text_with_attachment_paths, Attachment, FailureClass, ProviderError,
};
use base64::Engine;
use serde_json::{json, Value};
use std::io::Read;
use std::path::Path;

/// The largest frame the SDK transport takes: the retained budget plus framing.
pub(super) const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;
const MAX_RETAINED_BYTES: u64 = 28 * 1024 * 1024;
const MAX_RETAINED_PAGES: u32 = 100;
const MAX_PDF_BYTES: u64 = 20 * 1024 * 1024;
/// Anthropic's limit for one base64 image.
const MAX_IMAGE_ENCODED_BYTES: u64 = 5 * 1024 * 1024;
const BLOCK_OVERHEAD: u64 = 128;

fn encoded(raw: u64) -> u64 {
    4 * raw.div_ceil(3)
}

fn retained(raw: u64) -> u64 {
    encoded(raw) + BLOCK_OVERHEAD
}

/// What the session's conversation already holds of the budget.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(super) struct AttachmentBudget {
    pub(super) pages: u32,
    pub(super) bytes: u64,
}

impl AttachmentBudget {
    /// A resumed or forked session whose retained documents are unknown: no
    /// PDF until a full compaction, while images keep their allowance.
    pub(super) fn inherited() -> Self {
        Self {
            pages: MAX_RETAINED_PAGES,
            bytes: 0,
        }
    }

    pub(super) fn commit(&mut self, used: Self) {
        self.pages = self.pages.saturating_add(used.pages);
        self.bytes = self.bytes.saturating_add(used.bytes);
    }

    /// A full compaction, one that preserved nothing, drops retained media.
    pub(super) fn observe_compaction(&mut self, payload: &Value) {
        let Some(metadata) = payload.get("compact_metadata").and_then(Value::as_object) else {
            return;
        };
        if !metadata.contains_key("preserved_segment")
            && !metadata.contains_key("preserved_messages")
        {
            *self = Self::default();
        }
    }

    fn remaining_bytes(self, used: Self) -> u64 {
        MAX_RETAINED_BYTES.saturating_sub(self.bytes.saturating_add(used.bytes))
    }

    fn remaining_pages(self, used: Self) -> u32 {
        MAX_RETAINED_PAGES.saturating_sub(self.pages.saturating_add(used.pages))
    }
}

#[derive(Debug)]
pub(super) struct PreparedPrompt {
    pub(super) text: String,
    /// The native blocks, in attachment order; None for a turn without
    /// attachments, whose content stays a plain string.
    pub(super) media: Option<Vec<Value>>,
    pub(super) used: AttachmentBudget,
}

/// The prompt for [text] and [attachments]. Blocking: it reads files.
pub(super) fn prepare_prompt(
    text: &str,
    attachments: &[Attachment],
    budget: AttachmentBudget,
) -> Result<PreparedPrompt, ProviderError> {
    let text = text_with_attachment_paths(text, attachments);
    let mut used = AttachmentBudget {
        pages: 0,
        bytes: text.len() as u64 + BLOCK_OVERHEAD,
    };
    if attachments.is_empty() {
        return Ok(PreparedPrompt {
            text,
            media: None,
            used,
        });
    }
    let mut blocks: Vec<Option<Value>> = vec![None; attachments.len()];
    for (index, attachment) in attachments.iter().enumerate() {
        let (media_type, data, raw_len) = match attachment {
            Attachment::LocalImage { path } => {
                let bytes = std::fs::read(path).map_err(|error| ProviderError::Rejected {
                    class: FailureClass::AttachmentUnreadable,
                    detail: format!(
                        "Claude could not read the image attachment {}: {error}",
                        attachment.display_name().unwrap_or_default()
                    ),
                })?;
                // A type Claude cannot take, such as HEIC, is named by path.
                let Some(media_type) = image_media_type(&bytes) else {
                    continue;
                };
                let raw_len = bytes.len() as u64;
                if !image_fits(raw_len, budget, used) {
                    continue;
                }
                (
                    media_type,
                    base64::engine::general_purpose::STANDARD.encode(bytes),
                    raw_len,
                )
            }
            Attachment::Image { url } => {
                let (media_type, data) = data_url_image(url).ok_or_else(|| {
                    ProviderError::Unsupported(
                        "Claude Code takes local images and base64 data URL images; remote image URLs are not supported".into(),
                    )
                })?;
                let raw_len = data.len() as u64 / 4 * 3;
                if !image_fits(raw_len, budget, used) {
                    continue;
                }
                (media_type, data.to_owned(), raw_len)
            }
            Attachment::File { .. } => continue,
        };
        used.bytes += retained(raw_len);
        blocks[index] = Some(json!({
            "type": "image",
            "source": {"type": "base64", "media_type": media_type, "data": data},
        }));
    }
    for (index, attachment) in attachments.iter().enumerate() {
        let Attachment::File { path, .. } = attachment else {
            continue;
        };
        let Some((bytes, pages)) = readable_pdf(path, budget, used) else {
            continue;
        };
        used.pages += pages;
        used.bytes += retained(bytes.len() as u64);
        blocks[index] = Some(json!({
            "type": "document",
            "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": base64::engine::general_purpose::STANDARD.encode(bytes),
            },
        }));
    }
    Ok(PreparedPrompt {
        text,
        media: Some(blocks.into_iter().flatten().collect()),
        used,
    })
}

fn image_fits(raw_len: u64, budget: AttachmentBudget, used: AttachmentBudget) -> bool {
    encoded(raw_len) <= MAX_IMAGE_ENCODED_BYTES && retained(raw_len) <= budget.remaining_bytes(used)
}

/// A PDF that fits the remaining budget, with its page count. Anything
/// else, an unreadable file included, is named by path only.
fn readable_pdf(
    path: &Path,
    budget: AttachmentBudget,
    used: AttachmentBudget,
) -> Option<(Vec<u8>, u32)> {
    let remaining_pages = budget.remaining_pages(used);
    if remaining_pages == 0 {
        return None;
    }
    let cap = MAX_PDF_BYTES.min(budget.remaining_bytes(used).saturating_sub(1024) * 3 / 4);
    let mut file = std::fs::File::open(path).ok()?;
    if cap == 0 || file.metadata().ok()?.len() > cap {
        return None;
    }
    let mut bytes = Vec::new();
    file.by_ref().take(cap + 1).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 > cap || !bytes.starts_with(b"%PDF-") {
        return None;
    }
    let pages = pdf_pages::estimate_pdf_pages(&bytes)?;
    if pages == 0
        || pages > remaining_pages
        || retained(bytes.len() as u64) > budget.remaining_bytes(used)
    {
        return None;
    }
    Some((bytes, pages))
}

fn image_media_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        Some("image/jpeg")
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("image/gif")
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

fn data_url_image(url: &str) -> Option<(&'static str, &str)> {
    let rest = url.strip_prefix("data:")?;
    let (media_type, data) = rest.split_once(";base64,")?;
    let media_type = match media_type {
        "image/png" => "image/png",
        "image/jpeg" => "image/jpeg",
        "image/gif" => "image/gif",
        "image/webp" => "image/webp",
        _ => return None,
    };
    Some((media_type, data))
}

/// Replaces the bytes of each top-level image or document block with their
/// length, so a replayed prompt does not carry them through events.
pub(super) fn redact_media(content: &mut Value) {
    for block in content.as_array_mut().into_iter().flatten() {
        if !matches!(block["type"].as_str(), Some("image" | "document")) {
            continue;
        }
        if let Some(source) = block.get_mut("source").and_then(Value::as_object_mut) {
            if let Some(Value::String(data)) = source.remove("data") {
                source.insert("omittedBytes".into(), json!(data.len()));
            }
        }
    }
}

#[cfg(test)]
#[path = "attachments_tests.rs"]
mod tests;
