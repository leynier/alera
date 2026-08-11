use std::fs;
use std::path::{Path, PathBuf};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::prompt_file_store::DIRECTORY as PROMPT_FILE_DIRECTORY;
use super::prompt_image_store::PROMPT_IMAGE_DIRECTORY;

pub(super) fn prompt_attachment_root(
    runtime_dir: &Path,
    canonical_path: &Path,
) -> HostResult<PathBuf> {
    [PROMPT_FILE_DIRECTORY, PROMPT_IMAGE_DIRECTORY]
        .into_iter()
        .filter_map(|name| fs::canonicalize(runtime_dir.join(name)).ok())
        .find(|root| canonical_path.starts_with(root))
        .ok_or_else(|| HostError::state("Prompt attachment path is outside the runtime store."))
}
