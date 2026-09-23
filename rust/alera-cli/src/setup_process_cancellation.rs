use std::process::ExitStatus;
use std::time::Duration;

use alera_core::runtime::{RelocationSetupDescendant, RelocationSetupProcess};
use anyhow::{anyhow, bail, Result};
use tokio::process::Child;

use crate::process_identity::{
    terminate_process, ProcessIdentity, ProcessIdentityProbe, ProcessLookup,
    SystemProcessIdentityProbe,
};
use crate::relocation_setup_process::{current_boot_id, SetupProcessJournal};

pub(crate) struct SetupProcessExit {
    pub status: ExitStatus,
    pub closure_error: Option<String>,
}

pub(crate) async fn wait(
    child: &mut Child,
    journal: Option<&SetupProcessJournal<'_>>,
    root: Option<&RelocationSetupProcess>,
) -> Result<SetupProcessExit> {
    let (Some(journal), Some(root)) = (journal, root) else {
        return Ok(SetupProcessExit {
            status: child.wait().await?,
            closure_error: None,
        });
    };
    loop {
        tokio::select! {
            status = child.wait() => return Ok(SetupProcessExit { status: status?, closure_error: None }),
            _ = tokio::time::sleep(Duration::from_millis(200)) => {
                if journal.store.setup_cancellation_requested(journal.receipt).await? {
                    return stop(child, journal, root).await;
                }
            }
        }
    }
}

async fn stop(
    child: &mut Child,
    journal: &SetupProcessJournal<'_>,
    root: &RelocationSetupProcess,
) -> Result<SetupProcessExit> {
    if child.id() != root.pid {
        bail!("Setup child no longer matches the recorded process");
    }
    let owned = root.clone();
    let identities = tokio::task::spawn_blocking(move || capture_descendants(&owned)).await??;
    let mut descendants = Vec::new();
    for identity in identities {
        descendants.push(
            journal
                .store
                .record_setup_descendant(journal.receipt, root, identity.pid, identity.start_marker)
                .await?,
        );
    }
    let signals = descendants.clone();
    tokio::task::spawn_blocking(move || -> Result<()> {
        for process in signals {
            if !process.exit_verified {
                verify_boot(&process.platform, process.boot_id.as_deref())?;
                terminate_process(ProcessIdentity {
                    pid: process.pid,
                    start_marker: process.start_marker,
                })
                .map_err(|error| anyhow!(error))?;
            }
        }
        Ok(())
    })
    .await??;
    child.start_kill()?;
    let status = tokio::time::timeout(Duration::from_secs(10), child.wait())
        .await
        .map_err(|_| anyhow!("Setup root exit could not be verified within 10 seconds"))??;
    let closure_error = verify_descendant_exits(journal, &descendants)
        .await
        .err()
        .map(|error| error.to_string());
    Ok(SetupProcessExit {
        status,
        closure_error,
    })
}

fn verify_boot(platform: &str, recorded: Option<&str>) -> Result<()> {
    if platform != std::env::consts::OS {
        bail!("Setup process belongs to another platform");
    }
    if platform == "linux" && (recorded.is_none() || current_boot_id()?.as_deref() != recorded) {
        bail!("Setup process boot identity changed or could not be verified");
    }
    Ok(())
}

fn require_root(root: &RelocationSetupProcess) -> Result<ProcessIdentity> {
    verify_boot(&root.platform, root.boot_id.as_deref())?;
    let expected = ProcessIdentity {
        pid: root
            .pid
            .ok_or_else(|| anyhow!("Setup root PID was not captured"))?,
        start_marker: root
            .start_marker
            .ok_or_else(|| anyhow!("Setup root identity was not captured"))?,
    };
    match SystemProcessIdentityProbe.lookup(expected.pid) {
        ProcessLookup::Live(actual) if actual == expected => Ok(actual),
        actual => bail!("Setup root ownership could not be verified: {actual}"),
    }
}

fn capture_descendants(root: &RelocationSetupProcess) -> Result<Vec<ProcessIdentity>> {
    let identity = require_root(root)?;
    let topology = crate::terminal_host::resources::sweep_process_topology();
    let mut descendants = Vec::new();
    for pid in topology.descendants(identity.pid) {
        match SystemProcessIdentityProbe.lookup(pid) {
            ProcessLookup::Live(process) => descendants.push(process),
            ProcessLookup::Exited => {}
            ProcessLookup::Unknown(reason) => {
                bail!("Could not verify setup descendant {pid}: {reason}")
            }
        }
    }
    require_root(root)?;
    let current =
        crate::terminal_host::resources::sweep_process_topology().descendants(identity.pid);
    if current
        .iter()
        .any(|pid| !descendants.iter().any(|process| process.pid == *pid))
    {
        bail!("Setup process tree changed during capture; no processes were signalled");
    }
    for descendant in &descendants {
        if !current.contains(&descendant.pid) {
            match SystemProcessIdentityProbe.lookup(descendant.pid) {
                ProcessLookup::Exited => {}
                _ => bail!("Setup descendant {} changed ownership during capture; no processes were signalled", descendant.pid),
            }
        }
    }
    Ok(descendants)
}

async fn verify_descendant_exits(
    journal: &SetupProcessJournal<'_>,
    descendants: &[RelocationSetupDescendant],
) -> Result<()> {
    let mut pending: Vec<_> = descendants
        .iter()
        .filter(|process| !process.exit_verified)
        .cloned()
        .collect();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !pending.is_empty() {
        let check = pending.clone();
        let exited = tokio::task::spawn_blocking(move || {
            check
                .into_iter()
                .filter(
                    |process| match SystemProcessIdentityProbe.lookup(process.pid) {
                        ProcessLookup::Exited => true,
                        ProcessLookup::Live(actual) => actual.start_marker != process.start_marker,
                        ProcessLookup::Unknown(_) => false,
                    },
                )
                .collect::<Vec<_>>()
        })
        .await?;
        for process in exited {
            journal
                .store
                .verify_setup_descendant_exit(journal.receipt, &process)
                .await?;
            pending.retain(|item| {
                item.pid != process.pid || item.start_marker != process.start_marker
            });
        }
        if !pending.is_empty() && tokio::time::Instant::now() >= deadline {
            bail!(
                "Setup descendant exits remain unverified: {}",
                pending
                    .iter()
                    .map(|process| process.pid.to_string())
                    .collect::<Vec<_>>()
                    .join(", ")
            );
        }
        if !pending.is_empty() {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
    Ok(())
}
