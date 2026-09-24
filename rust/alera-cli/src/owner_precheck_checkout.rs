use alera_core::runtime::{OwnerAutomationPrecheckRequest, ProjectKind, WorkspaceKind};
use anyhow::{bail, Context, Result};

pub(crate) async fn inspect(
    request: &OwnerAutomationPrecheckRequest,
    kind: ProjectKind,
) -> Result<()> {
    let Some(scope) = request.workspace.clone() else {
        let inspection =
            crate::project_checkout_inspection::inspect(request.path.clone(), kind).await?;
        if inspection.path != request.path || inspection.automation_declared != Some(true) {
            bail!("Owner precheck requires the canonical registered checkout and its automation declaration");
        }
        return Ok(());
    };
    if scope.kind != WorkspaceKind::Linked || kind != ProjectKind::GitRepository {
        bail!("An exclusive owner precheck requires a linked Git worktree");
    }
    let path = request.path.clone();
    tokio::task::spawn_blocking(move || {
        let origin = scope
            .repository_path
            .context("The linked repository origin is missing")?;
        let canonical = |value: &str| -> Result<std::path::PathBuf> {
            let actual = std::fs::canonicalize(value)?;
            if actual.to_str() != Some(value) {
                bail!("Owner precheck paths must retain their canonical identity");
            }
            Ok(actual)
        };
        let checkout = canonical(&path)?;
        canonical(&origin)?;
        if path == origin
            || !alera_core::git::checkouts_share_repository(&origin, &path)?
            || !alera_core::git::list_worktrees(&origin)?
                .iter()
                .any(|entry| {
                    std::fs::canonicalize(&entry.path).is_ok_and(|value| value == checkout)
                })
        {
            bail!("The linked precheck checkout is not owned by its retained repository");
        }
        if !crate::automation_declaration::repository_declares_automation(&path, &path) {
            bail!("Owner precheck requires the linked checkout's automation declaration");
        }
        Ok(())
    })
    .await?
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::runtime::{AutomationPrecheck, AutomationPrecheckWorkspace};

    #[tokio::test]
    async fn linked_precheck_inspection_preserves_bare_origin_and_requires_exact_declared_worktree()
    {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().canonicalize().unwrap();
        let origin = root.join("legacy.git");
        let repo = git2::Repository::init_bare(&origin).unwrap();
        repo.set_head("refs/heads/main").unwrap();
        let tree = repo.treebuilder(None).unwrap().write().unwrap();
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
        let path = root.join("linked");
        alera_core::git::create_worktree(
            origin.to_str().unwrap(),
            "task",
            path.to_str().unwrap(),
            "main",
            false,
        )
        .unwrap();
        let request = OwnerAutomationPrecheckRequest {
            operation_id: uuid::Uuid::new_v4().to_string(),
            origin_id: "home".into(),
            run_id: "run".into(),
            project_id: "project".into(),
            path: path.to_str().unwrap().into(),
            workspace: Some(AutomationPrecheckWorkspace {
                workspace_id: "task".into(),
                instance_id: "instance".into(),
                kind: WorkspaceKind::Linked,
                repository_path: Some(origin.to_str().unwrap().into()),
            }),
            precheck: AutomationPrecheck {
                command: "never executed".into(),
                timeout_seconds: 10,
            },
        };
        assert!(inspect(&request, ProjectKind::GitRepository).await.is_err());
        std::fs::write(path.join("alera.toml"), "[automation]\ndeclared = true\n").unwrap();
        inspect(&request, ProjectKind::GitRepository).await.unwrap();
        assert!(inspect(&request, ProjectKind::Folder).await.is_err());
        let other = root.join("other.git");
        git2::Repository::init_bare(&other).unwrap();
        let mut changed = request.clone();
        changed.workspace.as_mut().unwrap().repository_path = Some(other.to_str().unwrap().into());
        assert!(inspect(&changed, ProjectKind::GitRepository).await.is_err());
        let child = path.join("child");
        std::fs::create_dir(&child).unwrap();
        changed = request.clone();
        changed.path = child.to_str().unwrap().into();
        assert!(inspect(&changed, ProjectKind::GitRepository).await.is_err());
        changed = request.clone();
        changed.path = format!("{}/.", request.path);
        assert!(inspect(&changed, ProjectKind::GitRepository).await.is_err());
        assert_eq!(
            alera_core::git::current_branch(origin.to_str().unwrap()).unwrap(),
            "main"
        );
        assert_eq!(
            alera_core::git::current_branch(path.to_str().unwrap()).unwrap(),
            "task"
        );
        assert!(path.join("alera.toml").exists());
    }
}
