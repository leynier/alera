use std::path::{Path, PathBuf};

use notify::{Event, EventKind};

use super::{SourceControlWatchSignal, WorkspaceFileError};

pub(super) struct SourceControlWatchPaths {
    root: PathBuf,
    git_dir: Option<PathBuf>,
    common_dir: Option<PathBuf>,
}

impl SourceControlWatchPaths {
    pub(super) fn discover(root: PathBuf) -> Result<Self, WorkspaceFileError> {
        let repository = git2::Repository::discover(&root).ok();
        let canonical = |path: &Path| {
            path.canonicalize()
                .map_err(|error| WorkspaceFileError::from_io(error, "Git watch directory"))
        };
        Ok(Self {
            git_dir: repository
                .as_ref()
                .map(|repo| canonical(repo.path()))
                .transpose()?,
            common_dir: repository
                .as_ref()
                .map(|repo| canonical(repo.commondir()))
                .transpose()?,
            root,
        })
    }

    pub(super) fn roots(&self) -> Vec<PathBuf> {
        let mut roots = vec![self.root.clone()];
        // A linked worktree's .git is a pointer file. Its HEAD/index and shared
        // refs live elsewhere, and sibling worktree metadata must stay irrelevant.
        for path in self.common_dir.iter().chain(self.git_dir.iter()) {
            if !roots.iter().any(|root| path.starts_with(root)) {
                roots.push(path.clone());
            }
        }
        roots
    }

    pub(super) fn classify(&self, event: &Event) -> Option<SourceControlWatchSignal> {
        if matches!(event.kind, EventKind::Access(_)) {
            return None;
        }
        if event.need_rescan() {
            return Some(all_changes());
        }
        let mut signal = SourceControlWatchSignal::default();
        for path in &event.paths {
            let changes = self.classify_path(path);
            signal.worktree_changed |= changes.worktree_changed;
            signal.repository_changed |= changes.repository_changed;
            signal.catalog_changed |= changes.catalog_changed;
        }
        if signal.worktree_changed || signal.repository_changed || signal.catalog_changed {
            signal.coalesced_event_count = 1;
            Some(signal)
        } else {
            None
        }
    }

    fn classify_path(&self, path: &Path) -> SourceControlWatchSignal {
        if let Some(relative) = self
            .git_dir
            .as_ref()
            .and_then(|dir| path.strip_prefix(dir).ok())
        {
            return metadata_changes(relative, true);
        }
        if let Some(relative) = self
            .common_dir
            .as_ref()
            .and_then(|dir| path.strip_prefix(dir).ok())
        {
            return metadata_changes(relative, false);
        }
        let Ok(relative) = path.strip_prefix(&self.root) else {
            return SourceControlWatchSignal::default();
        };
        let components = relative
            .components()
            .filter_map(|component| component.as_os_str().to_str())
            .collect::<Vec<_>>();
        let first = components.first().copied();
        if first == Some(".git") {
            return if components.len() == 1 {
                all_changes()
            } else {
                SourceControlWatchSignal::default()
            };
        }
        if matches!(
            first,
            Some(".dart_tool" | "build" | "node_modules" | "target")
        ) || components.contains(&"node_modules")
        {
            return SourceControlWatchSignal::default();
        }
        SourceControlWatchSignal {
            worktree_changed: true,
            ..Default::default()
        }
    }
}

fn metadata_changes(relative: &Path, own_checkout: bool) -> SourceControlWatchSignal {
    let first = relative
        .components()
        .next()
        .and_then(|component| component.as_os_str().to_str());
    match first {
        Some("refs" | "packed-refs" | "config" | "config.worktree" | "shallow") => all_changes(),
        Some("HEAD" | "index" | "MERGE_HEAD" | "CHERRY_PICK_HEAD" | "REBASE_HEAD")
            if own_checkout =>
        {
            SourceControlWatchSignal {
                repository_changed: true,
                ..Default::default()
            }
        }
        Some("info") if relative == Path::new("info/exclude") => SourceControlWatchSignal {
            worktree_changed: true,
            ..Default::default()
        },
        _ => SourceControlWatchSignal::default(),
    }
}

pub(super) fn all_changes() -> SourceControlWatchSignal {
    SourceControlWatchSignal {
        coalesced_event_count: 1,
        worktree_changed: true,
        repository_changed: true,
        catalog_changed: true,
    }
}
