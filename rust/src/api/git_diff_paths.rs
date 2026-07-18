use std::path::{Path, PathBuf};

use git2::Repository;

use super::{GitError, GitErrorKind};

pub(in crate::api) struct GitPathContext {
    workspace_prefix: String,
}

impl GitPathContext {
    pub(in crate::api) fn new(repo: &Repository, workspace_path: &str) -> Result<Self, GitError> {
        let Some(workdir) = repo.workdir() else {
            return Err(GitError::new(GitErrorKind::NotARepository, workspace_path));
        };
        let repo_root = canonicalize_lossy(workdir);
        let workspace_root = canonicalize_lossy(Path::new(workspace_path));
        let workspace_prefix = workspace_root
            .strip_prefix(&repo_root)
            .ok()
            .map(path_to_repo_string)
            .unwrap_or_default();
        Ok(Self { workspace_prefix })
    }

    pub(in crate::api) fn is_workspace_root(&self) -> bool {
        self.workspace_prefix.is_empty()
    }

    pub(in crate::api) fn to_workspace_path(&self, repo_path: &str) -> Option<String> {
        let repo_path = normalize_repo_path(repo_path);
        if self.workspace_prefix.is_empty() {
            return Some(repo_path);
        }
        if repo_path == self.workspace_prefix {
            return None;
        }
        repo_path
            .strip_prefix(&(self.workspace_prefix.clone() + "/"))
            .map(ToString::to_string)
    }

    pub(in crate::api) fn to_repo_path(&self, workspace_path: &str) -> String {
        let workspace_path = normalize_repo_path(workspace_path);
        if self.workspace_prefix.is_empty() {
            workspace_path
        } else if workspace_path.is_empty() {
            self.workspace_prefix.clone()
        } else {
            format!("{}/{workspace_path}", self.workspace_prefix)
        }
    }
}

fn canonicalize_lossy(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn path_to_repo_string(path: &Path) -> String {
    path.components()
        .filter_map(|component| {
            let text = component.as_os_str().to_string_lossy();
            if text.is_empty() {
                None
            } else {
                Some(text.to_string())
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}

fn normalize_repo_path(path: &str) -> String {
    path.replace('\\', "/")
        .split('/')
        .filter(|part| !part.is_empty() && *part != ".")
        .collect::<Vec<_>>()
        .join("/")
}
