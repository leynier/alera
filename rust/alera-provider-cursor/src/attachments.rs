use super::MAX_LOCAL_IMAGE_BYTES;
use alera_provider_protocol::{Attachment, ProviderError};
use cursor_agent_sdk::SdkImage;

pub(super) async fn load_images(
    attachments: &[Attachment],
) -> Result<Vec<SdkImage>, ProviderError> {
    let mut images = Vec::new();
    for attachment in attachments {
        match attachment {
            Attachment::Image { .. } => {
                return Err(ProviderError::Unsupported(
                    "Cursor local agents do not accept remote image URLs".into(),
                ));
            }
            Attachment::LocalImage { path } => {
                let data = tokio::fs::read(path).await.map_err(|error| {
                    ProviderError::Validation(format!(
                        "read local image {}: {error}",
                        path.display()
                    ))
                })?;
                if data.len() > MAX_LOCAL_IMAGE_BYTES {
                    return Err(ProviderError::Validation(format!(
                        "local image {} exceeds {} bytes",
                        path.display(),
                        MAX_LOCAL_IMAGE_BYTES
                    )));
                }
                images.push(SdkImage::Data {
                    data: base64_encode(&data),
                    mime_type: image_mime_type(path),
                });
            }
            Attachment::File { .. } => {
                return Err(ProviderError::Unsupported(
                    "Cursor bridge accepts image attachments only".into(),
                ));
            }
        }
    }
    Ok(images)
}

fn image_mime_type(path: &std::path::Path) -> String {
    match path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.to_ascii_lowercase())
        .as_deref()
    {
        Some("avif") => "image/avif",
        Some("bmp") => "image/bmp",
        Some("gif") => "image/gif",
        Some("jpeg") | Some("jpg") => "image/jpeg",
        Some("png") => "image/png",
        Some("svg") | Some("svgz") => "image/svg+xml",
        Some("webp") => "image/webp",
        _ => "application/octet-stream",
    }
    .into()
}

fn base64_encode(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let first = chunk[0] as usize;
        let second = chunk.get(1).copied().unwrap_or_default() as usize;
        let third = chunk.get(2).copied().unwrap_or_default() as usize;
        output.push(ALPHABET[first >> 2] as char);
        output.push(ALPHABET[((first & 0x03) << 4) | (second >> 4)] as char);
        if chunk.len() > 1 {
            output.push(ALPHABET[((second & 0x0f) << 2) | (third >> 6)] as char);
        } else {
            output.push('=');
        }
        if chunk.len() > 2 {
            output.push(ALPHABET[third & 0x3f] as char);
        } else {
            output.push('=');
        }
    }
    output
}
