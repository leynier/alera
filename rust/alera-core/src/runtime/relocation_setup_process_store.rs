use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};

use super::{RelocationSetupReceipt, RuntimeStore};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelocationSetupProcess {
    pub command_index: u32,
    pub platform: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub boot_id: Option<String>,
    pub pid: Option<u32>,
    pub start_marker: Option<u64>,
    pub phase: SetupRootProcessPhase,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SetupRootProcessPhase {
    Starting,
    Started,
    SpawnFailed,
    RootExitedOutputPending,
    RootExited,
}

impl RuntimeStore {
    pub(super) async fn migrate_relocation_setup_processes(&self) -> Result<()> {
        sqlx::query("CREATE TABLE IF NOT EXISTS relocationSetupProcesses (relocationId TEXT NOT NULL, attemptId TEXT NOT NULL, commandIndex INTEGER NOT NULL, dataJson TEXT NOT NULL, PRIMARY KEY(relocationId, attemptId, commandIndex))")
            .execute(self.pool()).await?;
        Ok(())
    }

    pub async fn begin_setup_root_process(
        &self,
        receipt: &RelocationSetupReceipt,
        command_index: u32,
        platform: &str,
        boot_id: Option<&str>,
    ) -> Result<RelocationSetupProcess> {
        if platform == "linux" && boot_id.is_none() {
            bail!("Linux setup processes require a recorded boot identity before spawning");
        }
        let process = RelocationSetupProcess {
            command_index,
            platform: platform.into(),
            boot_id: boot_id.map(str::to_owned),
            pid: None,
            start_marker: None,
            phase: SetupRootProcessPhase::Starting,
        };
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup has no claimed attempt"))?;
        let changed = sqlx::query("INSERT INTO relocationSetupProcesses(relocationId, attemptId, commandIndex, dataJson) SELECT relocationId, attemptId, ?, ? FROM relocationSetupReceipts WHERE relocationId = ? AND attemptId = ? AND reportJson IS NULL AND NOT EXISTS(SELECT 1 FROM relocationSetupCancellations c WHERE c.relocationId = relocationSetupReceipts.relocationId AND c.attemptId = relocationSetupReceipts.attemptId)")
            .bind(command_index).bind(serde_json::to_string(&process)?).bind(&receipt.relocation_id).bind(attempt).execute(self.pool()).await?.rows_affected();
        if changed != 1 {
            bail!("Setup attempt finished or cancellation was requested; no further process should be spawned");
        }
        Ok(process)
    }

    pub async fn update_setup_root_process(
        &self,
        receipt: &RelocationSetupReceipt,
        previous: &RelocationSetupProcess,
        next: &RelocationSetupProcess,
    ) -> Result<()> {
        use SetupRootProcessPhase as Phase;
        let valid = match (previous.phase, next.phase) {
            (Phase::Starting, Phase::Started) => next.pid.is_some_and(|pid| pid > 0),
            (Phase::Starting, Phase::SpawnFailed) => {
                next.pid.is_none() && next.start_marker.is_none()
            }
            (Phase::Started, Phase::RootExitedOutputPending)
            | (Phase::RootExitedOutputPending, Phase::RootExited) => {
                next.pid == previous.pid && next.start_marker == previous.start_marker
            }
            _ => false,
        };
        if previous.boot_id != next.boot_id
            || !valid
            || previous.command_index != next.command_index
            || previous.platform != next.platform
        {
            bail!("Invalid setup root-process transition");
        }
        let attempt = receipt
            .attempt_id
            .as_deref()
            .ok_or_else(|| anyhow!("Setup has no claimed attempt"))?;
        let changed = sqlx::query("UPDATE relocationSetupProcesses SET dataJson = ? WHERE relocationId = ? AND attemptId = ? AND commandIndex = ? AND dataJson = ? AND EXISTS(SELECT 1 FROM relocationSetupReceipts WHERE relocationId = ? AND attemptId = ? AND reportJson IS NULL)")
            .bind(serde_json::to_string(next)?).bind(&receipt.relocation_id).bind(attempt).bind(previous.command_index).bind(serde_json::to_string(previous)?)
            .bind(&receipt.relocation_id).bind(attempt).execute(self.pool()).await?.rows_affected();
        if changed != 1 {
            bail!("Setup process record changed; its stale result was not stored");
        }
        Ok(())
    }

    pub async fn list_setup_root_processes(
        &self,
        receipt: &RelocationSetupReceipt,
    ) -> Result<Vec<RelocationSetupProcess>> {
        let Some(attempt) = &receipt.attempt_id else {
            return Ok(Vec::new());
        };
        let rows: Vec<String> = sqlx::query_scalar("SELECT dataJson FROM relocationSetupProcesses WHERE relocationId = ? AND attemptId = ? ORDER BY commandIndex")
            .bind(&receipt.relocation_id).bind(attempt).fetch_all(self.pool()).await?;
        rows.into_iter()
            .map(|data| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }
}
