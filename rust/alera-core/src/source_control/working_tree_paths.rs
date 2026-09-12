//! Workspace to repository path translation shared by the write operations.

use super::*;

pub(super) fn repo_path_is_in_scope(path: &str, scope: &str) -> bool {
    scope == "."
        || path == scope
        || path
            .strip_prefix(scope)
            .is_some_and(|remainder| remainder.starts_with('/'))
}

pub(super) fn repo_relative_path(
    repo: &Repository,
    workspace_path: &str,
    workspace_relative_path: &str,
) -> Result<String, GitError> {
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    repo_relative_path_from_workspace(repo, workspace_path, &workspace, workspace_relative_path)
}

pub(super) fn workspace_repo_relative_path(
    repo: &Repository,
    workspace_path: &str,
) -> Result<String, GitError> {
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    repo_relative_path_from_workspace(repo, workspace_path, &workspace, "")
}

fn repo_relative_path_from_workspace(
    repo: &Repository,
    workspace_path: &str,
    workspace: &Path,
    workspace_relative_path: &str,
) -> Result<String, GitError> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let workdir = std::fs::canonicalize(workdir).map_err(GitError::from_io)?;
    let target = workspace.join(relative_path(workspace_relative_path)?);
    let relative = target
        .strip_prefix(&workdir)
        .map_err(|_| GitError::new(GitErrorKind::Internal, "path outside repository"))?;
    Ok(pathspec_string(relative))
}

pub(super) fn scoped_pathspecs(
    repo: &Repository,
    workspace_path: &str,
    file_path: Option<&str>,
) -> Result<Vec<String>, GitError> {
    let workdir = repo
        .workdir()
        .ok_or_else(|| GitError::new(GitErrorKind::NotARepository, workspace_path))?;
    let workdir = std::fs::canonicalize(workdir).map_err(GitError::from_io)?;
    let workspace = std::fs::canonicalize(workspace_path).map_err(GitError::from_io)?;
    let target = match file_path {
        Some(file_path) => workspace.join(relative_path(file_path)?),
        None => workspace,
    };
    let relative = target
        .strip_prefix(&workdir)
        .map_err(|_| GitError::new(GitErrorKind::Internal, "path outside repository"))?;
    let pathspec = pathspec_string(relative);
    Ok(vec![pathspec])
}

pub(super) fn pathspec_string(path: &Path) -> String {
    let value = path
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().to_string()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/");
    if value.is_empty() {
        ".".to_string()
    } else {
        value
    }
}

pub(super) fn relative_path(path: &str) -> Result<PathBuf, GitError> {
    let source = Path::new(path);
    if source.is_absolute() {
        return Err(GitError::new(GitErrorKind::Internal, path));
    }
    let mut out = PathBuf::new();
    for component in source.components() {
        match component {
            Component::Normal(part) => out.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(GitError::new(GitErrorKind::Internal, path));
            }
        }
    }
    Ok(out)
}
