use git2::{Diff, DiffFindOptions, DiffFormat, DiffLineType, DiffOptions, Oid};

use super::{
    build_untracked_patch, diff_for_area, diff_for_commit_range, git_status, git_status_for_path,
    open_repo, read_untracked_text, GitChangeArea, GitError, GitErrorKind, GitPathContext,
};

pub(crate) fn git_reading_diff_patch(
    path: String,
    file_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    base_ref: Option<String>,
) -> Result<Vec<u8>, GitError> {
    const MAX_READING_DIFF_BYTES: usize = 4 * 1024 * 1024;
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    if let Some(base_ref) = base_ref {
        if area.is_some() || commit_oid.is_some() || parent_oid.is_some() {
            return Err(GitError::new(
                GitErrorKind::Internal,
                "a range reading diff cannot also select a worktree area or commit",
            ));
        }
        let base_ref = base_ref.trim();
        if base_ref.is_empty() {
            return Err(GitError::new(
                GitErrorKind::InvalidBranchName,
                "base branch is empty",
            ));
        }
        let base_oid = repo
            .revparse_single(base_ref)
            .and_then(|object| object.peel_to_commit())
            .map(|commit| commit.id())
            .map_err(GitError::from_git2)?;
        let head_oid = super::super::current_head_commit(&repo)?
            .ok_or_else(|| {
                GitError::new(GitErrorKind::DetachedHead, "repository has no HEAD commit")
            })?
            .id();
        let merge_base = repo
            .merge_base(base_oid, head_oid)
            .map_err(GitError::from_git2)?;
        let base_tree = repo
            .find_commit(merge_base)
            .and_then(|commit| commit.tree())
            .map_err(GitError::from_git2)?;
        let head_tree = repo
            .find_commit(head_oid)
            .and_then(|commit| commit.tree())
            .map_err(GitError::from_git2)?;
        let mut options = DiffOptions::new();
        if let Some(file_path) = file_path.as_deref() {
            options.pathspec(paths.to_repo_path(file_path));
        }
        let mut diff = repo
            .diff_tree_to_tree(Some(&base_tree), Some(&head_tree), Some(&mut options))
            .map_err(GitError::from_git2)?;
        let mut find_options = DiffFindOptions::new();
        find_options.renames(true).copies(true);
        diff.find_similar(Some(&mut find_options))
            .map_err(GitError::from_git2)?;
        return raw_patch(&mut diff, MAX_READING_DIFF_BYTES);
    }
    if let Some(commit_oid) = commit_oid {
        if area.is_some() {
            return Err(GitError::new(
                GitErrorKind::Internal,
                "a commit reading diff cannot also select a worktree area",
            ));
        }
        let commit_oid = Oid::from_str(&commit_oid).map_err(GitError::from_git2)?;
        let parent_oid = parent_oid
            .as_deref()
            .map(Oid::from_str)
            .transpose()
            .map_err(GitError::from_git2)?;
        let repo_path = file_path.as_deref().map(|value| paths.to_repo_path(value));
        let pathspecs = repo_path.as_deref().into_iter().collect::<Vec<_>>();
        let mut diff = diff_for_commit_range(&repo, parent_oid, commit_oid, &pathspecs)?;
        return raw_patch(&mut diff, MAX_READING_DIFF_BYTES);
    }
    if parent_oid.is_some() {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "a parent commit requires a commit reading diff",
        ));
    }

    let status = if let Some(file_path) = &file_path {
        git_status_for_path(path.clone(), file_path.clone())?
    } else {
        git_status(path.clone())?
    };
    let mut output = Vec::new();
    for entry in status.entries {
        if area.is_some_and(|selected| selected != entry.area) {
            continue;
        }
        if file_path
            .as_ref()
            .is_some_and(|selected| selected != &entry.path)
        {
            continue;
        }
        let repo_path = paths.to_repo_path(&entry.path);
        if entry.area == GitChangeArea::Untracked {
            let value = read_untracked_text(&repo, &repo_path)?;
            if let Some(content) = value.content {
                output.extend_from_slice(
                    build_untracked_patch(&entry.path, &content, value.is_symlink).as_bytes(),
                );
            }
        } else {
            let mut diff = diff_for_area(&repo, &[repo_path.as_str()], entry.area)?;
            output.extend_from_slice(&raw_patch(
                &mut diff,
                MAX_READING_DIFF_BYTES.saturating_sub(output.len()),
            )?);
        }
        if output.len() > MAX_READING_DIFF_BYTES {
            return Err(GitError::new(
                GitErrorKind::Internal,
                "reading diff input exceeds the 4 MiB safety limit",
            ));
        }
    }
    Ok(output)
}

fn raw_patch(diff: &mut Diff<'_>, limit: usize) -> Result<Vec<u8>, GitError> {
    let mut output = Vec::new();
    let mut too_large = false;
    let result = diff.print(DiffFormat::Patch, |_delta, _hunk, line| {
        if too_large {
            return false;
        }
        let additional = line.content().len().saturating_add(1);
        if output.len().saturating_add(additional) > limit {
            too_large = true;
            return false;
        }
        match line.origin_value() {
            DiffLineType::Context
            | DiffLineType::Addition
            | DiffLineType::Deletion
            | DiffLineType::ContextEOFNL
            | DiffLineType::AddEOFNL
            | DiffLineType::DeleteEOFNL => output.push(line.origin() as u8),
            DiffLineType::FileHeader | DiffLineType::HunkHeader | DiffLineType::Binary => {}
        }
        output.extend_from_slice(line.content());
        true
    });
    if too_large {
        return Err(GitError::new(
            GitErrorKind::Internal,
            "reading diff input exceeds the 4 MiB safety limit",
        ));
    }
    result.map_err(GitError::from_git2)?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use std::fs;

    use git2::{IndexAddOption, Repository, Signature};

    use super::*;

    #[test]
    fn extracts_worktree_staged_commit_and_range_patches() {
        let directory = tempfile::tempdir().expect("tempdir");
        let repository = Repository::init(directory.path()).expect("repository");
        let file = directory.path().join("app.txt");
        fs::write(&file, "before\n").expect("initial file");
        let base = commit(&repository, "base");

        fs::write(&file, "worktree\n").expect("worktree file");
        let worktree = git_reading_diff_patch(
            directory.path().to_string_lossy().to_string(),
            Some("app.txt".to_string()),
            Some(GitChangeArea::Unstaged),
            None,
            None,
            None,
        )
        .expect("worktree patch");
        assert!(worktree
            .windows(b"+worktree".len())
            .any(|row| row == b"+worktree"));

        let mut index = repository.index().expect("index");
        index
            .add_path(std::path::Path::new("app.txt"))
            .expect("stage");
        index.write().expect("write index");
        let staged = git_reading_diff_patch(
            directory.path().to_string_lossy().to_string(),
            None,
            Some(GitChangeArea::Staged),
            None,
            None,
            None,
        )
        .expect("staged patch");
        assert!(staged
            .windows(b"-before".len())
            .any(|row| row == b"-before"));

        let head = commit(&repository, "change");
        let commit_patch = git_reading_diff_patch(
            directory.path().to_string_lossy().to_string(),
            None,
            None,
            Some(head.to_string()),
            Some(base.to_string()),
            None,
        )
        .expect("commit patch");
        let range_patch = git_reading_diff_patch(
            directory.path().to_string_lossy().to_string(),
            None,
            None,
            None,
            None,
            Some(base.to_string()),
        )
        .expect("range patch");
        assert_eq!(range_patch, commit_patch);
    }

    fn commit(repository: &Repository, message: &str) -> Oid {
        let mut index = repository.index().expect("index");
        index
            .add_all(["*"], IndexAddOption::DEFAULT, None)
            .expect("add files");
        index.write().expect("write index");
        let tree = repository
            .find_tree(index.write_tree().expect("tree id"))
            .expect("tree");
        let signature = Signature::now("Alera", "alera@example.com").expect("signature");
        let parent = repository
            .head()
            .ok()
            .and_then(|head| head.target())
            .map(|oid| repository.find_commit(oid).expect("parent"));
        let parents = parent.iter().collect::<Vec<_>>();
        repository
            .commit(
                Some("HEAD"),
                &signature,
                &signature,
                message,
                &tree,
                &parents,
            )
            .expect("commit")
    }
}
