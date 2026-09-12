use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::{RuntimeStore, WorkflowWorkspaceIdentity};
use crate::git::WorkflowCleanupGitPreview;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupItem {
    pub identity: WorkflowWorkspaceIdentity,
    pub git: WorkflowCleanupGitPreview,
    pub remove_branch: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupPreview {
    pub id: String,
    pub run_id: String,
    pub digest: String,
    pub expires_at: i64,
    pub items: Vec<WorkflowCleanupItem>,
}

impl RuntimeStore {
    pub(super) async fn migrate_workflow_cleanup(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("CREATE TABLE IF NOT EXISTS workflowCleanup (
            id TEXT PRIMARY KEY,run_id TEXT NOT NULL,digest TEXT NOT NULL,document TEXT NOT NULL,
            expires_at INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('preview','applying','retired','attention')),
            error TEXT)").execute(&mut *tx).await?;
        sqlx::query(
            "CREATE INDEX IF NOT EXISTS workflowCleanupRecovery ON workflowCleanup(state,id)",
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query("CREATE TABLE IF NOT EXISTS workflowCleanupResources (
            workspace_id TEXT PRIMARY KEY REFERENCES workflowWorkspaces(id),
            cleanup_id TEXT NOT NULL REFERENCES workflowCleanup(id),retired INTEGER NOT NULL DEFAULT 0)")
            .execute(&mut *tx).await?;
        sqlx::query("DROP TRIGGER IF EXISTS workflowLaunchTabRetained")
            .execute(&mut *tx)
            .await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowCleanupTabInsert BEFORE INSERT ON workspaceTabs
            WHEN EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=0)
            BEGIN SELECT RAISE(ABORT, 'workspace is reserved for reviewed cleanup'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowCleanupTabMove BEFORE UPDATE OF workspaceId ON workspaceTabs
            WHEN OLD.workspaceId IS NOT NEW.workspaceId
              AND EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=0)
            BEGIN SELECT RAISE(ABORT, 'workspace is reserved for reviewed cleanup'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER workflowLaunchTabRetained BEFORE DELETE ON workspaceTabs
            WHEN EXISTS(SELECT 1 FROM workflowLaunches l WHERE l.terminal_handle=OLD.id)
              AND NOT EXISTS(SELECT 1 FROM workflowCleanupResources r WHERE r.workspace_id=OLD.workspaceId AND r.retired=1)
            BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowRetiredWorkspaceInsert BEFORE INSERT ON workspaces
            WHEN EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.id AND retired=1)
            BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot be recreated'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowRetiredWorkspaceTabInsert BEFORE INSERT ON workspaceTabs
            WHEN EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=1)
            BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot receive tabs'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowRetiredWorkspaceUpdate BEFORE UPDATE OF id ON workspaces
            WHEN EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.id AND retired=1)
            BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot be recreated'); END")
            .execute(&mut *tx).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowRetiredWorkspaceTabUpdate BEFORE UPDATE OF workspaceId ON workspaceTabs
            WHEN EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=1)
            BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot receive tabs'); END")
            .execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }

    /// Called after host-side Git inspection. Published previews are immutable;
    /// only the trusted host may later claim one after its process/Git checks.
    pub async fn publish_workflow_cleanup_preview(
        &self,
        id: &str,
        run: &str,
        items: Vec<WorkflowCleanupItem>,
    ) -> Result<WorkflowCleanupPreview> {
        uuid::Uuid::parse_str(id)?;
        super::workflow_plan::workflow_text(run, 160)?;
        if items.is_empty() || items.len() > 25 {
            bail!("select between one and 25 workflow resources");
        }
        let mut ids = std::collections::BTreeSet::new();
        for item in &items {
            if item.identity.run_id != run || !ids.insert(&item.identity.workspace.id) {
                bail!("cleanup selection contains duplicate or foreign resources");
            }
        }
        let digest = super::workflow_plan::workflow_digest(&(run, &items))?;
        let preview = WorkflowCleanupPreview {
            id: id.into(),
            run_id: run.into(),
            digest,
            expires_at: chrono::Utc::now().timestamp() + 300,
            items,
        };
        let document = serde_json::to_value(&preview)?;
        super::orchestration_contract_schema::bounded_json(
            &document,
            super::WORKFLOW_PLAN_MAX_BYTES,
        )?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query("SELECT digest,document FROM workflowCleanup WHERE id=?")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?
        {
            if row.try_get::<String, _>("digest")? != preview.digest {
                bail!("cleanup preview id already has different contents");
            }
            return Ok(serde_json::from_str(
                &row.try_get::<String, _>("document")?,
            )?);
        }
        require_cleanup_quiescent(&mut tx, &preview).await?;
        sqlx::query("INSERT INTO workflowCleanup(id,run_id,digest,document,expires_at,state) VALUES(?,?,?,?,?,'preview')")
            .bind(id).bind(run).bind(&preview.digest).bind(serde_json::to_string(&preview)?).bind(preview.expires_at).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(preview)
    }

    pub async fn workflow_cleanup_preview(&self, id: &str) -> Result<WorkflowCleanupPreview> {
        let document: String =
            sqlx::query_scalar("SELECT document FROM workflowCleanup WHERE id=?")
                .bind(id)
                .fetch_one(self.pool())
                .await?;
        Ok(serde_json::from_str(&document)?)
    }
}

pub(super) async fn require_cleanup_quiescent(
    tx: &mut Transaction<'_, Sqlite>,
    preview: &WorkflowCleanupPreview,
) -> Result<()> {
    let closed: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowRuns WHERE run_id=? AND status IN ('completed','cancelled'))")
        .bind(&preview.run_id).fetch_one(&mut **tx).await?;
    if !closed {
        bail!("finish or cancel the workflow before cleaning its resources");
    }
    let pending: bool = sqlx::query_scalar("SELECT EXISTS(
        SELECT 1 FROM workflowIntegrations WHERE run_id=? AND state IN ('pending','prepared','attention')
        UNION ALL SELECT 1 FROM workflowCancellationTargets WHERE run_id=? AND state<>'settled'
        UNION ALL SELECT 1 FROM orchestrationTasks WHERE run_id=? AND status IN ('dispatched','stalled'))")
        .bind(&preview.run_id).bind(&preview.run_id).bind(&preview.run_id).fetch_one(&mut **tx).await?;
    if pending {
        bail!("reconcile active workflow operations before cleanup");
    }
    let ids = preview
        .items
        .iter()
        .map(|item| &item.identity.workspace.id)
        .collect::<Vec<_>>();
    let rows = sqlx::query("SELECT id,identity,phase FROM workflowWorkspaces WHERE run_id=? AND id IN (SELECT value FROM json_each(?)) LIMIT 26")
        .bind(&preview.run_id).bind(serde_json::to_string(&ids)?).fetch_all(&mut **tx).await?;
    if rows.len() != preview.items.len() {
        bail!("cleanup resources no longer belong to this run");
    }
    for row in rows {
        let id: String = row.try_get("id")?;
        let item = preview
            .items
            .iter()
            .find(|item| item.identity.workspace.id == id)
            .expect("selected resource");
        let recorded: WorkflowWorkspaceIdentity =
            serde_json::from_str(&row.try_get::<String, _>("identity")?)?;
        if serde_json::to_value(recorded)? != serde_json::to_value(&item.identity)? {
            bail!("workflow cleanup resource identity changed");
        }
        if !matches!(
            row.try_get::<String, _>("phase")?.as_str(),
            "ready" | "attention"
        ) {
            bail!("workflow resource setup must settle before cleanup");
        }
    }
    Ok(())
}
