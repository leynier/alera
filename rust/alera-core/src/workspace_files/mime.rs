use std::path::Path;

pub(super) fn path_has_binary_preview_mime(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(str::to_ascii_lowercase)
            .as_deref(),
        Some("png" | "jpg" | "jpeg" | "gif" | "webp" | "pdf")
    )
}

pub(super) fn mime_type_for_path(path: &Path, is_text: bool) -> &'static str {
    match path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("svg") => "image/svg+xml",
        Some("json") => "application/json",
        Some("pdf") => "application/pdf",
        _ if is_text => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}
