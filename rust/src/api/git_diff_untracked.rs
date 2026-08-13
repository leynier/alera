use git2::Repository;

use super::{
    git_diff_render::diff_lines_from_patch, GitChangeArea, GitChangeStatus, GitDiffFile, GitError,
    GitErrorKind, GitPathContext,
};

const MAX_UNTRACKED_TEXT_BYTES: u64 = 256 * 1024;

pub(super) struct UntrackedText {
    pub(super) content: Option<String>,
    pub(super) added: Option<u32>,
    pub(super) is_binary: bool,
    pub(super) is_large: bool,
    pub(super) is_symlink: bool,
    pub(super) is_executable: bool,
}

pub(super) fn untracked_diff_file(
    repo: &Repository,
    paths: &GitPathContext,
    file_path: &str,
) -> Result<GitDiffFile, GitError> {
    let untracked = read_untracked_text(repo, file_path)?;
    let display_path = paths
        .to_workspace_path(file_path)
        .unwrap_or_else(|| file_path.to_string());
    let patch = untracked
        .content
        .as_ref()
        .map(|content| {
            build_untracked_patch(
                &display_path,
                content,
                untracked.is_symlink,
                untracked.is_executable,
            )
        })
        .unwrap_or_default();
    let (lines, line_preview_truncated) = diff_lines_from_patch(&patch);
    Ok(GitDiffFile {
        path: display_path,
        old_path: None,
        area: GitChangeArea::Untracked,
        status: GitChangeStatus::Untracked,
        lines,
        added: untracked.added,
        removed: Some(0),
        is_binary: untracked.is_binary,
        is_large: untracked.is_large,
        is_gitlink: false,
        truncated: false,
        line_preview_truncated,
    })
}

pub(super) fn read_untracked_text(
    repo: &Repository,
    file_path: &str,
) -> Result<UntrackedText, GitError> {
    read_untracked_text_up_to(repo, file_path, MAX_UNTRACKED_TEXT_BYTES)
}

pub(super) fn read_untracked_text_up_to(
    repo: &Repository,
    file_path: &str,
    max_bytes: u64,
) -> Result<UntrackedText, GitError> {
    let Some(workdir) = repo.workdir() else {
        return Err(GitError::new(GitErrorKind::NotARepository, file_path));
    };
    let path = workdir.join(file_path);
    let metadata = std::fs::symlink_metadata(&path)
        .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
    if metadata.file_type().is_symlink() {
        let target = std::fs::read_link(&path)
            .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
        let content = target.to_string_lossy().to_string();
        return Ok(UntrackedText {
            content: Some(content),
            added: Some(1),
            is_binary: false,
            is_large: false,
            is_symlink: true,
            is_executable: false,
        });
    }
    if !metadata.is_file() {
        return Ok(empty_untracked_text(false));
    }
    let is_executable = metadata_is_executable(&metadata);
    if metadata.len() > max_bytes {
        return Ok(UntrackedText {
            content: None,
            added: None,
            is_binary: false,
            is_large: true,
            is_symlink: false,
            is_executable,
        });
    }
    let bytes = std::fs::read(&path)
        .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
    if bytes.contains(&0) {
        return Ok(binary_untracked_text(is_executable));
    }
    let Ok(content) = String::from_utf8(bytes) else {
        return Ok(binary_untracked_text(is_executable));
    };
    let added = count_text_lines(&content);
    Ok(UntrackedText {
        content: Some(content),
        added: Some(added),
        is_binary: false,
        is_large: false,
        is_symlink: false,
        is_executable,
    })
}

fn empty_untracked_text(is_executable: bool) -> UntrackedText {
    UntrackedText {
        content: None,
        added: None,
        is_binary: false,
        is_large: false,
        is_symlink: false,
        is_executable,
    }
}

fn binary_untracked_text(is_executable: bool) -> UntrackedText {
    UntrackedText {
        content: None,
        added: None,
        is_binary: true,
        is_large: false,
        is_symlink: false,
        is_executable,
    }
}

pub(super) fn build_untracked_patch(
    file_path: &str,
    content: &str,
    is_symlink: bool,
    is_executable: bool,
) -> String {
    let added = count_text_lines(content);
    let mode = if is_symlink {
        "120000"
    } else if is_executable {
        "100755"
    } else {
        "100644"
    };
    let mut patch = format!(
        "diff --git a/{file_path} b/{file_path}\nnew file mode {mode}\n--- /dev/null\n+++ b/{file_path}\n@@ -0,0 +1,{added} @@\n"
    );
    for line in content.split_inclusive('\n') {
        patch.push('+');
        patch.push_str(line);
    }
    if !content.is_empty() && !content.ends_with('\n') {
        patch.push('\n');
        patch.push_str("\\ No newline at end of file\n");
    }
    patch
}

#[cfg(unix)]
fn metadata_is_executable(metadata: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o111 != 0
}

#[cfg(not(unix))]
fn metadata_is_executable(_metadata: &std::fs::Metadata) -> bool {
    false
}

fn count_text_lines(content: &str) -> u32 {
    if content.is_empty() {
        return 0;
    }
    content.lines().count() as u32
}
