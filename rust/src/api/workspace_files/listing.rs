use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use ignore::WalkBuilder;

use super::{
    entry_for_path, is_protected_child_path, resolve_existing, workspace_root, WorkspaceFileEntry,
    WorkspaceFileError, WorkspaceFileErrorKind, WorkspaceFileKind,
};

const LISTABLE_DESCENDANT_MAX_DEPTH: usize = 32;
const LISTABLE_DESCENDANT_MAX_VISITS: usize = 2048;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum HideIgnoredDirectoryKind {
    Listable,
    Empty,
    IgnoredOnly,
    Unknown,
}

pub(super) fn list_workspace_children(
    workspace_path: String,
    relative_path: String,
    hide_ignored: bool,
) -> Result<Vec<WorkspaceFileEntry>, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let directory = resolve_existing(&root, &relative_path)?;
    let metadata = fs::symlink_metadata(&directory)
        .map_err(|error| WorkspaceFileError::from_io(error, &relative_path))?;
    if !metadata.is_dir() {
        return Err(WorkspaceFileError::new(
            WorkspaceFileErrorKind::Unsupported,
            relative_path,
        ));
    }

    let paths = if hide_ignored {
        ignored_aware_children(&directory)?
    } else {
        read_dir_children(&directory)?
    };

    let mut entries = Vec::with_capacity(paths.len());
    for path in paths {
        if let Some(entry) = entry_for_path(&root, &path, hide_ignored)? {
            entries.push(entry);
        }
    }
    entries.sort_by(|left, right| {
        let left_dir = matches!(left.kind, WorkspaceFileKind::Directory);
        let right_dir = matches!(right.kind, WorkspaceFileKind::Directory);
        right_dir
            .cmp(&left_dir)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
            .then_with(|| left.name.cmp(&right.name))
    });
    Ok(entries)
}

fn ignored_aware_children(directory: &Path) -> Result<Vec<PathBuf>, WorkspaceFileError> {
    let mut paths = Vec::new();
    let walker = WalkBuilder::new(directory)
        .max_depth(Some(1))
        .hidden(false)
        .parents(true)
        .require_git(false)
        .build();
    for result in walker {
        let entry = result.map_err(|error| {
            WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
        })?;
        if entry.path() == directory {
            continue;
        }
        if is_protected_child_path(entry.path()) {
            continue;
        }
        paths.push(entry.path().to_path_buf());
    }
    Ok(paths)
}

fn read_dir_children(directory: &Path) -> Result<Vec<PathBuf>, WorkspaceFileError> {
    let mut paths = Vec::new();
    for result in fs::read_dir(directory)
        .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?
    {
        let entry = result
            .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?;
        if is_protected_child_path(&entry.path()) {
            continue;
        }
        paths.push(entry.path());
    }
    Ok(paths)
}

pub(super) fn has_unprotected_child(directory: &Path) -> Result<bool, WorkspaceFileError> {
    for result in fs::read_dir(directory)
        .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?
    {
        let entry = result
            .map_err(|error| WorkspaceFileError::from_io(error, directory.to_string_lossy()))?;
        if !is_protected_child_path(&entry.path()) {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(super) fn hide_ignored_directory_kind(directory: &Path) -> HideIgnoredDirectoryKind {
    match has_unprotected_child(directory) {
        Ok(false) => HideIgnoredDirectoryKind::Empty,
        Ok(true) => walk_listable_descendant(directory),
        Err(_) => HideIgnoredDirectoryKind::Unknown,
    }
}

fn lock_visited_directories(
    visited: &Mutex<HashSet<(u64, u64)>>,
) -> std::sync::MutexGuard<'_, HashSet<(u64, u64)>> {
    visited
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn walk_listable_descendant(directory: &Path) -> HideIgnoredDirectoryKind {
    let visited = Arc::new(Mutex::new(HashSet::new()));
    if let Some(id) = directory_identity(directory) {
        lock_visited_directories(&visited).insert(id);
    }
    let visited_for_filter = visited;
    let walker = WalkBuilder::new(directory)
        .hidden(false)
        .parents(true)
        .require_git(false)
        .follow_links(false)
        .max_depth(Some(LISTABLE_DESCENDANT_MAX_DEPTH))
        .filter_entry(move |entry| {
            if entry.depth() == 0 {
                return true;
            }
            if is_protected_child_path(entry.path()) {
                return false;
            }
            if entry
                .file_type()
                .is_some_and(|file_type| file_type.is_dir())
            {
                if let Some(id) = directory_identity(entry.path()) {
                    return lock_visited_directories(&visited_for_filter).insert(id);
                }
            }
            true
        })
        .build();

    let mut truncated = false;
    let mut saw_error = false;
    let mut visits = 0;
    for result in walker {
        let entry = match result {
            Ok(entry) => entry,
            Err(_) => {
                saw_error = true;
                continue;
            }
        };
        if entry.path() == directory {
            continue;
        }
        visits += 1;
        let Some(file_type) = entry.file_type() else {
            continue;
        };
        if !file_type.is_dir() {
            return HideIgnoredDirectoryKind::Listable;
        }
        match has_unprotected_child(entry.path()) {
            Ok(false) | Err(_) => return HideIgnoredDirectoryKind::Listable,
            Ok(true) if entry.depth() >= LISTABLE_DESCENDANT_MAX_DEPTH => truncated = true,
            Ok(true) => {}
        }
        if visits >= LISTABLE_DESCENDANT_MAX_VISITS {
            truncated = true;
            break;
        }
    }
    if truncated || saw_error {
        HideIgnoredDirectoryKind::Unknown
    } else {
        HideIgnoredDirectoryKind::IgnoredOnly
    }
}

fn directory_identity(path: &Path) -> Option<(u64, u64)> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let metadata = fs::symlink_metadata(path).ok()?;
        metadata
            .file_type()
            .is_dir()
            .then(|| (metadata.dev(), metadata.ino()))
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn workspace_path(dir: &tempfile::TempDir) -> String {
        dir.path().to_string_lossy().to_string()
    }

    fn entry_names(entries: &[WorkspaceFileEntry]) -> Vec<&str> {
        entries.iter().map(|entry| entry.name.as_str()).collect()
    }

    #[cfg(unix)]
    struct RestoreUnixMode {
        path: PathBuf,
        mode: u32,
    }

    #[cfg(unix)]
    impl Drop for RestoreUnixMode {
        fn drop(&mut self) {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&self.path, fs::Permissions::from_mode(self.mode));
        }
    }

    #[test]
    fn list_workspace_children_sorts_directories_and_filters_ignored_entries() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "ignored.txt\n").expect("write gitignore");
        fs::create_dir(workspace.path().join("src")).expect("create src");
        fs::write(workspace.path().join("src/main.dart"), "void main() {}\n").expect("write src");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");
        fs::write(workspace.path().join("ignored.txt"), "ignored\n").expect("write ignored");

        let entries =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let names = entries
            .iter()
            .map(|entry| entry.name.as_str())
            .collect::<Vec<_>>();

        assert!(names.contains(&"src"));
        assert!(names.contains(&"readme.md"));
        assert!(!names.contains(&"ignored.txt"));
        assert!(
            names.iter().position(|name| *name == "src").unwrap()
                < names.iter().position(|name| *name == "readme.md").unwrap()
        );

        let src = entries.iter().find(|entry| entry.name == "src").unwrap();
        assert_eq!(src.kind, WorkspaceFileKind::Directory);
        assert!(src.has_children_hint);
    }

    #[test]
    fn list_workspace_children_omits_directories_that_only_contain_ignored_files() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), ".codex/*\n").expect("write gitignore");
        fs::create_dir(workspace.path().join(".codex")).expect("create .codex");
        fs::write(workspace.path().join(".codex/config.json"), "{}\n").expect("write ignored file");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let hidden_names = entry_names(&hidden);
        assert!(hidden_names.contains(&"readme.md"));
        assert!(!hidden_names.contains(&".codex"));

        let shown =
            list_workspace_children(workspace_path(&workspace), String::new(), false).unwrap();
        let shown_names = entry_names(&shown);
        assert!(shown_names.contains(&".codex"));
        assert!(shown_names.contains(&"readme.md"));
    }

    #[test]
    fn list_workspace_children_omits_nested_ignored_only_trees() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "*.jsonl\n").expect("write gitignore");
        fs::create_dir_all(workspace.path().join(".codex/sessions")).expect("create sessions");
        fs::write(
            workspace.path().join(".codex/sessions/a.jsonl"),
            "session\n",
        )
        .expect("write session");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let hidden_names = entry_names(&hidden);
        assert!(hidden_names.contains(&"readme.md"));
        assert!(!hidden_names.contains(&".codex"));

        let shown =
            list_workspace_children(workspace_path(&workspace), String::new(), false).unwrap();
        assert!(entry_names(&shown).contains(&".codex"));
    }

    #[test]
    fn list_workspace_children_keeps_directories_with_tracked_and_ignored_files() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "ignored.txt\n").expect("write gitignore");
        fs::create_dir(workspace.path().join("src")).expect("create src");
        fs::write(workspace.path().join("src/ignored.txt"), "ignored\n").expect("write ignored");
        fs::write(workspace.path().join("src/main.dart"), "void main() {}\n").expect("write src");

        let root =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let src = root.iter().find(|entry| entry.name == "src").unwrap();
        assert_eq!(src.kind, WorkspaceFileKind::Directory);
        assert!(src.has_children_hint);

        let src_children =
            list_workspace_children(workspace_path(&workspace), "src".to_string(), true).unwrap();
        let src_names = entry_names(&src_children);
        assert!(src_names.contains(&"main.dart"));
        assert!(!src_names.contains(&"ignored.txt"));
    }

    #[test]
    fn list_workspace_children_keeps_truly_empty_directories_when_hiding_ignored() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::create_dir(workspace.path().join("empty")).expect("create empty");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        let entries =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let empty = entries.iter().find(|entry| entry.name == "empty").unwrap();
        assert_eq!(empty.kind, WorkspaceFileKind::Directory);
        assert!(!empty.has_children_hint);
        assert!(entry_names(&entries).contains(&"readme.md"));
    }

    #[test]
    fn list_workspace_children_keeps_directories_of_empty_subdirectories_when_hiding_ignored() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::create_dir_all(workspace.path().join("parent/child")).expect("create child");

        let root =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        assert_eq!(entry_names(&root), vec!["parent"]);
        assert!(root[0].has_children_hint);

        let parent =
            list_workspace_children(workspace_path(&workspace), "parent".to_string(), true)
                .unwrap();
        assert_eq!(entry_names(&parent), vec!["child"]);
        assert!(!parent[0].has_children_hint);
    }

    #[cfg(unix)]
    #[test]
    fn list_workspace_children_keeps_directory_when_descendant_probe_fails() {
        use std::os::unix::fs::PermissionsExt;

        let workspace = tempfile::tempdir().expect("tempdir");
        let secret = workspace.path().join("foo/secret");
        fs::create_dir_all(&secret).expect("create secret");
        fs::write(secret.join("hidden.txt"), "hidden\n").expect("write hidden");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");
        fs::set_permissions(&secret, fs::Permissions::from_mode(0o000)).expect("deny secret");
        let _restore = RestoreUnixMode {
            path: secret.clone(),
            mode: 0o700,
        };
        if fs::read_dir(&secret).is_ok() {
            return;
        }

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let hidden_names = entry_names(&hidden);
        assert!(hidden_names.contains(&"foo"));
        assert!(hidden_names.contains(&"readme.md"));
        let foo = hidden.iter().find(|entry| entry.name == "foo").unwrap();
        assert!(foo.has_children_hint);
    }

    #[cfg(unix)]
    #[test]
    fn list_workspace_children_keeps_expander_when_unreadable_dir_has_visible_sibling() {
        use std::os::unix::fs::PermissionsExt;

        let workspace = tempfile::tempdir().expect("tempdir");
        let secret = workspace.path().join("foo/secret");
        fs::create_dir_all(&secret).expect("create secret");
        fs::write(secret.join("hidden.txt"), "hidden\n").expect("write hidden");
        fs::write(workspace.path().join("foo/visible.txt"), "visible\n").expect("write visible");
        fs::set_permissions(&secret, fs::Permissions::from_mode(0o000)).expect("deny secret");
        let _restore = RestoreUnixMode {
            path: secret.clone(),
            mode: 0o700,
        };
        if fs::read_dir(&secret).is_ok() {
            return;
        }

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let foo = hidden.iter().find(|entry| entry.name == "foo").unwrap();
        assert!(foo.has_children_hint);

        let foo_children =
            list_workspace_children(workspace_path(&workspace), "foo".to_string(), true).unwrap();
        let foo_names = entry_names(&foo_children);
        assert!(foo_names.contains(&"visible.txt"));
        assert!(foo_names.contains(&"secret"));
    }

    #[test]
    fn list_workspace_children_keeps_directory_when_listable_walk_hits_depth_bound() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "ignored.txt\n").expect("write gitignore");
        let mut nested = workspace.path().join("deep");
        for index in 0..=LISTABLE_DESCENDANT_MAX_DEPTH {
            nested.push(format!("d{index}"));
        }
        fs::create_dir_all(&nested).expect("create deep tree");
        fs::write(nested.join("ignored.txt"), "ignored\n").expect("write ignored");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let hidden_names = entry_names(&hidden);
        assert!(hidden_names.contains(&"deep"));
        assert!(hidden_names.contains(&"readme.md"));
        let deep = hidden.iter().find(|entry| entry.name == "deep").unwrap();
        assert!(deep.has_children_hint);
    }

    #[test]
    fn list_workspace_children_keeps_directory_when_listable_walk_hits_visit_budget() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(workspace.path().join(".gitignore"), "ignored.txt\n").expect("write gitignore");
        let wide = workspace.path().join("wide");
        fs::create_dir(&wide).expect("create wide");
        for index in 0..=LISTABLE_DESCENDANT_MAX_VISITS {
            let child = wide.join(format!("d{index}"));
            fs::create_dir(&child).expect("create child");
            fs::write(child.join("ignored.txt"), "ignored\n").expect("write ignored");
        }
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        let hidden =
            list_workspace_children(workspace_path(&workspace), String::new(), true).unwrap();
        let hidden_names = entry_names(&hidden);
        assert!(hidden_names.contains(&"wide"));
        assert!(hidden_names.contains(&"readme.md"));
        let wide_entry = hidden.iter().find(|entry| entry.name == "wide").unwrap();
        assert!(wide_entry.has_children_hint);
    }

    #[test]
    fn list_workspace_children_always_hides_protected_git_directory() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::create_dir(workspace.path().join(".git")).expect("create git dir");
        fs::write(workspace.path().join(".git/config"), "protected").expect("write git config");
        fs::write(workspace.path().join("readme.md"), "# Alera\n").expect("write readme");

        for hide_ignored in [true, false] {
            let entries =
                list_workspace_children(workspace_path(&workspace), String::new(), hide_ignored)
                    .unwrap();
            let names = entries
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>();

            assert!(names.contains(&"readme.md"));
            assert!(!names.contains(&".git"));
        }
    }
}
