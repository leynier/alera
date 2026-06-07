use git2::Repository;

use super::{
    diff_file_for_area,
    git_diff_paths::GitPathContext,
    git_diff_render::{diff_lines_byte_len, truncate_diff_lines_to_bytes},
    GitChangeArea, GitDiffFile, GitDiffResult, GitError, MAX_DIFF_PATCH_BYTES,
};

pub(super) fn git_diff_all_for_file(
    repo: &Repository,
    paths: &GitPathContext,
    file_path: &str,
) -> Result<GitDiffResult, GitError> {
    let mut files = Vec::new();
    let mut total_bytes = 0usize;
    let mut truncated = false;

    for area in [
        GitChangeArea::Untracked,
        GitChangeArea::Unstaged,
        GitChangeArea::Staged,
    ] {
        if let Some(file) = diff_file_for_area(repo, paths, file_path, area)? {
            if append_combined_diff_file(&mut files, &mut total_bytes, &mut truncated, file) {
                break;
            }
        }
    }

    Ok(GitDiffResult { files, truncated })
}

pub(super) fn append_combined_diff_file(
    files: &mut Vec<GitDiffFile>,
    total_bytes: &mut usize,
    truncated: &mut bool,
    mut file: GitDiffFile,
) -> bool {
    let preview_bytes = diff_lines_byte_len(&file.lines);
    if file.truncated {
        *truncated = true;
    }
    if *total_bytes + preview_bytes > MAX_DIFF_PATCH_BYTES {
        let remaining = MAX_DIFF_PATCH_BYTES.saturating_sub(*total_bytes);
        truncate_diff_lines_to_bytes(&mut file.lines, remaining);
        file.truncated = true;
        *truncated = true;
    }
    *total_bytes = total_bytes.saturating_add(diff_lines_byte_len(&file.lines));
    files.push(file);
    if *total_bytes >= MAX_DIFF_PATCH_BYTES {
        *truncated = true;
        true
    } else {
        false
    }
}
