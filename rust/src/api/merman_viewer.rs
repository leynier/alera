use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;

use merman::render::HeadlessRenderer;
use merman::MermaidConfig;
use serde_json::json;

const MAX_MERMAN_SOURCE_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MermanViewerErrorKind {
    InvalidPath,
    OutsideWorkspace,
    NotFound,
    Unsupported,
    Render,
    Io,
}

#[derive(Debug)]
pub struct MermanViewerError {
    pub kind: MermanViewerErrorKind,
    pub context: String,
}

#[derive(Debug)]
pub struct MermanWorkspaceRender {
    pub svg: String,
    pub content_token: String,
    pub modified_millis: i64,
    pub size: u64,
}

impl MermanViewerError {
    fn new(kind: MermanViewerErrorKind, context: impl Into<String>) -> Self {
        Self {
            kind,
            context: context.into(),
        }
    }

    fn from_io(error: io::Error, context: impl Into<String>) -> Self {
        let kind = match error.kind() {
            io::ErrorKind::NotFound => MermanViewerErrorKind::NotFound,
            _ => MermanViewerErrorKind::Io,
        };
        Self::new(kind, format!("{}: {error}", context.into()))
    }
}

pub fn render_merman_workspace_file(
    workspace_path: String,
    relative_path: String,
) -> Result<MermanWorkspaceRender, MermanViewerError> {
    let root = workspace_root(&workspace_path)?;
    let path = resolve_existing(&root, &relative_path)?;
    let metadata =
        fs::metadata(&path).map_err(|error| MermanViewerError::from_io(error, &relative_path))?;
    if !metadata.is_file() {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::Unsupported,
            relative_path,
        ));
    }
    if metadata.len() > MAX_MERMAN_SOURCE_BYTES {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::Unsupported,
            format!(
                "{} exceeds {} bytes",
                relative_path, MAX_MERMAN_SOURCE_BYTES
            ),
        ));
    }

    let bytes =
        fs::read(&path).map_err(|error| MermanViewerError::from_io(error, &relative_path))?;
    if bytes.contains(&0) {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::Unsupported,
            relative_path,
        ));
    }
    let source = String::from_utf8(bytes).map_err(|_| {
        MermanViewerError::new(MermanViewerErrorKind::Unsupported, relative_path.clone())
    })?;
    let svg = HeadlessRenderer::new()
        .with_site_config(MermaidConfig::from_value(json!({
            "theme": "neutral",
        })))
        .with_diagram_id(&relative_path)
        .render_svg_resvg_safe_sync(&source)
        .map_err(|error| MermanViewerError::new(MermanViewerErrorKind::Render, error.to_string()))?
        .ok_or_else(|| {
            MermanViewerError::new(
                MermanViewerErrorKind::Unsupported,
                "No Mermaid diagram found",
            )
        })?;

    Ok(MermanWorkspaceRender {
        svg,
        content_token: content_token(&metadata),
        modified_millis: modified_millis(&metadata),
        size: metadata.len(),
    })
}

fn workspace_root(path: &str) -> Result<PathBuf, MermanViewerError> {
    let root = fs::canonicalize(path).map_err(|error| MermanViewerError::from_io(error, path))?;
    if !root.is_dir() {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::NotFound,
            path,
        ));
    }
    Ok(root)
}

fn resolve_existing(root: &Path, relative_path: &str) -> Result<PathBuf, MermanViewerError> {
    let normalized = normalize_relative_path(relative_path)?;
    let candidate = root.join(&normalized);
    let canonical = fs::canonicalize(&candidate)
        .map_err(|error| MermanViewerError::from_io(error, relative_path))?;
    if canonical != root && !canonical.starts_with(root) {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::OutsideWorkspace,
            relative_path,
        ));
    }
    Ok(canonical)
}

fn normalize_relative_path(path: &str) -> Result<PathBuf, MermanViewerError> {
    let raw = Path::new(path);
    if path.trim().is_empty() || raw.is_absolute() {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::InvalidPath,
            path,
        ));
    }
    let mut normalized = PathBuf::new();
    for component in raw.components() {
        match component {
            Component::Normal(part) => normalized.push(part),
            Component::CurDir => {}
            _ => {
                return Err(MermanViewerError::new(
                    MermanViewerErrorKind::InvalidPath,
                    path,
                ));
            }
        }
    }
    if normalized.as_os_str().is_empty() {
        return Err(MermanViewerError::new(
            MermanViewerErrorKind::InvalidPath,
            path,
        ));
    }
    Ok(normalized)
}

fn modified_millis(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn content_token(metadata: &fs::Metadata) -> String {
    format!("{}:{}", metadata.len(), modified_millis(metadata))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_valid_merman_file() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("diagram.mmd"),
            "flowchart TD\n  A[Start] --> B[Done]\n",
        )
        .unwrap();

        let rendered = render_merman_workspace_file(
            dir.path().to_string_lossy().to_string(),
            "diagram.mmd".to_string(),
        )
        .unwrap();

        assert!(rendered.svg.contains("<svg"));
        assert!(rendered
            .svg
            .contains(".labelBkg{background-color:rgba(255, 255, 255, 0.5);}"));
        assert!(rendered
            .content_token
            .starts_with(&rendered.size.to_string()));
    }

    #[test]
    fn rejects_outside_workspace_paths() {
        let dir = tempfile::tempdir().unwrap();

        let error = render_merman_workspace_file(
            dir.path().to_string_lossy().to_string(),
            "../diagram.mmd".to_string(),
        )
        .unwrap_err();

        assert_eq!(error.kind, MermanViewerErrorKind::InvalidPath);
    }

    #[test]
    fn rejects_binary_input() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("diagram.mmd"), b"flowchart TD\0A-->B").unwrap();

        let error = render_merman_workspace_file(
            dir.path().to_string_lossy().to_string(),
            "diagram.mmd".to_string(),
        )
        .unwrap_err();

        assert_eq!(error.kind, MermanViewerErrorKind::Unsupported);
    }

    #[test]
    fn reports_render_errors_for_invalid_diagrams() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("diagram.mmd"), "plain text").unwrap();

        let error = render_merman_workspace_file(
            dir.path().to_string_lossy().to_string(),
            "diagram.mmd".to_string(),
        )
        .unwrap_err();

        assert_eq!(error.kind, MermanViewerErrorKind::Render);
    }
}
