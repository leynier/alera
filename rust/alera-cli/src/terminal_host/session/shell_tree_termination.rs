use std::time::Duration;

use crate::terminal_host::resources::{sweep_process_topology, ShellProcess};

/// How long the process-table sweep may run before the kill proceeds without
/// it. Closing a terminal must not hang behind a busy machine.
const SWEEP_DEADLINE: Duration = Duration::from_secs(1);

/// Kill a session's shell together with everything it spawned.
///
/// `kill_root` is the PTY's own killer, and it reaches the shell and nothing
/// else: on unix `portable-pty` sends `SIGHUP` to the direct child, on Windows
/// it calls `TerminateProcess` on the direct process. The kernel hangup that
/// normally sweeps up the rest only reaches the controlling terminal's
/// foreground group, so whatever left it survives: an agent CLI that
/// daemonizes, an MCP server, a language server. Those keep holding the
/// worktree's working directory, which on Windows is enough to block deleting
/// it.
///
/// The subtree is captured BEFORE anything is signalled. Once the root dies its
/// children reparent away and can no longer be found by walking parent links,
/// and any row still naming the vacated pid is a pid-recycle coincidence rather
/// than a descendant.
///
/// A session whose shell already exited has `shell` cleared, so it never
/// reaches the sweep. That is deliberate for the same reason: its real
/// descendants are unreachable by then, and signalling what is left at that pid
/// would be signalling a stranger.
pub(super) async fn kill_shell_tree(shell: Option<ShellProcess>, kill_root: impl FnOnce()) {
    if let Some(shell) = shell {
        kill_descendants(shell).await;
    }
    kill_root();
}

/// The live descendants of `shell`, or `None` when the sweep cannot prove the
/// pid still holds it.
///
/// A sweep that fails or overruns its deadline also answers `None`. Refusing to
/// act without positive proof is deliberate: guessing wrong means signalling an
/// unrelated process tree, which is a worse outcome than leaking one.
async fn live_descendants(shell: ShellProcess) -> Option<Vec<u32>> {
    // On a blocking thread: the sweep walks every process on the machine and
    // must not sit on the async runtime.
    let sweep = tokio::task::spawn_blocking(move || {
        let index = sweep_process_topology();
        index.holds(shell).then(|| index.descendants(shell.pid))
    });
    tokio::time::timeout(SWEEP_DEADLINE, sweep)
        .await
        .ok()?
        .ok()?
}

#[cfg(unix)]
async fn kill_descendants(shell: ShellProcess) {
    let Some(descendants) = live_descendants(shell).await else {
        return;
    };
    for pid in descendants {
        // SIGTERM rather than SIGKILL: agents and MCP servers use it to flush
        // state and release sockets. Anything that ignores it still survives,
        // which is no worse than not sweeping at all.
        //
        // Safe: `kill` only reads the pid, and a pid that died since the sweep
        // just yields ESRCH.
        unsafe {
            libc::kill(pid as libc::pid_t, libc::SIGTERM);
        }
    }
}

#[cfg(windows)]
async fn kill_descendants(shell: ShellProcess) {
    // Windows has no controlling-terminal hangup, so the tree only dies if
    // something walks it. `taskkill /T` does, but only once the sweep proves
    // the pid still holds this shell: `/F` against a recycled pid force-kills
    // a stranger's entire tree.
    //
    // Orca bounds this with an ancestry walk and documents that it cannot close
    // the class, because a recycle landing on another of its own descendants
    // still reads as owned. The sealed start time closes it instead.
    if live_descendants(shell).await.is_none() {
        return;
    }
    // Racing an already-exited tree is expected, so the result is ignored.
    let _ = alera_core::child_process::windowless_async_command("taskkill")
        .args(["/PID", &shell.pid.to_string(), "/T", "/F"])
        .output()
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn this_process() -> ShellProcess {
        crate::terminal_host::resources::seal_shell_process(std::process::id())
            .expect("this process is live")
    }

    #[tokio::test]
    async fn a_missing_shell_still_kills_the_root() {
        // Restored checkpoints and stubs have no process behind them.
        let mut killed = false;

        kill_shell_tree(None, || killed = true).await;

        assert!(killed);
    }

    #[tokio::test]
    async fn the_root_is_killed_even_when_the_sweep_finds_nothing_to_do() {
        let recycled = ShellProcess {
            pid: this_process().pid,
            start_time: this_process().start_time + 1,
        };
        let mut killed = false;

        kill_shell_tree(Some(recycled), || killed = true).await;

        assert!(killed);
    }

    #[tokio::test]
    async fn a_live_shell_reports_its_descendants() {
        assert!(live_descendants(this_process()).await.is_some());
    }

    #[tokio::test]
    async fn a_recycled_pid_reports_no_descendants_to_signal() {
        // Same pid, a start time this process never had: whatever lives there
        // is not ours to signal.
        let sealed = this_process();
        let recycled = ShellProcess {
            pid: sealed.pid,
            start_time: sealed.start_time + 1,
        };

        assert_eq!(live_descendants(recycled).await, None);
    }

    #[tokio::test]
    async fn an_absent_pid_reports_no_descendants_to_signal() {
        let absent = ShellProcess {
            pid: u32::MAX,
            start_time: 1,
        };

        assert_eq!(live_descendants(absent).await, None);
    }

    /// Poll the process table until `predicate` holds, or give up. Polling
    /// rather than sleeping a fixed span keeps the case honest on a loaded CI
    /// box without making it slow on an idle one.
    #[cfg(unix)]
    async fn wait_until(mut predicate: impl FnMut() -> bool) -> bool {
        for _ in 0..100 {
            if predicate() {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    #[cfg(unix)]
    #[tokio::test]
    // Test fixture: it runs from a console, so the console-window suppression in
    // `alera_core::child_process` does not apply.
    #[allow(clippy::disallowed_methods)]
    async fn a_descendant_that_outlives_the_shell_is_signalled() {
        // The case the sweep exists for: `sleep` is a child of `sh`, so the
        // root killer alone would leave it running.
        let mut shell_process = std::process::Command::new("sh")
            .arg("-c")
            .arg("sleep 60 & wait")
            .spawn()
            .expect("sh is available");
        let shell_pid = shell_process.id();
        let sealed = crate::terminal_host::resources::seal_shell_process(shell_pid)
            .expect("the shell is live");

        let descendants_of_shell = || sweep_process_topology().descendants(shell_pid);
        assert!(
            wait_until(|| !descendants_of_shell().is_empty()).await,
            "the shell never spawned its child"
        );
        let child_pid = descendants_of_shell()[0];

        kill_descendants(sealed).await;

        let gone = wait_until(|| {
            // A pid missing from a fresh sweep is gone. `sh` is still alive and
            // has not reaped it yet, so this cannot be read off a zombie.
            !sweep_process_topology().holds(ShellProcess {
                pid: child_pid,
                start_time: sealed.start_time,
            }) && !sweep_process_topology()
                .descendants(shell_pid)
                .contains(&child_pid)
        })
        .await;

        let _ = shell_process.kill();
        let _ = shell_process.wait();
        assert!(gone, "the descendant outlived the sweep");
    }
}
