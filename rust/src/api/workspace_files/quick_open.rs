use std::fs;
use std::path::Path;

use ignore::WalkBuilder;

use super::{
    content_token, is_protected_child_path, is_protected_relative_path, modified_millis,
    relative_string, workspace_root, WorkspaceFileEntry, WorkspaceFileError,
    WorkspaceFileErrorKind, WorkspaceFileKind,
};

const MAX_QUICK_OPEN_FILES: usize = 20_000;

pub(super) fn list_workspace_files(
    workspace_path: String,
    max_results: u32,
) -> Result<Vec<WorkspaceFileEntry>, WorkspaceFileError> {
    let root = workspace_root(&workspace_path)?;
    let result_limit = (max_results as usize).min(MAX_QUICK_OPEN_FILES);
    if result_limit == 0 {
        return Ok(Vec::new());
    }

    let filter_root = root.clone();
    let walker = WalkBuilder::new(&root)
        .hidden(false)
        .parents(true)
        .require_git(false)
        .follow_links(false)
        .filter_entry(move |entry| {
            entry.path() == filter_root || !is_protected_child_path(entry.path())
        })
        .build();
    let mut entries = Vec::with_capacity(result_limit.min(1024));
    for result in walker {
        if entries.len() >= result_limit {
            break;
        }
        let entry = result.map_err(|error| {
            WorkspaceFileError::new(WorkspaceFileErrorKind::Io, error.to_string())
        })?;
        if let Some(file) = quick_open_entry(&root, entry.path())? {
            entries.push(file);
        }
    }

    entries.sort_by(|left, right| {
        left.relative_path
            .to_lowercase()
            .cmp(&right.relative_path.to_lowercase())
            .then_with(|| left.relative_path.cmp(&right.relative_path))
    });
    Ok(entries)
}

fn quick_open_entry(
    root: &Path,
    path: &Path,
) -> Result<Option<WorkspaceFileEntry>, WorkspaceFileError> {
    let relative_path = relative_string(root, path)?;
    if relative_path.is_empty() || is_protected_relative_path(&relative_path) {
        return Ok(None);
    }

    let link_metadata = fs::symlink_metadata(path)
        .map_err(|error| WorkspaceFileError::from_io(error, path.to_string_lossy()))?;
    let is_symlink = link_metadata.file_type().is_symlink();
    if is_symlink {
        let canonical = match fs::canonicalize(path) {
            Ok(canonical) => canonical,
            Err(_) => return Ok(None),
        };
        if !canonical.starts_with(root) {
            return Ok(None);
        }
        let canonical_relative = relative_string(root, &canonical)?;
        if is_protected_relative_path(&canonical_relative) {
            return Ok(None);
        }
    }

    let metadata = if is_symlink {
        match fs::metadata(path) {
            Ok(metadata) => metadata,
            Err(_) => return Ok(None),
        }
    } else {
        link_metadata
    };
    if !metadata.is_file() {
        return Ok(None);
    }
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| relative_path.clone());
    Ok(Some(WorkspaceFileEntry {
        relative_path,
        name: name.clone(),
        kind: if is_symlink {
            WorkspaceFileKind::Symlink
        } else {
            WorkspaceFileKind::File
        },
        size: metadata.len(),
        modified_millis: modified_millis(&metadata),
        content_token: content_token(&metadata),
        is_ignored: false,
        is_hidden: name.starts_with('.'),
        is_symlink,
        is_protected: false,
        has_children_hint: false,
        git_status: None,
    }))
}

#[cfg(test)]
mod tests {
    use std::io;
    use std::path::Path;

    use super::*;

    fn workspace_path(dir: &tempfile::TempDir) -> String {
        dir.path().to_string_lossy().into_owned()
    }

    fn create_file_symlink(source: &Path, link: &Path) -> io::Result<()> {
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(source, link)
        }
        #[cfg(windows)]
        {
            std::os::windows::fs::symlink_file(source, link)
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = (source, link);
            Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "file symlinks are unsupported on this platform",
            ))
        }
    }

    #[test]
    fn list_workspace_files_recurses_and_uses_workspace_ignore_rules() {
        let workspace = tempfile::tempdir().expect("tempdir");
        fs::write(
            workspace.path().join(".gitignore"),
            "ignored.txt\nignored-dir/\n",
        )
        .expect("write gitignore");
        fs::create_dir_all(workspace.path().join("src/nested")).expect("create nested dirs");
        fs::write(workspace.path().join("src/main.dart"), "void main() {}").expect("write main");
        fs::write(workspace.path().join("src/nested/helper.dart"), "helper").expect("write helper");
        fs::write(workspace.path().join("ignored.txt"), "ignored").expect("write ignored");
        fs::create_dir(workspace.path().join("ignored-dir")).expect("create ignored dir");
        fs::write(workspace.path().join("ignored-dir/secret.txt"), "ignored")
            .expect("write ignored secret");
        for protected in [".git", ".hg", ".svn"] {
            fs::create_dir(workspace.path().join(protected)).expect("create protected dir");
            fs::write(workspace.path().join(protected).join("secret"), "protected")
                .expect("write protected file");
        }

        let entries = list_workspace_files(workspace_path(&workspace), 100).unwrap();
        let paths = entries
            .iter()
            .map(|entry| entry.relative_path.as_str())
            .collect::<Vec<_>>();

        assert!(paths.contains(&".gitignore"));
        assert!(paths.contains(&"src/main.dart"));
        assert!(paths.contains(&"src/nested/helper.dart"));
        assert!(!paths.contains(&"ignored.txt"));
        assert!(!paths.contains(&"ignored-dir/secret.txt"));
        assert!(!paths.iter().any(|path| {
            path.starts_with(".git/") || path.starts_with(".hg/") || path.starts_with(".svn/")
        }));
    }

    #[test]
    fn list_workspace_files_respects_result_bound() {
        let workspace = tempfile::tempdir().expect("tempdir");
        for name in ["one.txt", "two.txt", "three.txt", "four.txt"] {
            fs::write(workspace.path().join(name), name).expect("write file");
        }

        let entries = list_workspace_files(workspace_path(&workspace), 2).unwrap();

        assert_eq!(entries.len(), 2);
        assert!(entries
            .iter()
            .all(|entry| matches!(entry.kind, WorkspaceFileKind::File)));
    }

    #[test]
    fn list_workspace_files_skips_symlink_escapes_and_keeps_local_files() {
        let workspace = tempfile::tempdir().expect("tempdir");
        let outside = tempfile::tempdir().expect("outside tempdir");
        let outside_file = outside.path().join("outside.txt");
        fs::write(&outside_file, "outside").expect("write outside file");
        let outside_link = workspace.path().join("outside-link.txt");
        if let Err(error) = create_file_symlink(&outside_file, &outside_link) {
            eprintln!("skipping symlink test because symlink creation failed: {error}");
            return;
        }

        let local_file = workspace.path().join("local.txt");
        fs::write(&local_file, "local").expect("write local file");
        let local_link = workspace.path().join("local-link.txt");
        if let Err(error) = create_file_symlink(&local_file, &local_link) {
            eprintln!("skipping local symlink assertion because symlink creation failed: {error}");
            return;
        }

        let entries = list_workspace_files(workspace_path(&workspace), 100).unwrap();
        let paths = entries
            .iter()
            .map(|entry| entry.relative_path.as_str())
            .collect::<Vec<_>>();

        assert!(paths.contains(&"local.txt"));
        assert!(paths.contains(&"local-link.txt"));
        assert!(!paths.contains(&"outside-link.txt"));
    }
}
