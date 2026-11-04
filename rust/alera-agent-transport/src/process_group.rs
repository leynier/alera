//! Unix process groups that end with the runtime host.
//!
//! An agent CLI starts processes of its own, such as the MCP servers the
//! Claude CLI launches, and `kill_on_drop` reaches none of them. It does not
//! reach the agent either when the host is killed or crashes. Every agent
//! therefore runs in a process group led by a small `/bin/sh` watcher that
//! blocks reading a pipe whose only write end the host holds. The kernel
//! closes that end when the host exits for any reason, and close and drop
//! close it on purpose. At end-of-file the watcher sends SIGTERM to the group,
//! then SIGKILL, which also ends the watcher, after the grace period.
//!
//! Linux's `PR_SET_PDEATHSIG` only reaches the direct child and macOS has no
//! equivalent, so the pipe is the one mechanism that covers the whole group
//! on both. The watcher starts first and the agent joins its group at spawn,
//! so the agent never runs unwatched. Commands an agent moves into a group of
//! their own, as the Claude CLI does for its Bash tool, are not part of this.

use std::io::{self, PipeWriter};
use std::os::fd::AsRawFd;
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use tokio::process::{Child, Command};

/// Where the watcher finds the read end of its pipe.
const WATCH_FD: libc::c_int = 3;

/// Ignores the signals it sends and any hangup, waits for end-of-file on fd 3,
/// then stops the group, waiting `$1` seconds between SIGTERM and SIGKILL.
const WATCH_SCRIPT: &str =
    "trap '' HUP INT TERM; read -r _ <&3; kill -TERM 0; sleep \"$1\"; kill -KILL 0";

/// A process group whose members are stopped when this value is dropped or
/// the process that owns it dies.
pub(crate) struct ProcessGroup {
    id: libc::pid_t,
    watch: Option<PipeWriter>,
    // Never waited on while this value lives: an unreaped watcher keeps its
    // pid, and with it the group id, from being reused, so signalling the
    // group cannot reach a stranger. Dropping it leaves the reaping to Tokio.
    _watcher: Child,
}

impl ProcessGroup {
    /// Start the watcher of a new, otherwise empty group. `grace` is how long
    /// members get between SIGTERM and SIGKILL, rounded up to whole seconds.
    pub(crate) fn start(grace: Duration) -> io::Result<Self> {
        let (reader, writer) = io::pipe()?;
        let read_fd = reader.as_raw_fd();
        let seconds = (grace.as_secs() + u64::from(grace.subsec_nanos() > 0)).max(1);
        let mut command = windowless_async_command("/bin/sh");
        command
            .arg("-c")
            .arg(WATCH_SCRIPT)
            .arg("alera-agent-watch")
            .arg(seconds.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0);
        // Safety: the closure only calls dup2 or fcntl, which are
        // async-signal-safe and valid between fork and exec.
        unsafe {
            command.pre_exec(move || {
                // The pipe is close-on-exec so no other child inherits it.
                // dup2 clears that flag on its copy but does nothing when the
                // read end already is fd 3.
                let result = if read_fd == WATCH_FD {
                    libc::fcntl(read_fd, libc::F_SETFD, 0)
                } else {
                    libc::dup2(read_fd, WATCH_FD)
                };
                if result == -1 {
                    Err(io::Error::last_os_error())
                } else {
                    Ok(())
                }
            });
        }
        let watcher = command.spawn()?;
        drop(reader);
        let id = watcher
            .id()
            .and_then(|pid| libc::pid_t::try_from(pid).ok())
            .ok_or_else(|| io::Error::other("process group watcher has no pid"))?;
        Ok(Self {
            id,
            watch: Some(writer),
            _watcher: watcher,
        })
    }

    /// Start `command` as a member of this group.
    pub(crate) fn join(&self, command: &mut Command) {
        command.process_group(self.id);
    }

    /// Send SIGTERM to the group now and SIGKILL after the grace period. The
    /// watcher does both, so this returns at once.
    pub(crate) fn terminate(&mut self) {
        self.watch.take();
    }

    /// Send SIGKILL to the whole group, the watcher included.
    pub(crate) fn kill(&mut self) {
        self.watch.take();
        // Safe: the unreaped watcher keeps the group id ours, and an empty
        // group only returns ESRCH.
        unsafe {
            libc::kill(-self.id, libc::SIGKILL);
        }
    }
}

impl Drop for ProcessGroup {
    fn drop(&mut self) {
        self.terminate();
    }
}
