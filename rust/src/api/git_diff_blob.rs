use super::git::{GitChangeArea, GitError};

/// Raw bytes of one side of a diffed file, used for binary previews such as
/// images. Returns `None` when that side does not exist (added or deleted
/// files), the entry is not a blob, or the content exceeds the core limit.
pub fn git_diff_blob_bytes(
    path: String,
    file_path: String,
    old_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    old_side: bool,
) -> Result<Option<Vec<u8>>, GitError> {
    alera_core::source_control::git_diff_blob_bytes(
        path, file_path, old_path, area, commit_oid, parent_oid, old_side,
    )
}
