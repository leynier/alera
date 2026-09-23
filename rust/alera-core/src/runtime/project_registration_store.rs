use anyhow::{bail, Result};

use super::{format_timestamp, Project, RuntimeStore, Workspace, WorkspaceKind, LOCAL_HOST_ID};

impl RuntimeStore {
    pub async fn insert_project_with_initial_workspace(
        &self,
        project: &Project,
        workspace: &Workspace,
    ) -> Result<()> {
        if project.id.trim().is_empty()
            || workspace.id.trim().is_empty()
            || workspace.instance_id.trim().is_empty()
            || workspace.project_id != project.id
            || workspace.host_id != LOCAL_HOST_ID
            || workspace.kind != WorkspaceKind::Main
            || workspace.path != project.repo_path
        {
            bail!("Initial workspace must belong to the new project's local checkout");
        }
        let checkout_path = self.checkout_path_for_write(workspace).await?;
        let mut tx = self.pool().begin().await?;
        // INSERT preserves an existing identity if another registration wins the race.
        sqlx::query("INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind) VALUES (?, ?, ?, ?, ?, ?)")
            .bind(&project.id).bind(&project.name).bind(&project.repo_path)
            .bind(format_timestamp(project.created_at)).bind(format_timestamp(project.updated_at))
            .bind(project.kind.as_str()).execute(&mut *tx).await?;
        super::checkout_store::bind_workspace_checkout(&mut tx, workspace, &checkout_path).await?;
        super::workspace_record_write::write_workspace_record(&mut tx, workspace, false).await?;
        tx.commit().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::checkout_store_tests::{fixture, workspace};

    #[tokio::test]
    async fn registration_rolls_back_project_and_checkout_when_task_identity_collides() {
        let (_directory, store, existing) = fixture().await;
        let original = workspace("existing-task", LOCAL_HOST_ID, "/repo", WorkspaceKind::Main);
        store.insert_workspace(original.clone()).await.unwrap();
        let mut project = existing.clone();
        project.id = "new-project".into();
        project.repo_path = "/another-repo".into();
        let mut initial = original.clone();
        initial.project_id = project.id.clone();
        initial.path = project.repo_path.clone();
        assert!(store
            .insert_project_with_initial_workspace(&project, &initial)
            .await
            .is_err());
        assert!(store.find_project(&project.id).await.unwrap().is_none());
        assert!(store
            .find_project_checkout(&project.id, LOCAL_HOST_ID)
            .await
            .unwrap()
            .is_none());
        assert_eq!(
            store
                .find_workspace(&original.id)
                .await
                .unwrap()
                .unwrap()
                .project_id,
            original.project_id
        );
        assert_eq!(
            store
                .find_workspace_checkout(&original.id)
                .await
                .unwrap()
                .unwrap()
                .project_id,
            original.project_id
        );
    }

    #[tokio::test]
    async fn registration_is_atomic_and_never_overwrites_an_existing_project() {
        let (_directory, store, mut project) = fixture().await;
        project.id = "new-project".into();
        project.repo_path = "/new-repo".into();
        let mut initial = workspace(
            "initial",
            LOCAL_HOST_ID,
            &project.repo_path,
            WorkspaceKind::Main,
        );
        initial.project_id = project.id.clone();
        store
            .insert_project_with_initial_workspace(&project, &initial)
            .await
            .unwrap();
        assert_eq!(
            store
                .workspace_terminal_launch_attempted(&initial.id, &initial.instance_id)
                .await
                .unwrap(),
            Some(false)
        );
        project.name = "Must not replace".into();
        initial.id = "second-initial".into();
        assert!(store
            .insert_project_with_initial_workspace(&project, &initial)
            .await
            .is_err());
        assert_ne!(
            store.find_project(&project.id).await.unwrap().unwrap().name,
            project.name
        );
        assert!(store.find_workspace(&initial.id).await.unwrap().is_none());
        assert!(store
            .find_project_checkout(&project.id, LOCAL_HOST_ID)
            .await
            .unwrap()
            .is_some());
    }
}
