//! `agentChat.attachment.read` (`agentChatAttachmentReadV1`): one piece of
//! an image or video a person uploaded to a chat, for thumbnails on devices
//! that do not hold the file. Only the store's own files are read: the id
//! must be a canonical UUID, the storage directory and every file must be
//! real (no symlinks), and the file must sit directly in that directory.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

use super::*;

/// The largest attachment the host serves back.
pub(in crate::terminal_host::server) const MAX_READ_BYTES: u64 = 8 * 1024 * 1024;
/// One piece; base64 keeps it inside the phone relay's 1 MiB envelope.
pub(in crate::terminal_host::server) const READ_PIECE_BYTES: u64 = CHUNK_BYTES as u64;

pub(in crate::terminal_host::server) struct AttachmentRead<'a> {
    pub workspace_id: &'a str,
    pub chat_id: &'a str,
    /// The reader's caller scope; an unsent upload is readable only by it.
    pub caller: &'a str,
    pub attachment_id: &'a str,
    pub offset: u64,
    pub length: u64,
}

impl ChatAttachmentStore {
    pub(in crate::terminal_host::server) fn read_piece(
        &self,
        request: &AttachmentRead<'_>,
    ) -> HostResult<Value> {
        let id = request.attachment_id;
        // A canonical UUID cannot name `..`, a separator or another file.
        validate_id(id).map_err(|_| not_found())?;
        if request.length == 0 || request.length > READ_PIECE_BYTES {
            return Err(HostError::format(format!(
                "length must be between 1 and {READ_PIECE_BYTES}"
            )));
        }
        if !std::fs::symlink_metadata(&self.directory).is_ok_and(|meta| meta.file_type().is_dir()) {
            return Err(not_found());
        }
        let metadata_path = self.metadata_path(id);
        if std::fs::symlink_metadata(&metadata_path).is_err() {
            return Err(not_found());
        }
        let metadata = self.read_metadata_path(&metadata_path)?;
        if metadata.upload_id != id {
            return Err(HostError::state(
                "Invalid chat attachment metadata identity.",
            ));
        }
        let sent = self.retained_path(id).exists();
        if metadata.scope.workspace_id != request.workspace_id
            || metadata.scope.chat_id != request.chat_id
            || (!sent && metadata.scope.caller != request.caller)
        {
            return Err(HostError::conflict(
                "attachment_scope_denied",
                "This attachment belongs to another chat.",
                json!({}),
            ));
        }
        if self.expired(&metadata) {
            return Err(HostError::conflict(
                "attachment_expired",
                "This unused attachment has expired.",
                json!({}),
            ));
        }
        if metadata.size_bytes > MAX_READ_BYTES {
            return Err(HostError::conflict(
                "attachment_too_large",
                "The attachment is too large to preview.",
                json!({"maxBytes": MAX_READ_BYTES}),
            ));
        }
        let path = self.final_path(&metadata);
        if std::fs::symlink_metadata(&path).is_err() {
            return Err(HostError::conflict(
                "attachment_unavailable",
                "The attachment has not finished uploading.",
                json!({}),
            ));
        }
        let mut file = regular_file(&path, false)?;
        let directory =
            crate::windows_path_form::canonicalize(&self.directory).map_err(io_error)?;
        let canonical = crate::windows_path_form::canonicalize(&path).map_err(io_error)?;
        if canonical.parent() != Some(directory.as_path()) {
            return Err(not_found());
        }
        let size = file.metadata().map_err(io_error)?.len();
        if size != metadata.size_bytes {
            return Err(HostError::state(
                "Completed chat attachment is unavailable.",
            ));
        }
        let mut magic = [0u8; 16];
        let read = read_up_to(&mut file, &mut magic)?;
        let mime_type = media_mime_type(&magic[..read]).ok_or_else(|| {
            HostError::conflict(
                "attachment_unsupported_type",
                "Only image and video attachments can be previewed.",
                json!({}),
            )
        })?;
        if request.offset > size {
            return Err(HostError::format("offset is past the attachment's end"));
        }
        let length = request.length.min(size - request.offset);
        file.seek(SeekFrom::Start(request.offset))
            .map_err(io_error)?;
        let mut bytes = vec![0u8; length as usize];
        file.read_exact(&mut bytes).map_err(io_error)?;
        Ok(json!({
            "attachmentId": id,
            "mimeType": mime_type,
            "sizeBytes": size,
            "offset": request.offset,
            "nextOffset": request.offset + length,
            "dataBase64": STANDARD.encode(bytes),
        }))
    }
}

fn not_found() -> HostError {
    HostError::conflict(
        "attachment_not_found",
        "The attachment is not on this host.",
        json!({}),
    )
}

fn read_up_to(file: &mut std::fs::File, buffer: &mut [u8]) -> HostResult<usize> {
    let mut read = 0;
    while read < buffer.len() {
        match file.read(&mut buffer[read..]).map_err(io_error)? {
            0 => break,
            count => read += count,
        }
    }
    Ok(read)
}

/// The image or video type [bytes] start with, by magic bytes, or None.
pub(in crate::terminal_host::server) fn media_mime_type(bytes: &[u8]) -> Option<&'static str> {
    let at = |offset: usize, magic: &[u8]| bytes.get(offset..offset + magic.len()) == Some(magic);
    if at(0, b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if at(0, &[0xff, 0xd8, 0xff]) {
        Some("image/jpeg")
    } else if at(0, b"GIF87a") || at(0, b"GIF89a") {
        Some("image/gif")
    } else if at(0, b"RIFF") && at(8, b"WEBP") {
        Some("image/webp")
    } else if at(0, b"RIFF") && at(8, b"AVI ") {
        Some("video/x-msvideo")
    } else if at(0, b"BM")
        // A known DIB header size, so text starting "BM" is not an image.
        && matches!(bytes.get(14..16), Some([12 | 40 | 52 | 56 | 108 | 124, 0]))
    {
        Some("image/bmp")
    } else if at(0, &[0x1a, 0x45, 0xdf, 0xa3]) {
        Some("video/webm")
    } else if at(4, b"ftyp") {
        let brand = bytes.get(8..12)?;
        Some(match brand {
            b"heic" | b"heix" | b"hevc" | b"hevx" | b"heim" | b"heis" => "image/heic",
            b"mif1" | b"msf1" => "image/heif",
            b"avif" | b"avis" => "image/avif",
            b"qt  " => "video/quicktime",
            _ => "video/mp4",
        })
    } else {
        None
    }
}

#[cfg(test)]
#[path = "agent_chat_attachment_store_reads_tests.rs"]
mod tests;
