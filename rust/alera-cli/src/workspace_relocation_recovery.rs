use alera_core::runtime::{
    RelocationSetupProcess, RuntimeStore, SetupRootObservation, SetupRootObservationState as State,
    SetupRootProcessPhase as Phase, WorkspaceRelocationRecovery,
};
use anyhow::{anyhow, bail, Result};

use crate::process_identity::{ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe};

pub(crate) async fn recover(
    store: &RuntimeStore,
    workspace_id: &str,
    relocation_id: &str,
    attempt_id: &str,
) -> Result<alera_core::runtime::WorktreeSetupReport> {
    let relocation = store
        .find_workspace_relocation(relocation_id)
        .await?
        .ok_or_else(|| anyhow!("Relocation not found"))?;
    if relocation.destination.id != workspace_id
        || relocation.destination.host_id != alera_core::runtime::LOCAL_HOST_ID
    {
        bail!("Recover setup from its owning task and host");
    }
    let receipt = store
        .find_relocation_setup(relocation_id)
        .await?
        .ok_or_else(|| anyhow!("Setup receipt not found"))?;
    if receipt.attempt_id.as_deref() != Some(attempt_id) {
        bail!("Setup attempt changed; inspect workspace recovery before trying again");
    }
    let boot_id =
        tokio::task::spawn_blocking(crate::relocation_setup_process::current_boot_id).await??;
    store
        .recover_interrupted_relocation_setup(&receipt, std::env::consts::OS, boot_id.as_deref())
        .await
}

pub(crate) async fn inspect(
    store: &RuntimeStore,
    workspace_id: &str,
    limit: u32,
) -> Result<Vec<WorkspaceRelocationRecovery>> {
    let mut records = store
        .list_workspace_relocation_recovery(workspace_id, limit)
        .await?;
    tokio::task::spawn_blocking(move || {
        let boot_id = crate::relocation_setup_process::current_boot_id()
            .ok()
            .flatten();
        for record in &mut records {
            record.setup_root_observations = record
                .setup_root_processes
                .iter()
                .map(|process| {
                    if record.relocation.destination.host_id != alera_core::runtime::LOCAL_HOST_ID {
                        return SetupRootObservation {
                            command_index: process.command_index,
                            state: State::Unknown,
                            reason: "Inspect this process on its owning host".into(),
                        };
                    }
                    observe(
                        process,
                        &SystemProcessIdentityProbe,
                        std::env::consts::OS,
                        boot_id.as_deref(),
                    )
                })
                .collect();
        }
        records
    })
    .await
    .map_err(Into::into)
}

fn observe(
    process: &RelocationSetupProcess,
    probe: &impl ProcessIdentityProbe,
    platform: &str,
    boot_id: Option<&str>,
) -> SetupRootObservation {
    let result = |state, reason: &str| SetupRootObservation {
        command_index: process.command_index,
        state,
        reason: reason.into(),
    };
    match process.phase {
        Phase::SpawnFailed => {
            return result(State::Exited, "The spawn failed before creating a process")
        }
        Phase::RootExited | Phase::RootExitedOutputPending => {
            return result(State::Exited, "The runtime recorded the root process exit")
        }
        Phase::Starting => return result(State::Unknown, "The spawn result was not recorded"),
        Phase::Started => {}
    }
    if process.platform != platform {
        return result(
            State::Unknown,
            "Inspect this process on its owning platform",
        );
    }
    if platform == "linux" {
        match (process.boot_id.as_deref(), boot_id) {
            (Some(previous), Some(current)) if previous != current => {
                return result(
                    State::Exited,
                    "The machine has rebooted since this process was started",
                )
            }
            (Some(_), Some(_)) => {}
            _ => {
                return result(
                    State::Unknown,
                    "The Linux boot identity could not be verified",
                )
            }
        }
    }
    let (Some(pid), Some(marker)) = (process.pid, process.start_marker) else {
        return result(State::Unknown, "The process identity was not captured");
    };
    match probe.lookup(pid) {
        ProcessLookup::Live(identity) if identity.start_marker == marker => {
            result(State::Live, "The recorded root process is still running")
        }
        ProcessLookup::Live(_) => {
            result(State::Exited, "The PID now belongs to a different process")
        }
        ProcessLookup::Exited => result(State::Exited, "The recorded root process has exited"),
        ProcessLookup::Unknown(reason) => result(State::Unknown, &reason),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::process_identity::ProcessIdentity;
    use std::cell::Cell;

    struct Probe {
        calls: Cell<u32>,
        value: ProcessLookup,
    }
    impl ProcessIdentityProbe for Probe {
        fn lookup(&self, _: u32) -> ProcessLookup {
            self.calls.set(self.calls.get() + 1);
            self.value.clone()
        }
    }
    fn process() -> RelocationSetupProcess {
        RelocationSetupProcess {
            command_index: 0,
            platform: "linux".into(),
            boot_id: Some("first-boot".into()),
            pid: Some(42),
            start_marker: Some(100),
            phase: Phase::Started,
        }
    }

    #[test]
    fn reboot_and_missing_boot_identity_never_treat_a_recycled_pid_as_ours() {
        let probe = Probe {
            calls: Cell::new(0),
            value: ProcessLookup::Live(ProcessIdentity {
                pid: 42,
                start_marker: 100,
            }),
        };
        assert_eq!(
            observe(&process(), &probe, "linux", Some("second-boot")).state,
            State::Exited
        );
        assert_eq!(
            observe(&process(), &probe, "linux", None).state,
            State::Unknown
        );
        let mut legacy = process();
        legacy.boot_id = None;
        assert_eq!(
            observe(&legacy, &probe, "linux", Some("first-boot")).state,
            State::Unknown
        );
        assert_eq!(probe.calls.get(), 0);
        assert_eq!(
            observe(&process(), &probe, "linux", Some("first-boot")).state,
            State::Live
        );
        assert_eq!(probe.calls.get(), 1);
    }

    #[test]
    fn changed_pid_identity_is_exited_but_lookup_failure_remains_unknown() {
        let probe = Probe {
            calls: Cell::new(0),
            value: ProcessLookup::Live(ProcessIdentity {
                pid: 42,
                start_marker: 200,
            }),
        };
        assert_eq!(
            observe(&process(), &probe, "linux", Some("first-boot")).state,
            State::Exited
        );
        let unknown = Probe {
            calls: Cell::new(0),
            value: ProcessLookup::Unknown("access denied".into()),
        };
        let result = observe(&process(), &unknown, "linux", Some("first-boot"));
        assert_eq!(result.state, State::Unknown);
        assert_eq!(result.reason, "access denied");
        let mut unrecorded = process();
        unrecorded.phase = Phase::Starting;
        assert_eq!(
            observe(&unrecorded, &unknown, "linux", Some("first-boot")).state,
            State::Unknown
        );
        assert_eq!(unknown.calls.get(), 1);
    }
}
