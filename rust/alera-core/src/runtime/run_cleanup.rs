use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::{Row, Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
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

pub(super) async fn install_cleanup_schema(conn: &mut sqlx::SqliteConnection) -> Result<()> {
    sqlx::query("CREATE TABLE IF NOT EXISTS runCleanup (
        id TEXT PRIMARY KEY,run_id TEXT NOT NULL,digest TEXT NOT NULL,document TEXT NOT NULL,
        expires_at INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('preview','applying','retired','attention')),
        error TEXT,abandoned INTEGER NOT NULL DEFAULT 0)").execute(&mut *conn).await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS runCleanupRecovery ON runCleanup(state,id)")
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS runCleanupResources (
        workspace_id TEXT PRIMARY KEY REFERENCES runWorkspaces(id),
        cleanup_id TEXT NOT NULL REFERENCES runCleanup(id),retired INTEGER NOT NULL DEFAULT 0)",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS runCleanupRun ON runCleanup(run_id)")
        .execute(&mut *conn)
        .await?;
    sqlx::query("CREATE INDEX IF NOT EXISTS runCleanupRunState ON runCleanup(run_id,state)")
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS runCleanupRetired ON runCleanupResources(cleanup_id,retired)",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("DROP TRIGGER IF EXISTS runLaunchTabRetained")
        .execute(&mut *conn)
        .await?;
    sqlx::query("CREATE TRIGGER IF NOT EXISTS runCleanupTabInsert BEFORE INSERT ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=0)
        BEGIN SELECT RAISE(ABORT, 'workspace is reserved for reviewed cleanup'); END")
        .execute(&mut *conn).await?;
    sqlx::query("CREATE TRIGGER IF NOT EXISTS runCleanupTabMove BEFORE UPDATE OF workspaceId ON workspaceTabs
        WHEN OLD.workspaceId IS NOT NEW.workspaceId
          AND EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=0)
        BEGIN SELECT RAISE(ABORT, 'workspace is reserved for reviewed cleanup'); END")
        .execute(&mut *conn).await?;
    sqlx::query("CREATE TRIGGER runLaunchTabRetained BEFORE DELETE ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runLaunches l WHERE l.terminal_handle=OLD.id)
          AND NOT EXISTS(SELECT 1 FROM runCleanupResources r WHERE r.workspace_id=OLD.workspaceId AND r.retired=1)
        BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END")
        .execute(&mut *conn).await?;
    sqlx::query(
        "CREATE TRIGGER IF NOT EXISTS runRetiredWorkspaceInsert BEFORE INSERT ON workspaces
        WHEN EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.id AND retired=1)
        BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot be recreated'); END",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("CREATE TRIGGER IF NOT EXISTS runRetiredWorkspaceTabInsert BEFORE INSERT ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=1)
        BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot receive tabs'); END")
        .execute(&mut *conn).await?;
    sqlx::query(
        "CREATE TRIGGER IF NOT EXISTS runRetiredWorkspaceUpdate BEFORE UPDATE OF id ON workspaces
        WHEN EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.id AND retired=1)
        BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot be recreated'); END",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("CREATE TRIGGER IF NOT EXISTS runRetiredWorkspaceTabUpdate BEFORE UPDATE OF workspaceId ON workspaceTabs
        WHEN EXISTS(SELECT 1 FROM runCleanupResources WHERE workspace_id=NEW.workspaceId AND retired=1)
        BEGIN SELECT RAISE(ABORT, 'retired workflow workspace cannot receive tabs'); END")
        .execute(&mut *conn).await?;
    sqlx::query(
        "CREATE INDEX IF NOT EXISTS runCleanupRunDisposition ON runCleanup(run_id,abandoned,state)",
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}

impl RuntimeStore {
    /// Called after host-side Git inspection. Published previews are immutable;
    /// only the trusted host may later claim one after its process/Git checks.
    pub async fn publish_workflow_cleanup_preview(
        &self,
        id: &str,
        run: &str,
        items: Vec<WorkflowCleanupItem>,
    ) -> Result<WorkflowCleanupPreview> {
        uuid::Uuid::parse_str(id)?;
        super::run_plan::workflow_text(run, 160)?;
        if items.is_empty() || items.len() > 25 {
            bail!("select between one and 25 workflow resources");
        }
        let mut ids = std::collections::BTreeSet::new();
        for item in &items {
            if item.identity.run_id != run || !ids.insert(&item.identity.workspace.id) {
                bail!("cleanup selection contains duplicate or foreign resources");
            }
        }
        let digest = super::run_plan::workflow_digest(&(run, &items))?;
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
        if let Some(row) = sqlx::query("SELECT digest,document FROM runCleanup WHERE id=?")
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
        sqlx::query("INSERT INTO runCleanup(id,run_id,digest,document,expires_at,state) VALUES(?,?,?,?,?,'preview')")
            .bind(id).bind(run).bind(&preview.digest).bind(serde_json::to_string(&preview)?).bind(preview.expires_at).execute(&mut *tx).await?;
        record_cleanup_event(
            &mut tx,
            run,
            id,
            RunEventKind::CleanupPrepared,
            preview.items.len(),
        )
        .await?;
        tx.commit().await?;
        Ok(preview)
    }

    pub async fn workflow_cleanup_preview(&self, id: &str) -> Result<WorkflowCleanupPreview> {
        let document: String = sqlx::query_scalar("SELECT document FROM runCleanup WHERE id=?")
            .bind(id)
            .fetch_one(self.pool())
            .await?;
        Ok(serde_json::from_str(&document)?)
    }
}

/// One timeline entry per cleanup step, naming how many resources it covers.
pub(super) async fn record_cleanup_event(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    cleanup_id: &str,
    kind: RunEventKind,
    resources: usize,
) -> Result<()> {
    let summary = match resources {
        1 => "1 resource".to_string(),
        count => format!("{count} resources"),
    };
    let mut event = NewRunEvent::new(run_id, kind);
    event.summary = &summary;
    event.payload = Some(serde_json::json!({
        "cleanupId": cleanup_id,
        "resourceCount": resources,
    }));
    record_run_event(tx, &event).await?;
    Ok(())
}

pub(super) async fn require_cleanup_quiescent(
    tx: &mut Transaction<'_, Sqlite>,
    preview: &WorkflowCleanupPreview,
) -> Result<()> {
    let closed: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns WHERE id=? AND isolation='isolated'
        AND status IN ('completed','failed','cancelled') AND completed_at IS NOT NULL)")
        .bind(&preview.run_id).fetch_one(&mut **tx).await?;
    if !closed {
        bail!("finish or cancel the run before cleaning its resources");
    }
    let pending: bool = sqlx::query_scalar("SELECT EXISTS(
        SELECT 1 FROM runIntegrations WHERE run_id=? AND cancelled=0 AND state IN ('pending','prepared','attention')
        UNION ALL SELECT 1 FROM runCancellationTargets WHERE run_id=? AND state<>'settled'
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
    let rows = sqlx::query("SELECT id,identity,phase FROM runWorkspaces WHERE run_id=? AND id IN (SELECT value FROM json_each(?)) LIMIT 26")
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
