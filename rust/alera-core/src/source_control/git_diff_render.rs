use git2::{Diff, DiffFormat, DiffLineType};

use super::{GitDiffLine, GitDiffLineKind, GitError};

pub(super) const MAX_DIFF_PATCH_BYTES: usize = 512 * 1024;

pub(super) const MAX_DIFF_PREVIEW_LINES: usize = 5000;

pub(super) struct RenderedDiff {
    pub(super) lines: Vec<GitDiffLine>,
    pub(super) added: u32,
    pub(super) removed: u32,
    pub(super) is_binary: bool,
    pub(super) truncated: bool,
    pub(super) line_preview_truncated: bool,
}

pub(super) fn render_diff_for_path(
    diff: &mut Diff<'_>,
    repo_path: &str,
) -> Result<RenderedDiff, GitError> {
    let mut lines = Vec::new();
    let mut preview_bytes = 0usize;
    let mut added = 0u32;
    let mut removed = 0u32;
    let mut is_binary = false;
    let mut truncated = false;
    let mut line_preview_truncated = false;

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
        if line_preview_truncated || truncated {
            return true;
        }
        if preview_bytes >= MAX_DIFF_PATCH_BYTES {
            truncated = true;
            return true;
        }
        let content = String::from_utf8_lossy(line.content());
        let (mut text, kind) = match line.origin_value() {
            DiffLineType::Context
            | DiffLineType::Addition
            | DiffLineType::Deletion
            | DiffLineType::ContextEOFNL
            | DiffLineType::AddEOFNL
            | DiffLineType::DeleteEOFNL => {
                let mut text = String::new();
                text.push(line.origin());
                text.push_str(content.trim_end_matches('\n'));
                (text, kind_for_line(line.origin_value()))
            }
            DiffLineType::FileHeader | DiffLineType::HunkHeader | DiffLineType::Binary => (
                content.trim_end_matches('\n').to_string(),
                kind_for_line(line.origin_value()),
            ),
        };
        let line_bytes = text.len().saturating_add(1);
        if preview_bytes.saturating_add(line_bytes) > MAX_DIFF_PATCH_BYTES {
            let remaining = MAX_DIFF_PATCH_BYTES.saturating_sub(preview_bytes);
            truncate_to_char_boundary(&mut text, remaining);
            truncated = true;
        }
        if !text.is_empty() {
            if lines.len() >= MAX_DIFF_PREVIEW_LINES {
                line_preview_truncated = true;
                return true;
            }
            preview_bytes = preview_bytes.saturating_add(text.len().saturating_add(1));
            lines.push(GitDiffLine { text, kind });
        }
        if truncated {
            return true;
        }
        true
    });
    match print_result {
        Ok(()) => {}
        Err(_) if truncated || line_preview_truncated => {}
        Err(error) => return Err(GitError::from_git2(error)),
    }

    Ok(RenderedDiff {
        lines,
        added,
        removed,
        is_binary,
        truncated,
        line_preview_truncated,
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

pub(super) fn diff_lines_byte_len(lines: &[GitDiffLine]) -> usize {
    lines
        .iter()
        .map(|line| line.text.len().saturating_add(1))
        .sum()
}

pub(super) fn truncate_diff_lines_to_bytes(lines: &mut Vec<GitDiffLine>, max_bytes: usize) -> bool {
    let mut used = 0usize;
    let mut keep = 0usize;
    for line in lines.iter_mut() {
        let line_bytes = line.text.len().saturating_add(1);
        if used.saturating_add(line_bytes) <= max_bytes {
            used = used.saturating_add(line_bytes);
            keep += 1;
            continue;
        }
        let remaining = max_bytes.saturating_sub(used);
        if remaining > 0 {
            truncate_to_char_boundary(&mut line.text, remaining);
            if !line.text.is_empty() {
                keep += 1;
            }
        }
        lines.truncate(keep);
        return true;
    }
    false
}

pub(super) fn diff_lines_from_patch(patch: &str) -> (Vec<GitDiffLine>, bool) {
    let mut lines = Vec::new();
    let mut truncated = false;
    for text in patch.lines() {
        if lines.len() >= MAX_DIFF_PREVIEW_LINES {
            truncated = true;
            break;
        }
        lines.push(GitDiffLine {
            text: text.to_string(),
            kind: kind_for_text(text),
        });
    }
    (lines, truncated)
}

fn kind_for_line(line_type: DiffLineType) -> GitDiffLineKind {
    match line_type {
        DiffLineType::Addition | DiffLineType::AddEOFNL => GitDiffLineKind::Addition,
        DiffLineType::Deletion | DiffLineType::DeleteEOFNL => GitDiffLineKind::Deletion,
        DiffLineType::HunkHeader => GitDiffLineKind::Hunk,
        DiffLineType::FileHeader | DiffLineType::Binary => GitDiffLineKind::Header,
        _ => GitDiffLineKind::Context,
    }
}

fn kind_for_text(text: &str) -> GitDiffLineKind {
    if text.starts_with("@@") {
        GitDiffLineKind::Hunk
    } else if text.starts_with("diff --git")
        || text.starts_with("index ")
        || text.starts_with("--- ")
        || text.starts_with("+++ ")
        || text.starts_with("new file mode ")
        || text.starts_with("deleted file mode ")
        || text.starts_with("rename from ")
        || text.starts_with("rename to ")
        || text.starts_with("similarity index ")
    {
        GitDiffLineKind::Header
    } else if text.starts_with('+') {
        GitDiffLineKind::Addition
    } else if text.starts_with('-') {
        GitDiffLineKind::Deletion
    } else {
        GitDiffLineKind::Context
    }
}
