use super::super::{open_repo, GitError, GitErrorKind, GitPathContext};

pub(super) fn submodule_child_workdir(
    path: &str,
    submodule_path: &str,
) -> Result<String, GitError> {
    let parent = open_repo(path)?;
    let paths = GitPathContext::new(&parent, path)?;
    let repo_path = paths.to_repo_path(submodule_path);
    let submodule = parent.find_submodule(&repo_path).map_err(|error| {
        GitError::new(
            GitErrorKind::WorkspaceScope,
            format!("configured submodule not found: {submodule_path}: {error}"),
        )
    })?;
    let child = submodule.open().map_err(GitError::from_git2)?;
    child
        .workdir()
        .map(|workdir| workdir.to_string_lossy().to_string())
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, submodule_path))
}
