use anyhow::Result;

use super::{RuntimeStore, Workspace};

impl RuntimeStore {
    pub async fn read_workspace_retirement_receipt(
        runtime_dir: &std::path::Path,
        workspace_id: &str,
        instance_id: &str,
    ) -> Result<Option<Workspace>> {
        use sqlx::Connection;
        let path = runtime_dir.join(super::store::RUNTIME_DATABASE_FILE_NAME);
        match std::fs::metadata(&path) {
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        }
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(path)
            .read_only(true)
            .create_if_missing(false);
        let mut connection = sqlx::SqliteConnection::connect_with(&options).await?;
        let result = async {
            let exists: i64 = sqlx::query_scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'workspaceRetirements'")
                .fetch_one(&mut connection).await?;
            if exists == 0 { return Ok(None); }
            let json: Option<String> = sqlx::query_scalar("SELECT workspaceJson FROM workspaceRetirements WHERE workspaceId = ? AND instanceId = ?")
                .bind(workspace_id).bind(instance_id).fetch_optional(&mut connection).await?;
            json.map(|json| serde_json::from_str(&json).map_err(Into::into)).transpose()
        }.await;
        connection.close().await?;
        result
    }

    pub(super) async fn migrate_workspace_retirements(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in [
            "CREATE TABLE IF NOT EXISTS workspaceRetirements (workspaceId TEXT NOT NULL, instanceId TEXT NOT NULL, workspaceJson TEXT NOT NULL, PRIMARY KEY(workspaceId, instanceId))",
            "CREATE TRIGGER IF NOT EXISTS rejectRetiredWorkspaceInsert BEFORE INSERT ON workspaces WHEN EXISTS (SELECT 1 FROM workspaceRetirements WHERE workspaceId = NEW.id AND instanceId = NEW.instanceId) BEGIN SELECT RAISE(ABORT, 'Workspace instance was retired'); END",
            "CREATE TRIGGER IF NOT EXISTS rejectRetiredWorkspaceUpdate BEFORE UPDATE ON workspaces WHEN EXISTS (SELECT 1 FROM workspaceRetirements WHERE workspaceId = NEW.id AND instanceId = NEW.instanceId) BEGIN SELECT RAISE(ABORT, 'Workspace instance was retired'); END",
        ] {
            sqlx::query(statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn workspace_retirement_receipt(
        &self,
        workspace_id: &str,
        instance_id: &str,
    ) -> Result<Option<Workspace>> {
        let json: Option<String> = sqlx::query_scalar("SELECT workspaceJson FROM workspaceRetirements WHERE workspaceId = ? AND instanceId = ?")
            .bind(workspace_id).bind(instance_id).fetch_optional(self.pool()).await?;
        json.map(|json| serde_json::from_str(&json).map_err(Into::into))
            .transpose()
    }

    /// The caller must complete buffer and owned-process checks before this transaction.
    pub async fn retire_verified_shared_workspace(&self, workspace: &Workspace) -> Result<()> {
        if workspace.kind != super::WorkspaceKind::Main {
            anyhow::bail!("Only shared tasks may use shared retirement receipts");
        }
        self.remove_workspace_with_receipt(&workspace.id, true, Some(workspace), None, None)
            .await
    }

    /// Persist only after owned processes and physical linked-worktree cleanup finish.
    pub async fn retire_verified_linked_workspace(&self, workspace: &Workspace) -> Result<()> {
        if workspace.kind != super::WorkspaceKind::Linked
            || workspace.host_id != super::LOCAL_HOST_ID
        {
            anyhow::bail!("Linked retirement requires the local checkout owner");
        }
        self.remove_workspace_with_receipt(&workspace.id, true, Some(workspace), None, None)
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::checkout_store_tests::{fixture, workspace};
    use crate::runtime::WorkspaceKind;

    #[tokio::test]
    async fn linked_receipt_survives_restart_and_requires_the_local_owner() {
        let (directory, store, _) = fixture().await;
        let task = workspace("linked", "local", "/linked", WorkspaceKind::Linked);
        store.insert_workspace(task.clone()).await.unwrap();
        let mut foreign = task.clone();
        foreign.host_id = "ssh".into();
        assert!(store
            .retire_verified_linked_workspace(&foreign)
            .await
            .is_err());
        assert!(store.find_workspace(&task.id).await.unwrap().is_some());
        assert!(store
            .workspace_retirement_receipt(&task.id, &task.instance_id)
            .await
            .unwrap()
            .is_none());
        store.retire_verified_linked_workspace(&task).await.unwrap();
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            reopened
                .workspace_retirement_receipt(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(task.clone())
        );
        assert!(reopened.find_workspace(&task.id).await.unwrap().is_none());
        assert!(reopened.insert_workspace(task).await.is_err());
    }

    #[tokio::test]
    async fn receipt_lookup_does_not_create_or_migrate_a_store() {
        use sqlx::Connection;
        let directory = tempfile::tempdir().unwrap();
        assert!(RuntimeStore::read_workspace_retirement_receipt(
            directory.path(),
            "task",
            "instance"
        )
        .await
        .unwrap()
        .is_none());
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
        let options = sqlx::sqlite::SqliteConnectOptions::new()
            .filename(
                directory
                    .path()
                    .join(super::super::store::RUNTIME_DATABASE_FILE_NAME),
            )
            .create_if_missing(true);
        let mut database = sqlx::SqliteConnection::connect_with(&options)
            .await
            .unwrap();
        sqlx::query("CREATE TABLE retained (value TEXT)")
            .execute(&mut database)
            .await
            .unwrap();
        assert!(RuntimeStore::read_workspace_retirement_receipt(
            directory.path(),
            "task",
            "instance"
        )
        .await
        .unwrap()
        .is_none());
        let count: i64 =
            sqlx::query_scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table'")
                .fetch_one(&mut database)
                .await
                .unwrap();
        assert_eq!(count, 1);
        database.close().await.unwrap();
    }

    #[tokio::test]
    async fn retirement_is_durable_and_rejects_resurrection_without_affecting_neighbors() {
        let (directory, store, _) = fixture().await;
        let task = workspace("task", "local", "/repo", WorkspaceKind::Main);
        let peer = workspace("peer", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        store.insert_workspace(peer.clone()).await.unwrap();
        store.retire_verified_shared_workspace(&task).await.unwrap();
        assert_eq!(
            RuntimeStore::read_workspace_retirement_receipt(
                directory.path(),
                &task.id,
                &task.instance_id
            )
            .await
            .unwrap(),
            Some(task.clone())
        );
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            reopened
                .workspace_retirement_receipt(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(task.clone())
        );
        assert!(reopened.find_workspace(&task.id).await.unwrap().is_none());
        assert!(reopened.find_workspace(&peer.id).await.unwrap().is_some());
        assert!(reopened.insert_workspace(task.clone()).await.is_err());
        assert!(reopened.upsert_workspace(task.clone()).await.is_err());
        assert!(reopened
            .workspace_retirement_receipt(&task.id, "another-instance")
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn stale_retirement_rolls_back_without_a_receipt() {
        let (_directory, store, _) = fixture().await;
        let mut task = workspace("task", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        task.instance_id = "stale-instance".into();
        assert!(store.retire_verified_shared_workspace(&task).await.is_err());
        assert!(store
            .workspace_retirement_receipt(&task.id, &task.instance_id)
            .await
            .unwrap()
            .is_none());
        assert!(store.find_workspace(&task.id).await.unwrap().is_some());
    }
}
