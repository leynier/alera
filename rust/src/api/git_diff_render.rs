use git2::{Diff, DiffFormat, DiffLineType, ErrorCode};

use super::{GitError, MAX_DIFF_PATCH_BYTES};

pub(super) struct RenderedDiff {
    pub(super) patch: String,
    pub(super) added: u32,
    pub(super) removed: u32,
    pub(super) is_binary: bool,
    pub(super) truncated: bool,
}

pub(super) fn render_diff_for_path(
    diff: &mut Diff<'_>,
    repo_path: &str,
) -> Result<RenderedDiff, GitError> {
    let mut patch = String::new();
    let mut added = 0u32;
    let mut removed = 0u32;
    let mut is_binary = false;
    let mut truncated = false;

    let print_result = diff.print(DiffFormat::Patch, |delta, _hunk, line| {
        if !delta_matches_repo_path(&delta, repo_path) {
            return true;
        }
        match line.origin_value() {
            DiffLineType::Addition => added = added.saturating_add(line.num_lines()),
            DiffLineType::Deletion => removed = removed.saturating_add(line.num_lines()),
            DiffLineType::Binary => is_binary = true,
            _ => {}
        }
        if patch.len() >= MAX_DIFF_PATCH_BYTES {
            truncated = true;
            return false;
        }
        let content = String::from_utf8_lossy(line.content());
        match line.origin_value() {
            DiffLineType::Context
            | DiffLineType::Addition
            | DiffLineType::Deletion
            | DiffLineType::ContextEOFNL
            | DiffLineType::AddEOFNL
            | DiffLineType::DeleteEOFNL => {
                patch.push(line.origin());
                patch.push_str(&content);
            }
            DiffLineType::FileHeader | DiffLineType::HunkHeader | DiffLineType::Binary => {
                patch.push_str(&content);
            }
        }
        if patch.len() > MAX_DIFF_PATCH_BYTES {
            truncate_to_char_boundary(&mut patch, MAX_DIFF_PATCH_BYTES);
            truncated = true;
            return false;
        }
        true
    });
    match print_result {
        Ok(()) => {}
        Err(error) if truncated && error.code() == ErrorCode::User => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }

    Ok(RenderedDiff {
        patch,
        added,
        removed,
        is_binary,
        truncated,
    })
}

fn delta_matches_repo_path(delta: &git2::DiffDelta<'_>, repo_path: &str) -> bool {
    delta
        .new_file()
        .path()
        .or_else(|| delta.old_file().path())
        .is_some_and(|path| path.to_string_lossy() == repo_path)
}

pub(super) fn truncate_to_char_boundary(value: &mut String, max_bytes: usize) -> bool {
    if value.len() <= max_bytes {
        return false;
    }
    let mut boundary = max_bytes.min(value.len());
    while boundary > 0 && !value.is_char_boundary(boundary) {
        boundary -= 1;
    }
    value.truncate(boundary);
    true
}
