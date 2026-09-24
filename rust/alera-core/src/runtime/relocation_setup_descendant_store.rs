use super::{RelocationSetupProcess, RelocationSetupReceipt, RuntimeStore, SetupRootProcessPhase};
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelocationSetupDescendant {
    pub command_index: u32,
    pub pid: u32,
    pub start_marker: u64,
    pub platform: String,
    pub boot_id: Option<String>,
    pub exit_verified: bool,
}

impl RuntimeStore {
    pub(super) async fn migrate_setup_descendants(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS relocationSetupDescendants (relocationId TEXT NOT NULL, attemptId TEXT NOT NULL, commandIndex INTEGER NOT NULL, pid INTEGER NOT NULL, startMarker TEXT NOT NULL, dataJson TEXT NOT NULL, PRIMARY KEY(relocationId, attemptId, commandIndex, pid, startMarker))")
            .execute(self.pool()).await?;
        Ok(())
    }

    pub async fn record_setup_descendant(
        &self,
        receipt: &RelocationSetupReceipt,
        root: &RelocationSetupProcess,
        pid: u32,
        start_marker: u64,
    ) -> Result<RelocationSetupDescendant> {
        if root.phase != SetupRootProcessPhase::Started
            || pid == 0
            || root.pid == Some(pid)
            || start_marker == 0
        {
            bail!("A setup descendant requires a live recorded root and its own process identity");
        }
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup attempt missing"))?;
        let descendant = RelocationSetupDescendant {
            command_index: root.command_index,
            pid,
            start_marker,
            platform: root.platform.clone(),
            boot_id: root.boot_id.clone(),
            exit_verified: false,
        };
        let mut tx = self.pool().begin_with("BEGIN IMMEDIATE").await?;
        let active: i64 = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM relocationSetupProcesses p JOIN relocationSetupReceipts s ON p.relocationId = s.relocationId AND p.attemptId = s.attemptId WHERE p.relocationId = ? AND p.attemptId = ? AND p.commandIndex = ? AND p.dataJson = ? AND s.reportJson IS NULL)")
            .bind(&receipt.relocation_id).bind(attempt).bind(root.command_index).bind(serde_json::to_string(root)?).fetch_one(&mut *tx).await?;
        if active == 0 {
            bail!("Setup root record changed; descendant ownership was not saved");
        }
        sqlx::query("INSERT INTO relocationSetupDescendants(relocationId, attemptId, commandIndex, pid, startMarker, dataJson) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING")
            .bind(&receipt.relocation_id).bind(attempt).bind(root.command_index).bind(pid).bind(start_marker.to_string()).bind(serde_json::to_string(&descendant)?).execute(&mut *tx).await?;
        let data: String = sqlx::query_scalar("SELECT dataJson FROM relocationSetupDescendants WHERE relocationId = ? AND attemptId = ? AND commandIndex = ? AND pid = ? AND startMarker = ?")
            .bind(&receipt.relocation_id).bind(attempt).bind(root.command_index).bind(pid).bind(start_marker.to_string()).fetch_one(&mut *tx).await?;
        tx.commit().await?;
        Ok(serde_json::from_str(&data)?)
    }

    pub async fn verify_setup_descendant_exit(
        &self,
        receipt: &RelocationSetupReceipt,
        descendant: &RelocationSetupDescendant,
    ) -> Result<()> {
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup attempt missing"))?;
        let changed = sqlx::query("UPDATE relocationSetupDescendants SET dataJson = ? WHERE relocationId = ? AND attemptId = ? AND commandIndex = ? AND pid = ? AND startMarker = ? AND dataJson = ?")
            .bind(serde_json::to_string(&RelocationSetupDescendant { exit_verified: true, ..descendant.clone() })?).bind(&receipt.relocation_id).bind(attempt).bind(descendant.command_index).bind(descendant.pid).bind(descendant.start_marker.to_string()).bind(serde_json::to_string(descendant)?).execute(self.pool()).await?.rows_affected();
        if changed != 1 {
            bail!("Setup descendant changed; stale exit proof was not saved");
        }
        Ok(())
    }

    pub async fn list_setup_descendants(
        &self,
        receipt: &RelocationSetupReceipt,
    ) -> Result<Vec<RelocationSetupDescendant>> {
        let Some(attempt) = &receipt.attempt_id else {
            return Ok(Vec::new());
        };
        let rows: Vec<String> = sqlx::query_scalar("SELECT dataJson FROM relocationSetupDescendants WHERE relocationId = ? AND attemptId = ? ORDER BY commandIndex, pid")
            .bind(&receipt.relocation_id).bind(attempt).fetch_all(self.pool()).await?;
        rows.into_iter()
            .map(|data| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }
}
