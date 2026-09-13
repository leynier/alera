use alera_core::runtime::{
    RelocationSetupProcess, RelocationSetupReceipt, RuntimeStore, SetupRootProcessPhase,
};
use anyhow::Result;

use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};

pub(crate) struct SetupProcessJournal<'a> {
    pub store: &'a RuntimeStore,
    pub receipt: &'a RelocationSetupReceipt,
    pub command_index: u32,
}

impl SetupProcessJournal<'_> {
    pub async fn begin(&self) -> Result<RelocationSetupProcess> {
        let boot_id = tokio::task::spawn_blocking(current_boot_id).await??;
        self.store
            .begin_setup_root_process(
                self.receipt,
                self.command_index,
                std::env::consts::OS,
                boot_id.as_deref(),
            )
            .await
    }

    pub async fn spawned(
        &self,
        previous: &RelocationSetupProcess,
        pid: u32,
    ) -> Result<RelocationSetupProcess> {
        let lookup =
            tokio::task::spawn_blocking(move || SystemProcessIdentityProbe.lookup(pid)).await?;
        let marker = match lookup {
            ProcessLookup::Live(identity) => Some(identity.start_marker),
            _ => None,
        };
        let process = RelocationSetupProcess {
            pid: Some(pid),
            start_marker: marker,
            phase: SetupRootProcessPhase::Started,
            ..previous.clone()
        };
        self.store
            .update_setup_root_process(self.receipt, previous, &process)
            .await?;
        Ok(process)
    }

    pub async fn ended(
        &self,
        previous: &RelocationSetupProcess,
        phase: SetupRootProcessPhase,
    ) -> Result<()> {
        self.store
            .update_setup_root_process(
                self.receipt,
                previous,
                &RelocationSetupProcess {
                    phase,
                    ..previous.clone()
                },
            )
            .await
    }
}

pub(crate) fn current_boot_id() -> Result<Option<String>> {
    #[cfg(target_os = "linux")]
    {
        let value = std::fs::read_to_string("/proc/sys/kernel/random/boot_id")?;
        Ok(Some(uuid::Uuid::parse_str(value.trim())?.to_string()))
    }
    #[cfg(not(target_os = "linux"))]
    {
        Ok(None)
    }
}
