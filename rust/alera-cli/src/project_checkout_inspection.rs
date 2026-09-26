use alera_core::runtime::ProjectKind;
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

pub(crate) const INSPECTION_VERSION: u32 = 1;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CheckoutInspection {
    pub version: u32,
    pub path: String,
    pub kind: ProjectKind,
    pub branch: Option<String>,
    #[serde(default)]
    pub automation_declared: Option<bool>,
}

pub(crate) async fn inspect(path: String, kind: ProjectKind) -> Result<CheckoutInspection> {
    tokio::task::spawn_blocking(move || {
        if path.trim().is_empty() {
            bail!("A checkout path is required");
        }
        let canonical = crate::windows_path_form::canonicalize(path).context("Project checkout is unavailable")?;
        // Opening the directory verifies access without changing its contents.
        let mut entries = std::fs::read_dir(&canonical).context("Project checkout is not accessible")?;
        if let Some(entry) = entries.next() {
            entry.context("Project checkout is not readable")?;
        }
        let path = canonical.to_str().ok_or_else(|| anyhow!("Checkout path is not valid UTF-8"))?.to_string();
        let branch = match kind {
            ProjectKind::GitRepository => Some(alera_core::git::project_checkout_branch(&path)?),
            ProjectKind::Folder => {
                // Presence of `.git` is not enough: an empty leftover is not a checkout.
                if alera_core::git::project_checkout_branch(&path).is_ok() {
                    bail!("The selected folder is a Git checkout but this project is registered as a folder");
                }
                None
            }
        };
        let automation_declared = Some(crate::automation_declaration::repository_declares_automation(&path, &path));
        Ok(CheckoutInspection { version: INSPECTION_VERSION, path, kind, branch, automation_declared })
    }).await?
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LinkedCheckoutInspection {
    pub version: u32,
    pub path: String,
    pub repository_path: String,
    pub branch: String,
}

pub(crate) async fn inspect_linked(path: String) -> Result<LinkedCheckoutInspection> {
    tokio::task::spawn_blocking(move || {
        let repository_path = alera_core::git::linked_worktree_repository_origin(&path)?;
        let path = crate::windows_path_form::canonicalize(path)?
            .to_str()
            .ok_or_else(|| anyhow!("Linked checkout path is not valid UTF-8"))?
            .to_string();
        let branch = alera_core::git::current_branch(&path)?;
        Ok(LinkedCheckoutInspection {
            version: 1,
            path,
            repository_path,
            branch,
        })
    })
    .await?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn inspects_folder_without_changing_files_and_rejects_wrong_kind() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("keep"), "unchanged").unwrap();
        let path = dir.path().to_str().unwrap().to_string();
        let result = inspect(path.clone(), ProjectKind::Folder).await.unwrap();
        assert_eq!(
            result.path,
            dir.path().canonicalize().unwrap().to_str().unwrap()
        );
        assert!(result.branch.is_none());
        assert_eq!(result.automation_declared, Some(false));
        std::fs::write(
            dir.path().join("alera.toml"),
            "[automation]\ndeclared = true\n",
        )
        .unwrap();
        assert_eq!(
            inspect(path.clone(), ProjectKind::Folder)
                .await
                .unwrap()
                .automation_declared,
            Some(true)
        );
        assert!(inspect(path, ProjectKind::GitRepository).await.is_err());
        assert_eq!(
            std::fs::read_to_string(dir.path().join("keep")).unwrap(),
            "unchanged"
        );
    }

    #[tokio::test]
    async fn rejects_missing_paths_and_files() {
        let dir = tempfile::tempdir().unwrap();
        for path in [dir.path().join("missing"), dir.path().join("file")] {
            if path.ends_with("file") {
                std::fs::write(&path, "file").unwrap();
            }
            assert!(inspect(path.to_str().unwrap().into(), ProjectKind::Folder)
                .await
                .is_err());
        }
    }

    #[tokio::test]
    async fn folder_inspection_ignores_leftover_git_entries_and_rejects_real_checkouts() {
        let dir = tempfile::tempdir().unwrap();
        let leftover = dir.path().join("leftover");
        std::fs::create_dir(&leftover).unwrap();
        std::fs::create_dir(leftover.join(".git")).unwrap();
        inspect(leftover.to_str().unwrap().into(), ProjectKind::Folder)
            .await
            .unwrap();

        let git_file = dir.path().join("git-file");
        std::fs::create_dir(&git_file).unwrap();
        std::fs::write(git_file.join(".git"), "not a gitdir pointer").unwrap();
        inspect(git_file.to_str().unwrap().into(), ProjectKind::Folder)
            .await
            .unwrap();

        let nested = dir.path().join("nested");
        std::fs::create_dir(&nested).unwrap();
        init_main_repo(&nested.join("main"));
        inspect(nested.to_str().unwrap().into(), ProjectKind::Folder)
            .await
            .unwrap();

        let checkout = dir.path().join("checkout");
        init_main_repo(&checkout);
        let error = inspect(checkout.to_str().unwrap().into(), ProjectKind::Folder)
            .await
            .unwrap_err();
        assert!(error.to_string().contains(
            "The selected folder is a Git checkout but this project is registered as a folder"
        ));
    }

    fn init_main_repo(path: &std::path::Path) {
        std::fs::create_dir_all(path).unwrap();
        let repo = git2::Repository::init(path).unwrap();
        repo.set_head("refs/heads/main").unwrap();
        let tree = repo.index().unwrap().write_tree().unwrap();
        let signature = git2::Signature::now("Test", "test@example.test").unwrap();
        repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            "Initial",
            &repo.find_tree(tree).unwrap(),
            &[],
        )
        .unwrap();
    }
}
