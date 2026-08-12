use std::collections::HashSet;
use std::path::{Path, PathBuf};

use git2::{ErrorCode, Repository, Status, StatusOptions};
use notify::Event;

use crate::terminal_host::host_error::HostResult;

use super::event_scope::{path_is_in_workspace, path_is_rename_source};
use super::{
    git_query_error, is_missing_ambiguous_rename, repository_path_from_bytes, PathIdentity,
    PathIdentityCache,
};

pub(super) fn event_is_git_relevant(
    repository: &Repository,
    root: &Path,
    event: &Event,
    ignored_prefixes: &mut HashSet<PathBuf>,
    path_identities: &mut PathIdentityCache,
) -> HostResult<bool> {
    let Some(workdir) = repository.workdir() else {
        return Ok(false);
    };
    let identities = event
        .paths
        .iter()
        .map(|path| path_identities.identity_for_event(&event.kind, path))
        .collect::<Vec<_>>();
    path_identities.apply_event(event, &identities);
    for (path_index, (path, identity)) in event.paths.iter().zip(identities).enumerate() {
        if !path_is_in_workspace(root, path) {
            continue;
        }
        let Ok(relative) = path.strip_prefix(workdir) else {
            continue;
        };
        let directory_like = identity == PathIdentity::Directory;
        if directory_like {
            if path_is_ignored(repository, relative, true, ignored_prefixes)? {
                let index = repository.index().map_err(git_query_error)?;
                if index.get_path(relative, 0).is_some()
                    || index.iter().any(|entry| {
                        repository_path_from_bytes(&entry.path).is_some_and(|entry_path| {
                            entry_path != relative && entry_path.starts_with(relative)
                        })
                    })
                {
                    return Ok(true);
                }
                continue;
            }
            let mut options = StatusOptions::new();
            options
                .include_untracked(true)
                .recurse_untracked_dirs(true)
                .include_ignored(false)
                .disable_pathspec_match(true)
                .pathspec(relative);
            if repository
                .statuses(Some(&mut options))
                .map_err(git_query_error)?
                .iter()
                .next()
                .is_some()
            {
                return Ok(true);
            }
            if path_is_rename_source(event, path_index)
                || is_missing_ambiguous_rename(&event.kind, path)
            {
                return Ok(true);
            }
            continue;
        }
        match repository.status_file(relative) {
            Ok(status) if status.contains(Status::IGNORED) => continue,
            Ok(_) => return Ok(true),
            Err(error) if error.code() == ErrorCode::Ambiguous => return Ok(true),
            Err(error) if error.code() == ErrorCode::NotFound => {
                if !path_is_ignored(repository, relative, directory_like, ignored_prefixes)? {
                    return Ok(true);
                }
            }
            Err(error) => return Err(git_query_error(error)),
        }
    }
    Ok(false)
}

fn path_is_ignored(
    repository: &Repository,
    relative: &Path,
    check_as_directory: bool,
    ignored_prefixes: &mut HashSet<PathBuf>,
) -> HostResult<bool> {
    if ignored_prefixes
        .iter()
        .any(|prefix| relative.starts_with(prefix))
    {
        return Ok(true);
    }
    if repository
        .status_should_ignore(relative)
        .map_err(git_query_error)?
    {
        ignored_prefixes.insert(relative.to_path_buf());
        return Ok(true);
    }
    if check_as_directory
        && repository
            .status_should_ignore(&relative.join(".alera-terminal-pulse-entry"))
            .map_err(git_query_error)?
    {
        ignored_prefixes.insert(relative.to_path_buf());
        return Ok(true);
    }
    Ok(false)
}
