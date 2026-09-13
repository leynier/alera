use std::io::Read;

use git2::Repository;

use super::{
    git_diff_render::diff_lines_from_patch, GitChangeArea, GitChangeStatus, GitDiffFile, GitError,
    GitErrorKind, GitPathContext,
};

const MAX_UNTRACKED_TEXT_BYTES: u64 = 256 * 1024;
const BINARY_SAMPLE_BYTES: usize = 8 * 1024;

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
        let is_binary = file_prefix_is_binary(&path)?;
        return Ok(UntrackedText {
            content: None,
            added: None,
            is_binary,
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

fn file_prefix_is_binary(path: &std::path::Path) -> Result<bool, GitError> {
    let mut file = std::fs::File::open(path)
        .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
    let mut sample = vec![0; BINARY_SAMPLE_BYTES];
    let length = file
        .read(&mut sample)
        .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
    sample.truncate(length);
    if sample.contains(&0) {
        return Ok(true);
    }
    Ok(std::str::from_utf8(&sample)
        .err()
        .is_some_and(|error| error.error_len().is_some()))
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
    let old_path = git_patch_path("a", file_path);
    let new_path = git_patch_path("b", file_path);
    let mode = if is_symlink {
        "120000"
    } else if is_executable {
        "100755"
    } else {
        "100644"
    };
    let mut patch = format!(
        "diff --git {old_path} {new_path}\nnew file mode {mode}\n--- /dev/null\n+++ {new_path}\n@@ -0,0 +1,{added} @@\n"
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

pub(super) fn git_patch_path(prefix: &str, path: &str) -> String {
    let value = format!("{prefix}/{path}");
    if !value
        .chars()
        .any(|character| character.is_control() || matches!(character, '\\' | '"'))
    {
        return value;
    }
    let mut quoted = String::with_capacity(value.len().saturating_add(2));
    quoted.push('"');
    for character in value.chars() {
        match character {
            '\u{7}' => quoted.push_str("\\a"),
            '\u{8}' => quoted.push_str("\\b"),
            '\t' => quoted.push_str("\\t"),
            '\n' => quoted.push_str("\\n"),
            '\u{b}' => quoted.push_str("\\v"),
            '\u{c}' => quoted.push_str("\\f"),
            '\r' => quoted.push_str("\\r"),
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            control if control.is_control() => {
                for byte in control.to_string().as_bytes() {
                    quoted.push_str(&format!("\\{byte:03o}"));
                }
            }
            value => quoted.push(value),
        }
    }
    quoted.push('"');
    quoted
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
