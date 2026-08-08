use std::path::{Component, Path, PathBuf};

use alera_native::api::merman_viewer::render_merman_workspace_file;
use base64::prelude::*;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

const MAX_IMAGE_BYTES: u64 = 32 * 1024 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspacePreviewRequest {
    workspace_path: String,
    relative_path: String,
}

pub(super) async fn render_mermaid(payload: &Value) -> HostResult<Value> {
    let request: WorkspacePreviewRequest = parse(payload)?;
    let render = tokio::task::spawn_blocking(move || {
        render_merman_workspace_file(request.workspace_path, request.relative_path)
    })
    .await
    .map_err(|error| HostError::state(format!("Workspace Preview Task Failed: {error}")))?
    .map_err(|error| HostError::state(error.context))?;
    Ok(json!({
        "svg": render.svg,
        "contentToken": render.content_token,
        "modifiedMillis": render.modified_millis,
        "size": render.size,
    }))
}

pub(super) async fn read_image(payload: &Value) -> HostResult<Value> {
    let request: WorkspacePreviewRequest = parse(payload)?;
    let (format, bytes) = tokio::task::spawn_blocking(move || read_image_file(request))
        .await
        .map_err(|error| HostError::state(format!("Workspace Preview Task Failed: {error}")))??;
    Ok(json!({
        "format": format,
        "bytesBase64": BASE64_STANDARD.encode(bytes),
    }))
}

fn read_image_file(request: WorkspacePreviewRequest) -> HostResult<(&'static str, Vec<u8>)> {
    let format = image_format(&request.relative_path)
        .ok_or_else(|| HostError::format("Unsupported Workspace Image Format."))?;
    let root = std::fs::canonicalize(&request.workspace_path)
        .map_err(|error| HostError::state(format!("Workspace Path Is Unavailable: {error}")))?;
    let relative = safe_relative_path(&request.relative_path)?;
    let path = std::fs::canonicalize(root.join(relative))
        .map_err(|error| HostError::state(format!("Workspace Image Is Unavailable: {error}")))?;
    if !path.starts_with(&root) {
        return Err(HostError::format(
            "Workspace Image Is Outside The Workspace.",
        ));
    }
    let metadata = std::fs::metadata(&path)
        .map_err(|error| HostError::state(format!("Workspace Image Is Unavailable: {error}")))?;
    if !metadata.is_file() || metadata.len() > MAX_IMAGE_BYTES {
        return Err(HostError::format("Workspace Image Is Unsupported."));
    }
    let bytes = std::fs::read(path)
        .map_err(|error| HostError::state(format!("Workspace Image Is Unavailable: {error}")))?;
    Ok((format, bytes))
}

fn safe_relative_path(relative_path: &str) -> HostResult<PathBuf> {
    let path = Path::new(relative_path);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return Err(HostError::format("Invalid Workspace Image Path."));
    }
    Ok(path.to_path_buf())
}

fn image_format(relative_path: &str) -> Option<&'static str> {
    match Path::new(relative_path)
        .extension()
        .and_then(|extension| extension.to_str())?
        .to_ascii_lowercase()
        .as_str()
    {
        "png" => Some("png"),
        "jpg" | "jpeg" => Some("jpeg"),
        "webp" => Some("webp"),
        "gif" => Some("gif"),
        "svg" => Some("svg"),
        "bmp" => Some("bmp"),
        "tif" | "tiff" => Some("tiff"),
        _ => None,
    }
}

fn parse<T: for<'de> Deserialize<'de>>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|error| HostError::format(format!("Invalid Workspace Preview Request: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn reads_supported_workspace_image_as_base64() {
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(directory.path().join("pixel.png"), b"png").unwrap();
        let result = read_image(&json!({
            "workspacePath": directory.path(),
            "relativePath": "pixel.png",
        }))
        .await
        .unwrap();
        assert_eq!(result["format"], "png");
        assert_eq!(result["bytesBase64"], BASE64_STANDARD.encode(b"png"));
    }

    #[test]
    fn rejects_paths_outside_the_workspace() {
        assert!(safe_relative_path("../secret.png").is_err());
        assert!(safe_relative_path("/secret.png").is_err());
    }
}
