use std::collections::{HashMap, HashSet};
use std::time::Duration;

use sysinfo::{Pid, ProcessRefreshKind, ProcessStatus, ProcessesToUpdate, Signal, System};

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::resources::ShellProcess;

use super::{shutdown_error, Session, GRACE_PERIOD, KILL_PERIOD, POLL_INTERVAL};

const SWEEP_DEADLINE: Duration = Duration::from_secs(1);

#[derive(Default)]
pub(super) struct ShutdownGuard {
    processes: Vec<ShellProcess>,
    anchors: Vec<ShellProcess>,
    _reaper_leases: Vec<tokio::sync::OwnedMutexGuard<()>>,
}

impl ShutdownGuard {
    pub(super) async fn capture(sessions: &[&Session]) -> HostResult<Self> {
        let mut roots = Vec::new();
        let mut leases = Vec::new();
        for session in sessions {
            if let Some(shell) = session.shell() {
                leases.push(
                    tokio::time::timeout(SWEEP_DEADLINE, session.child_reaper.clone().lock_owned())
                        .await
                        .map_err(|_| shutdown_error("terminal reaper acquisition timed out"))?,
                );
                roots.push(shell);
            } else if session.running() && session.killer.is_some() {
                return Err(shutdown_error(
                    "cannot verify a running terminal's process identity",
                ));
            }
        }
        if roots.is_empty() {
            return Ok(Self::default());
        }
        let anchors = roots.clone();
        let processes =
            sweep(move || capture_owned(&process_table(), &roots, roots.clone(), false)).await??;
        Ok(Self {
            processes,
            anchors,
            _reaper_leases: leases,
        })
    }

    pub(super) async fn wait(&mut self) -> HostResult<()> {
        if self.anchors.is_empty() && self.processes.is_empty() {
            return Ok(());
        }
        let grace = tokio::time::Instant::now() + GRACE_PERIOD;
        let deadline = grace + KILL_PERIOD;
        let mut empty_sweeps = 0;
        loop {
            let kill = tokio::time::Instant::now() >= grace;
            // Keep our identities if the sweep fails so the error cannot be
            // mistaken for successful teardown and allow filesystem deletion.
            let processes = self.processes.clone();
            let anchors = self.anchors.clone();
            self.processes = sweep(move || {
                let system = process_table();
                let live = capture_owned(&system, &anchors, processes, true)?;
                if kill {
                    for identity in &live {
                        if let Some(process) = system.process(Pid::from_u32(identity.pid)) {
                            process.kill_with(Signal::Kill);
                        }
                    }
                }
                Ok(live)
            })
            .await??;
            if self.processes.is_empty() {
                // Enumeration can precede a final fork while its parent's
                // status is read after exit. Confirm quiescence in a fresh
                // sweep with the same reserved session identities.
                empty_sweeps += 1;
                if empty_sweeps >= 2 {
                    return Ok(());
                }
            } else {
                empty_sweeps = 0;
            }
            if tokio::time::Instant::now() >= deadline {
                return Err(shutdown_error(
                    "terminal processes did not exit before the deadline",
                ));
            }
            tokio::time::sleep(POLL_INTERVAL).await;
        }
    }
}

fn capture_owned(
    system: &System,
    anchors: &[ShellProcess],
    mut processes: Vec<ShellProcess>,
    allow_exited_anchor: bool,
) -> HostResult<Vec<ShellProcess>> {
    let mut sessions = HashSet::new();
    for anchor in anchors {
        let pid = Pid::from_u32(anchor.pid);
        let verified = system.process(pid).is_some_and(|process| {
            process.start_time() == anchor.start_time && process.session_id() == Some(pid)
        });
        if !(verified || allow_exited_anchor && is_unreaped_child(anchor.pid)) {
            return Err(shutdown_error(
                "terminal session identity cannot be verified",
            ));
        }
        sessions.insert(pid);
    }
    // Forked shutdown helpers can outlive their parent between sweeps. The
    // unreaped PTY leader reserves its PID and keeps this session scope safe
    // even after becoming a zombie; parent links alone cannot find those jobs.
    for (pid, process) in system.processes() {
        if process
            .session_id()
            .is_some_and(|sid| sessions.contains(&sid))
        {
            processes.push(ShellProcess {
                pid: pid.as_u32(),
                start_time: process.start_time(),
            });
        }
    }
    Ok(capture_tree(system, processes))
}

fn is_unreaped_child(pid: u32) -> bool {
    // macOS can omit zombies from proc_pidinfo. WNOWAIT proves this is still
    // our child without releasing its PID. Only use after initial identity
    // verification and while the reader's reaper lease remains held.
    unsafe {
        let mut status: libc::siginfo_t = std::mem::zeroed();
        libc::waitid(
            libc::P_PID,
            pid,
            &mut status,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        ) == 0
            && status.si_pid() == pid as libc::pid_t
    }
}

async fn sweep<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> HostResult<T> {
    tokio::time::timeout(SWEEP_DEADLINE, tokio::task::spawn_blocking(work))
        .await
        .map_err(|_| shutdown_error("process inspection timed out"))?
        .map_err(shutdown_error)
}

fn process_table() -> System {
    let mut system = System::new();
    system.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().without_tasks(),
    );
    system
}

fn capture_tree(system: &System, roots: Vec<ShellProcess>) -> Vec<ShellProcess> {
    let mut children = HashMap::<u32, Vec<u32>>::new();
    for (pid, process) in system.processes() {
        if let Some(parent) = process.parent() {
            children
                .entry(parent.as_u32())
                .or_default()
                .push(pid.as_u32());
        }
    }
    let mut pending = roots;
    let mut seen = HashSet::new();
    let mut live = Vec::new();
    while let Some(identity) = pending.pop() {
        let Some(process) = system.process(Pid::from_u32(identity.pid)) else {
            continue;
        };
        if process.start_time() != identity.start_time
            || matches!(
                process.status(),
                ProcessStatus::Zombie | ProcessStatus::Dead
            )
            || !seen.insert(identity.pid)
        {
            continue;
        }
        live.push(identity);
        // Follow only verified live parents. Children of an exited root may
        // have been reparented, so their previously captured identities stay
        // independent roots on subsequent sweeps.
        if let Some(descendants) = children.get(&identity.pid) {
            for pid in descendants {
                if let Some(child) = system.process(Pid::from_u32(*pid)) {
                    pending.push(ShellProcess {
                        pid: *pid,
                        start_time: child.start_time(),
                    });
                }
            }
        }
    }
    live
}

#[cfg(test)]
#[path = "workspace_shutdown_unix_tests.rs"]
mod tests;
