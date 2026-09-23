use std::path::{Component, Path};

use git2::StatusOptions;

use super::{open_repo, GitError, GitErrorKind};

/// A relocation setup must not replace transferred or subsequently edited files,
/// including deleted paths and untracked files below a copied directory.
pub fn validate_relocated_setup_copy(path: &str, destination: &str) -> Result<(), GitError> {
    let target = Path::new(destination);
    if destination.is_empty()
        || target
            .components()
            .any(|part| !matches!(part, Component::Normal(_) | Component::CurDir))
    {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "Invalid setup copy destination",
        ));
    }
    let target: std::path::PathBuf = target
        .components()
        .filter(|part| !matches!(part, Component::CurDir))
        .collect();
    if target.as_os_str().is_empty()
        || target
            .components()
            .any(|part| part.as_os_str().eq_ignore_ascii_case(".git"))
    {
        return Err(GitError::new(
            GitErrorKind::Conflict,
            "Setup cannot replace the checkout root or Git metadata",
        ));
    }
    let repo = open_repo(path)?;
    let ignore_case = cfg!(windows)
        || repo
            .config()
            .and_then(|config| config.get_bool("core.ignorecase"))
            .unwrap_or(false);
    let mut options = StatusOptions::new();
    options
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_ignored(true)
        .recurse_ignored_dirs(true);
    let statuses = repo
        .statuses(Some(&mut options))
        .map_err(GitError::from_git2)?;
    for entry in statuses.iter() {
        for delta in [entry.head_to_index(), entry.index_to_workdir()]
            .into_iter()
            .flatten()
        {
            for file in [delta.old_file(), delta.new_file()] {
                let Some(changed) = file.path() else {
                    return Err(GitError::new(
                        GitErrorKind::Conflict,
                        "Cannot verify the setup copy against a changed path",
                    ));
                };
                if paths_overlap(changed, &target, ignore_case) {
                    return Err(GitError::new(
                        GitErrorKind::Conflict,
                        format!(
                            "Setup copy would replace local data at {}; files were preserved",
                            changed.display()
                        ),
                    ));
                }
            }
        }
    }
    Ok(())
}

fn paths_overlap(left: &Path, right: &Path, ignore_case: bool) -> bool {
    if !ignore_case {
        return left.starts_with(right) || right.starts_with(left);
    }
    let folded = |path: &Path| {
        path.components()
            .map(|part| part.as_os_str().to_string_lossy().to_lowercase())
            .collect::<Vec<_>>()
    };
    let left = folded(left);
    let right = folded(right);
    left.starts_with(&right) || right.starts_with(&left)
}

#[cfg(test)]
mod tests {
    use super::*;
    use git2::{IndexAddOption, Repository, Signature};

    #[test]
    fn protects_modified_deleted_staged_untracked_and_ignored_paths() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().to_str().unwrap();
        let repo = Repository::init(path).unwrap();
        for name in ["modified", "deleted", "staged", "clean", ".gitignore"] {
            std::fs::write(
                root.path().join(name),
                if name == ".gitignore" {
                    "ignored\n"
                } else {
                    "base"
                },
            )
            .unwrap();
        }
        let mut index = repo.index().unwrap();
        index.add_all(["*"], IndexAddOption::DEFAULT, None).unwrap();
        index.write().unwrap();
        let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
        let signature = Signature::now("Test", "test@example.com").unwrap();
        repo.commit(Some("HEAD"), &signature, &signature, "base", &tree, &[])
            .unwrap();
        std::fs::write(root.path().join("modified"), "edited").unwrap();
        std::fs::remove_file(root.path().join("deleted")).unwrap();
        std::fs::write(root.path().join("staged"), "staged edit").unwrap();
        index.add_path(Path::new("staged")).unwrap();
        index.write().unwrap();
        std::fs::create_dir(root.path().join("untracked")).unwrap();
        std::fs::write(root.path().join("untracked/file"), "new").unwrap();
        std::fs::write(root.path().join("ignored"), "private").unwrap();
        for target in ["modified", "deleted", "staged", "untracked", "ignored", "."] {
            assert!(
                validate_relocated_setup_copy(path, target).is_err(),
                "{target}"
            );
        }
        for target in ["clean", "modified-other", "new"] {
            validate_relocated_setup_copy(path, target).unwrap();
        }
        repo.config()
            .unwrap()
            .set_bool("core.ignorecase", true)
            .unwrap();
        assert!(validate_relocated_setup_copy(path, "MODIFIED").is_err());
        assert!(validate_relocated_setup_copy(path, ".git/config").is_err());
    }
}
