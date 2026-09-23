use anyhow::{bail, Result};

use super::RuntimeStore;

impl RuntimeStore {
    pub(super) async fn migrate_workspace_terminal_launches(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        for statement in [
            "CREATE TABLE IF NOT EXISTS workspaceTerminalLaunchState (workspaceId TEXT NOT NULL, instanceId TEXT NOT NULL, attempted INTEGER NOT NULL CHECK(attempted IN (0, 1)), PRIMARY KEY(workspaceId, instanceId))",
            "CREATE TABLE IF NOT EXISTS unregisteredTerminalWorkspaceIds (workspaceId TEXT PRIMARY KEY)",
            "CREATE TABLE IF NOT EXISTS terminalLaunchAttempts (workspaceId TEXT NOT NULL, instanceId TEXT NOT NULL, tabId TEXT NOT NULL, sessionId TEXT NOT NULL, attempted INTEGER NOT NULL CHECK(attempted IN (0, 1)), PRIMARY KEY(workspaceId, instanceId, tabId, sessionId))",
            "INSERT INTO terminalLaunchAttempts SELECT w.id, w.instanceId, t.id, json_extract(t.payloadJson, '$.terminalSessionId'), 1 FROM workspaceTabs t JOIN workspaces w ON w.id = t.workspaceId WHERE t.kind = 'terminal' AND json_extract(t.payloadJson, '$.terminalSessionId') IS NOT NULL ON CONFLICT DO NOTHING",
            "CREATE TRIGGER IF NOT EXISTS recordNewTerminalLaunchState AFTER INSERT ON workspaceTabs WHEN NEW.kind = 'terminal' AND json_extract(NEW.payloadJson, '$.terminalSessionId') IS NOT NULL BEGIN INSERT INTO terminalLaunchAttempts SELECT w.id, w.instanceId, NEW.id, json_extract(NEW.payloadJson, '$.terminalSessionId'), EXISTS (SELECT 1 FROM unregisteredTerminalWorkspaceIds WHERE workspaceId = w.id) FROM workspaces w WHERE w.id = NEW.workspaceId ON CONFLICT DO NOTHING; END",
            // Existing tasks have no trustworthy evidence that a terminal never started.
            "INSERT INTO workspaceTerminalLaunchState SELECT id, instanceId, 1 FROM workspaces WHERE true ON CONFLICT DO NOTHING",
            "CREATE TRIGGER IF NOT EXISTS recordNewWorkspaceTerminalState AFTER INSERT ON workspaces BEGIN INSERT INTO workspaceTerminalLaunchState (workspaceId, instanceId, attempted) VALUES (NEW.id, NEW.instanceId, EXISTS (SELECT 1 FROM unregisteredTerminalWorkspaceIds WHERE workspaceId = NEW.id)) ON CONFLICT DO NOTHING; END",
        ] {
            sqlx::query(statement).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn record_workspace_terminal_launch(&self, workspace_id: &str) -> Result<()> {
        self.record_terminal_launch(workspace_id, None).await
    }

    pub async fn record_workspace_tab_terminal_launch(
        &self,
        workspace_id: &str,
        tab_id: &str,
        session_id: &str,
    ) -> Result<()> {
        self.record_terminal_launch(workspace_id, Some((tab_id, session_id)))
            .await
    }

    pub async fn terminal_launch_attempted(
        &self,
        workspace_id: &str,
        instance_id: &str,
        tab_id: &str,
        session_id: &str,
    ) -> Result<Option<bool>> {
        Ok(sqlx::query_scalar("SELECT attempted FROM terminalLaunchAttempts WHERE workspaceId = ? AND instanceId = ? AND tabId = ? AND sessionId = ?")
            .bind(workspace_id).bind(instance_id).bind(tab_id).bind(session_id)
            .fetch_optional(self.pool()).await?)
    }

    async fn record_terminal_launch(
        &self,
        workspace_id: &str,
        terminal: Option<(&str, &str)>,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        super::workspace_checkout_relocation_barrier::require_checkout_process_launch_available(
            &mut tx,
            workspace_id,
        )
        .await?;
        let instance: Option<String> =
            sqlx::query_scalar("SELECT instanceId FROM workspaces WHERE id = ?")
                .bind(workspace_id)
                .fetch_optional(&mut *tx)
                .await?;
        if let Some(instance) = instance {
            if let Some((tab_id, session_id)) = terminal {
                let closed: i64 = sqlx::query_scalar("SELECT count(*) FROM terminalLifecycleOperations WHERE workspaceId = ? AND tabId = ? AND sessionId = ? AND closed = 1 AND json_extract(recordJson, '$.workspace.instanceId') = ? AND json_extract(recordJson, '$.action') = 'close'")
                    .bind(workspace_id).bind(tab_id).bind(session_id).bind(&instance)
                    .fetch_one(&mut *tx).await?;
                if closed != 0 {
                    bail!("This terminal was closed; create a new terminal tab before launching");
                }
                sqlx::query("INSERT INTO terminalLaunchAttempts (workspaceId, instanceId, tabId, sessionId, attempted) VALUES (?, ?, ?, ?, 1) ON CONFLICT(workspaceId, instanceId, tabId, sessionId) DO UPDATE SET attempted = 1")
                    .bind(workspace_id).bind(&instance).bind(tab_id).bind(session_id)
                    .execute(&mut *tx).await?;
            }
            let updated = sqlx::query("INSERT INTO workspaceTerminalLaunchState (workspaceId, instanceId, attempted) VALUES (?, ?, 1) ON CONFLICT(workspaceId, instanceId) DO UPDATE SET attempted = 1")
                .bind(workspace_id).bind(instance).execute(&mut *tx).await?;
            if updated.rows_affected() != 1 {
                bail!("Workspace terminal launch ownership could not be recorded");
            }
        } else {
            let retired: i64 = sqlx::query_scalar(
                "SELECT count(*) FROM workspaceRetirements WHERE workspaceId = ?",
            )
            .bind(workspace_id)
            .fetch_one(&mut *tx)
            .await?;
            if retired != 0 {
                bail!("The workspace was retired; no terminal was started");
            }
            sqlx::query("INSERT INTO unregisteredTerminalWorkspaceIds (workspaceId) VALUES (?) ON CONFLICT DO NOTHING")
                .bind(workspace_id).execute(&mut *tx).await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// Only `Some(false)` proves no terminal launch attempt; migrated tasks are conservatively true.
    pub async fn workspace_terminal_launch_attempted(
        &self,
        workspace_id: &str,
        instance_id: &str,
    ) -> Result<Option<bool>> {
        Ok(sqlx::query_scalar("SELECT attempted FROM workspaceTerminalLaunchState WHERE workspaceId = ? AND instanceId = ?")
            .bind(workspace_id).bind(instance_id).fetch_optional(self.pool()).await?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::checkout_store_tests::{fixture, workspace};
    use crate::runtime::WorkspaceKind;

    #[tokio::test]
    async fn terminal_attempts_distinguish_tabs_and_preserve_evidence_across_restart() {
        use crate::runtime::WorkspaceTabRecord;
        use serde_json::json;
        let (directory, store, _) = fixture().await;
        let task = workspace("task", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        let tab = |id: &str| WorkspaceTabRecord {
            id: id.into(),
            workspace_id: task.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
            payload: json!({"terminalSessionId": id}),
        };
        for id in ["started", "idle"] {
            store.insert_workspace_tab(tab(id)).await.unwrap();
        }
        store
            .record_workspace_tab_terminal_launch(&task.id, "started", "started")
            .await
            .unwrap();
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        for (id, expected) in [
            ("started", Some(true)),
            ("idle", Some(false)),
            ("unknown", None),
        ] {
            assert_eq!(
                reopened
                    .terminal_launch_attempted(&task.id, &task.instance_id, id, id)
                    .await
                    .unwrap(),
                expected
            );
        }
        reopened.remove_workspace_tab("started").await.unwrap();
        reopened.insert_workspace_tab(tab("started")).await.unwrap();
        assert_eq!(
            reopened
                .terminal_launch_attempted(&task.id, &task.instance_id, "started", "started")
                .await
                .unwrap(),
            Some(true)
        );
        assert_eq!(
            reopened
                .terminal_launch_attempted(&task.id, "another-instance", "idle", "idle")
                .await
                .unwrap(),
            None
        );
        // Simulate upgrading a database whose tabs predate per-terminal evidence.
        sqlx::query("DROP TRIGGER recordNewTerminalLaunchState")
            .execute(reopened.pool())
            .await
            .unwrap();
        sqlx::query("DROP TABLE terminalLaunchAttempts")
            .execute(reopened.pool())
            .await
            .unwrap();
        let migrated = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            migrated
                .terminal_launch_attempted(&task.id, &task.instance_id, "idle", "idle")
                .await
                .unwrap(),
            Some(true)
        );
    }

    #[tokio::test]
    async fn launch_intent_survives_reopen_and_cannot_be_reset_by_upsert() {
        let (directory, store, _) = fixture().await;
        let task = workspace("task", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        assert_eq!(
            store
                .workspace_terminal_launch_attempted(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(false)
        );
        let idle_reopened = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            idle_reopened
                .workspace_terminal_launch_attempted(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(false)
        );
        store
            .record_workspace_terminal_launch(&task.id)
            .await
            .unwrap();
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        reopened.upsert_workspace(task.clone()).await.unwrap();
        assert_eq!(
            reopened
                .workspace_terminal_launch_attempted(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(true)
        );
        reopened
            .retire_verified_shared_workspace(&task)
            .await
            .unwrap();
        assert!(reopened
            .record_workspace_terminal_launch(&task.id)
            .await
            .is_err());
    }

    #[tokio::test]
    async fn migrated_tasks_do_not_gain_never_started_evidence() {
        let (directory, store, _) = fixture().await;
        let task = workspace("legacy", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        for statement in [
            "DROP TRIGGER recordNewWorkspaceTerminalState",
            "DROP TABLE workspaceTerminalLaunchState",
            "DROP TABLE unregisteredTerminalWorkspaceIds",
        ] {
            sqlx::query(statement).execute(store.pool()).await.unwrap();
        }
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            reopened
                .workspace_terminal_launch_attempted(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(true)
        );
    }

    #[tokio::test]
    async fn previously_unregistered_terminal_is_not_treated_as_never_started() {
        let (_directory, store, _) = fixture().await;
        store
            .record_workspace_terminal_launch("task")
            .await
            .unwrap();
        let task = workspace("task", "local", "/repo", WorkspaceKind::Main);
        store.insert_workspace(task.clone()).await.unwrap();
        store
            .insert_workspace_tab(crate::runtime::WorkspaceTabRecord {
                id: "tab".into(),
                workspace_id: task.id.clone(),
                kind: "terminal".into(),
                title: "Terminal".into(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
                payload: serde_json::json!({"terminalSessionId":"session"}),
            })
            .await
            .unwrap();
        assert_eq!(
            store
                .terminal_launch_attempted(&task.id, &task.instance_id, "tab", "session")
                .await
                .unwrap(),
            Some(true)
        );
        assert_eq!(
            store
                .workspace_terminal_launch_attempted(&task.id, &task.instance_id)
                .await
                .unwrap(),
            Some(true)
        );
    }
}
