use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use super::{
    ProjectConfig, RuntimeStore, WorkspaceKind, WorkspaceRelocationPhase, WorktreeSetupReport,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RelocationSetupReceipt {
    pub relocation_id: String,
    pub config: ProjectConfig,
    pub attempt_id: Option<String>,
    pub report: Option<WorktreeSetupReport>,
}

impl RuntimeStore {
    pub(super) async fn migrate_relocation_setup_receipts(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS relocationSetupReceipts (relocationId TEXT PRIMARY KEY, configJson TEXT NOT NULL, attemptId TEXT, reportJson TEXT)")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainSetupWorkspace BEFORE DELETE ON workspaces WHEN EXISTS (SELECT 1 FROM relocationSetupReceipts s JOIN workspaceRelocations r ON r.id = s.relocationId WHERE r.workspaceId = OLD.id AND s.attemptId IS NOT NULL AND s.reportJson IS NULL) BEGIN SELECT RAISE(ABORT, 'Workspace setup has an unconfirmed result; recover it before removal'); END")
            .execute(self.pool()).await?;
        sqlx::query("CREATE TRIGGER IF NOT EXISTS retainSetupWorkspaceLocation BEFORE UPDATE ON workspaces WHEN (NEW.instanceId IS NOT OLD.instanceId OR NEW.path IS NOT OLD.path OR NEW.hostId IS NOT OLD.hostId OR NEW.kind IS NOT OLD.kind OR NEW.status IS NOT OLD.status OR NEW.projectId IS NOT OLD.projectId) AND EXISTS (SELECT 1 FROM relocationSetupReceipts s JOIN workspaceRelocations r ON r.id = s.relocationId WHERE r.workspaceId = OLD.id AND s.attemptId IS NOT NULL AND s.reportJson IS NULL) BEGIN SELECT RAISE(ABORT, 'Workspace setup has an unconfirmed result; recover it before changing its location'); END")
            .execute(self.pool()).await?;
        Ok(())
    }

    pub async fn validate_workspace_setup_idle(&self, workspace_id: &str) -> Result<()> {
        let pending: Option<String> = sqlx::query_scalar("SELECT s.relocationId FROM relocationSetupReceipts s JOIN workspaceRelocations r ON r.id = s.relocationId WHERE r.workspaceId = ? AND s.attemptId IS NOT NULL AND s.reportJson IS NULL LIMIT 1")
            .bind(workspace_id).fetch_optional(self.pool()).await?;
        if let Some(id) = pending {
            bail!("Setup for relocation {id} is running or has an unconfirmed result; recover it before moving or removing this task");
        }
        Ok(())
    }

    /// Pin the recipe before relocation mutates the source checkout. A retry
    /// keeps the original recipe even if project configuration has changed.
    pub async fn prepare_relocation_setup(
        &self,
        relocation_id: &str,
        config: &ProjectConfig,
    ) -> Result<RelocationSetupReceipt> {
        let journal = self
            .find_workspace_relocation(relocation_id)
            .await?
            .ok_or_else(|| anyhow!("Relocation not found: {relocation_id}"))?;
        if journal.destination.kind != WorkspaceKind::Linked {
            bail!("Hand On does not create a worktree and must not run setup");
        }
        sqlx::query("INSERT INTO relocationSetupReceipts(relocationId, configJson) VALUES (?, ?) ON CONFLICT(relocationId) DO NOTHING")
            .bind(relocation_id).bind(serde_json::to_string(config)?).execute(self.pool()).await?;
        self.find_relocation_setup(relocation_id)
            .await?
            .ok_or_else(|| anyhow!("Setup receipt disappeared"))
    }

    pub async fn find_relocation_setup(
        &self,
        relocation_id: &str,
    ) -> Result<Option<RelocationSetupReceipt>> {
        let row: Option<(String, Option<String>, Option<String>)> = sqlx::query_as("SELECT configJson, attemptId, reportJson FROM relocationSetupReceipts WHERE relocationId = ?")
            .bind(relocation_id).fetch_optional(self.pool()).await?;
        row.map(|(config, attempt_id, report)| {
            Ok(RelocationSetupReceipt {
                relocation_id: relocation_id.to_owned(),
                config: serde_json::from_str(&config)?,
                attempt_id,
                report: report
                    .map(|report| serde_json::from_str(&report))
                    .transpose()?,
            })
        })
        .transpose()
    }

    /// A claimed attempt is never automatically reclaimed after a restart: its
    /// command may have performed effects before the host lost the result.
    pub async fn claim_relocation_setup(
        &self,
        receipt: &RelocationSetupReceipt,
    ) -> Result<RelocationSetupReceipt> {
        if receipt.attempt_id.is_some() || receipt.report.is_some() {
            bail!("Setup was already attempted; inspect its recorded outcome before requesting an explicit retry");
        }
        let journal = self
            .find_workspace_relocation(&receipt.relocation_id)
            .await?
            .ok_or_else(|| anyhow!("Relocation not found"))?;
        if journal.phase != WorkspaceRelocationPhase::Completed {
            bail!("Complete relocation before running its setup");
        }
        let attempt_id = uuid::Uuid::new_v4().to_string();
        let mut tx = self.pool().begin().await?;
        let latest: Option<String> = sqlx::query_scalar(
            "SELECT id FROM workspaceRelocations WHERE workspaceId = ? ORDER BY rowid DESC LIMIT 1",
        )
        .bind(&journal.destination.id)
        .fetch_optional(&mut *tx)
        .await?;
        if latest.as_deref() != Some(receipt.relocation_id.as_str()) {
            bail!("A newer relocation supersedes this setup recipe; no commands were started");
        }
        let current: Option<(String, String, String)> =
            sqlx::query_as("SELECT instanceId, hostId, path FROM workspaces WHERE id = ?")
                .bind(&journal.destination.id)
                .fetch_optional(&mut *tx)
                .await?;
        if current
            != Some((
                journal.destination.instance_id,
                journal.destination.host_id,
                journal.destination.path,
            ))
        {
            bail!(
                "Workspace moved or was retired after setup preparation; no commands were started"
            );
        }
        let changed = sqlx::query("UPDATE relocationSetupReceipts SET attemptId = ? WHERE relocationId = ? AND attemptId IS NULL AND reportJson IS NULL AND configJson = ?")
            .bind(&attempt_id).bind(&receipt.relocation_id).bind(serde_json::to_string(&receipt.config)?)
            .execute(&mut *tx).await?.rows_affected();
        if changed != 1 {
            bail!("Setup was claimed by another request; refresh its receipt instead of repeating commands");
        }
        tx.commit().await?;
        Ok(RelocationSetupReceipt {
            attempt_id: Some(attempt_id),
            ..receipt.clone()
        })
    }

    pub async fn finish_relocation_setup(
        &self,
        receipt: &RelocationSetupReceipt,
        report: &WorktreeSetupReport,
    ) -> Result<WorktreeSetupReport> {
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup has no claimed attempt"))?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let cancelled: i64 = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM relocationSetupCancellations WHERE relocationId = ? AND attemptId = ?)")
            .bind(&receipt.relocation_id).bind(attempt).fetch_one(&mut *tx).await?;
        let mut report = report.clone();
        if cancelled != 0
            && !report
                .steps
                .iter()
                .any(|step| step.label == "Setup Cancellation" && !step.succeeded)
        {
            report.steps.push(super::WorktreeSetupStepReport {
                kind: super::WorktreeSetupStepKind::Config,
                label: "Setup Cancellation".into(),
                succeeded: false,
                message: Some(
                    "Cancellation was requested before the setup result was recorded".into(),
                ),
                exit_code: None,
                stdout_tail: None,
                stderr_tail: None,
            });
        }
        let changed = sqlx::query("UPDATE relocationSetupReceipts SET reportJson = ? WHERE relocationId = ? AND attemptId = ? AND reportJson IS NULL AND NOT EXISTS(SELECT 1 FROM relocationSetupProcesses p WHERE p.relocationId = relocationSetupReceipts.relocationId AND p.attemptId = relocationSetupReceipts.attemptId AND json_extract(p.dataJson, '$.phase') IN ('starting', 'started', 'rootExitedOutputPending')) AND NOT EXISTS(SELECT 1 FROM relocationSetupDescendants d WHERE d.relocationId = relocationSetupReceipts.relocationId AND d.attemptId = relocationSetupReceipts.attemptId AND json_extract(d.dataJson, '$.exitVerified') = 0)")
            .bind(serde_json::to_string(&report)?).bind(&receipt.relocation_id).bind(attempt)
            .execute(&mut *tx).await?.rows_affected();
        if changed != 1 {
            bail!("Setup receipt changed or process/output closure remains unconfirmed; the result was not recorded");
        }
        tx.commit().await?;
        Ok(report)
    }
}
