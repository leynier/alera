use anyhow::{anyhow, bail, Result};

use super::{
    RelocationSetupDescendant, RelocationSetupProcess, RelocationSetupReceipt, RuntimeStore,
    SetupRootProcessPhase, WorktreeSetupReport, WorktreeSetupStepKind, WorktreeSetupStepReport,
};

impl RuntimeStore {
    pub(super) async fn migrate_setup_recovery_evidence(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS relocationSetupRecoveryEvidence (relocationId TEXT NOT NULL, attemptId TEXT NOT NULL, dataJson TEXT NOT NULL, PRIMARY KEY(relocationId, attemptId))")
            .execute(self.pool()).await?;
        Ok(())
    }

    /// The owning runtime must serialize this with setup execution. Boot evidence
    /// comes from that runtime, never from a client's request payload.
    pub async fn recover_interrupted_relocation_setup(
        &self,
        receipt: &RelocationSetupReceipt,
        platform: &str,
        boot_id: Option<&str>,
    ) -> Result<WorktreeSetupReport> {
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup has no attempted execution to recover"))?;
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let current: Option<(Option<String>, Option<String>)> = sqlx::query_as(
            "SELECT attemptId, reportJson FROM relocationSetupReceipts WHERE relocationId = ?",
        )
        .bind(&receipt.relocation_id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some((current_attempt, existing_report)) = current else {
            bail!("Setup receipt no longer exists");
        };
        if current_attempt.as_deref() != Some(attempt) {
            bail!("Setup attempt changed; inspect recovery before trying again");
        }
        if let Some(report) = existing_report {
            return Ok(serde_json::from_str(&report)?);
        }
        let roots: Vec<String> = sqlx::query_scalar("SELECT dataJson FROM relocationSetupProcesses WHERE relocationId = ? AND attemptId = ? ORDER BY commandIndex")
            .bind(&receipt.relocation_id).bind(attempt).fetch_all(&mut *tx).await?;
        let descendants: Vec<String> = sqlx::query_scalar("SELECT dataJson FROM relocationSetupDescendants WHERE relocationId = ? AND attemptId = ? ORDER BY commandIndex, pid")
            .bind(&receipt.relocation_id).bind(attempt).fetch_all(&mut *tx).await?;
        let roots = roots
            .iter()
            .map(|data| serde_json::from_str::<RelocationSetupProcess>(data))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let descendants = descendants
            .iter()
            .map(|data| serde_json::from_str::<RelocationSetupDescendant>(data))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let rebooted = |recorded_platform: &str, recorded_boot: Option<&str>| {
            platform == "linux"
                && recorded_platform == platform
                && matches!((recorded_boot, boot_id), (Some(previous), Some(current)) if previous != current)
        };
        for root in &roots {
            if !matches!(
                root.phase,
                SetupRootProcessPhase::SpawnFailed | SetupRootProcessPhase::RootExited
            ) && !rebooted(&root.platform, root.boot_id.as_deref())
            {
                bail!("Command {} has unverified process or output closure; recovery cannot release this task", root.command_index + 1);
            }
        }
        for descendant in &descendants {
            if !descendant.exit_verified
                && !rebooted(&descendant.platform, descendant.boot_id.as_deref())
            {
                bail!(
                    "Setup descendant {} has unverified closure; recovery cannot release this task",
                    descendant.pid
                );
            }
        }
        let evidence = serde_json::json!({
            "recordedAt": chrono::Utc::now(), "platform": platform, "bootId": boot_id,
            "roots": roots, "descendants": descendants,
        });
        sqlx::query("INSERT INTO relocationSetupRecoveryEvidence(relocationId, attemptId, dataJson) VALUES (?, ?, ?)")
            .bind(&receipt.relocation_id).bind(attempt).bind(serde_json::to_string(&evidence)?).execute(&mut *tx).await?;
        for root in roots {
            if matches!(
                root.phase,
                SetupRootProcessPhase::SpawnFailed | SetupRootProcessPhase::RootExited
            ) {
                continue;
            }
            let recovered = RelocationSetupProcess {
                phase: SetupRootProcessPhase::RootExited,
                ..root
            };
            sqlx::query("UPDATE relocationSetupProcesses SET dataJson = ? WHERE relocationId = ? AND attemptId = ? AND commandIndex = ?")
                .bind(serde_json::to_string(&recovered)?).bind(&receipt.relocation_id).bind(attempt).bind(recovered.command_index).execute(&mut *tx).await?;
        }
        for descendant in descendants {
            if descendant.exit_verified {
                continue;
            }
            let recovered = RelocationSetupDescendant {
                exit_verified: true,
                ..descendant
            };
            sqlx::query("UPDATE relocationSetupDescendants SET dataJson = ? WHERE relocationId = ? AND attemptId = ? AND commandIndex = ? AND pid = ? AND startMarker = ?")
                .bind(serde_json::to_string(&recovered)?).bind(&receipt.relocation_id).bind(attempt).bind(recovered.command_index).bind(recovered.pid).bind(recovered.start_marker.to_string()).execute(&mut *tx).await?;
        }
        let report = WorktreeSetupReport { steps: vec![WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Config,
            label: "Setup Recovery".into(),
            succeeded: false,
            message: Some("The interrupted attempt was closed after verifying process closure. Its command effects and missing output were not reconstructed; no commands were repeated.".into()),
            exit_code: None, stdout_tail: None, stderr_tail: None,
        }] };
        sqlx::query("UPDATE relocationSetupReceipts SET reportJson = ? WHERE relocationId = ? AND attemptId = ?")
            .bind(serde_json::to_string(&report)?).bind(&receipt.relocation_id).bind(attempt).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(report)
    }
}
