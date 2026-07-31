use std::path::{Path, PathBuf};

pub fn resolve_image_path(
    workspace_path: String,
    relative_path: String,
) -> Result<PathBuf, String> {
    let relative = Path::new(&relative_path);
    if relative.is_absolute() {
        return Err("Image path must be relative to the workspace.".to_string());
    }
    let extension = relative
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    if !is_supported_image_extension(&extension) {
        return Err("The selected file is not a supported image.".to_string());
    }
    let root = std::fs::canonicalize(&workspace_path)
        .map_err(|error| format!("Failed to resolve workspace path: {error}"))?;
    let candidate = std::fs::canonicalize(root.join(relative))
        .map_err(|error| format!("Failed to resolve image path: {error}"))?;
    if !candidate.starts_with(&root) {
        return Err("Image path resolves outside the workspace.".to_string());
    }
    if !candidate.is_file() {
        return Err("Image path does not identify a file.".to_string());
    }
    Ok(candidate)
}

fn is_supported_image_extension(extension: &str) -> bool {
    matches!(
        extension,
        "avif"
            | "jpg"
            | "jpeg"
            | "png"
            | "gif"
            | "webp"
            | "tif"
            | "tiff"
            | "tga"
            | "dds"
            | "bmp"
            | "ico"
            | "hdr"
            | "exr"
            | "pbm"
            | "pam"
            | "ppm"
            | "pgm"
            | "ff"
            | "farbfeld"
            | "qoi"
            | "svg"
    )
}

#[cfg(test)]
mod tests {
    use super::resolve_image_path;

    #[test]
    fn rejects_absolute_paths() {
        let result = resolve_image_path("/tmp".to_string(), "/tmp/image.png".to_string());
        assert_eq!(
            result.unwrap_err(),
            "Image path must be relative to the workspace."
        );
    }

    #[test]
    fn rejects_non_image_extensions_before_filesystem_access() {
        let result = resolve_image_path("/missing".to_string(), "notes.txt".to_string());
        assert_eq!(
            result.unwrap_err(),
            "The selected file is not a supported image."
        );
    }
}
