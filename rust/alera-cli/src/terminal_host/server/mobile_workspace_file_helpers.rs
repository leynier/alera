//! JSON helpers for workspace file host responses.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

pub(super) fn workspace_range_response(
    relative_path: String,
    range: alera_core::workspace_files::WorkspaceFileRange,
) -> Value {
    json!({
        "relativePath": relative_path,
        "offset": range.offset,
        "nextOffset": range.next_offset,
        "totalBytes": range.total_bytes,
        "mimeType": range.mime_type,
        "isText": range.is_text,
        "dataBase64": STANDARD.encode(range.bytes),
    })
}
