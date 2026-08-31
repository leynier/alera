use std::fs;
use std::path::{Path, PathBuf};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::prompt_file_store::DIRECTORY as PROMPT_FILE_DIRECTORY;
use super::prompt_image_store::PROMPT_IMAGE_DIRECTORY;

pub(super) fn prompt_attachment_root(
    runtime_dir: &Path,
    canonical_path: &Path,
) -> HostResult<PathBuf> {
    [
        PROMPT_FILE_DIRECTORY,
        PROMPT_IMAGE_DIRECTORY,
        "codex-attachments",
    ]
    .into_iter()
    .filter_map(|name| fs::canonicalize(runtime_dir.join(name)).ok())
    .find(|root| canonical_path.starts_with(root))
    .ok_or_else(|| HostError::state("Prompt attachment path is outside the runtime store."))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retained_attachments_are_readable_but_sibling_paths_are_not() {
        let runtime = tempfile::tempdir().unwrap();
        for directory in ["codex-attachments", "codex-attachments-private"] {
            let root = runtime.path().join(directory);
            fs::create_dir_all(&root).unwrap();
            let path = root.join("file.txt");
            fs::write(&path, b"retained").unwrap();
            assert_eq!(
                prompt_attachment_root(runtime.path(), &path.canonicalize().unwrap()).is_ok(),
                directory == "codex-attachments"
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn retained_attachment_symlinks_cannot_escape_the_store() {
        let runtime = tempfile::tempdir().unwrap();
        let outside = tempfile::NamedTempFile::new().unwrap();
        let root = runtime.path().join("codex-attachments");
        fs::create_dir(&root).unwrap();
        let path = root.join("escape");
        std::os::unix::fs::symlink(outside.path(), &path).unwrap();
        assert!(prompt_attachment_root(runtime.path(), &path.canonicalize().unwrap()).is_err());
    }
}
