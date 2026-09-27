use std::time::Duration;

use super::Session;

impl Session {
    /// The PTY's foreground process group, when it is not the shell's own.
    ///
    /// An interactive shell hands the terminal to each job it runs, so while an
    /// agent is running this is the agent's group, and when the shell is back
    /// at its prompt it is the shell's. A tab whose PTY runs the agent directly
    /// reports the root group, which is excluded: its exit ends the session.
    #[cfg(unix)]
    pub fn agent_process_group(&self) -> Option<u32> {
        if !self.running {
            return None;
        }
        let group = self.master.as_ref()?.process_group_leader()?;
        let group = u32::try_from(group).ok().filter(|group| *group > 0)?;
        (Some(group) != self.shell.map(|shell| shell.pid)).then_some(group)
    }

    /// Windows has no job control to ask, so liveness there relies on the
    /// agents' own session-end hooks and on the silent-output check.
    #[cfg(not(unix))]
    pub fn agent_process_group(&self) -> Option<u32> {
        None
    }

    pub fn output_idle_for(&self) -> Duration {
        self.last_output_at.elapsed()
    }
}

/// Whether any process is still a member of `group`. `ESRCH` is the only
/// answer that proves the group is gone; `EPERM` means it exists.
#[cfg(unix)]
pub fn process_group_alive(group: u32) -> bool {
    let Ok(group) = libc::pid_t::try_from(group) else {
        return true;
    };
    if group <= 1 {
        return true;
    }
    // SAFETY: signal 0 performs only the existence and permission checks.
    let result = unsafe { libc::kill(-group, 0) };
    result == 0 || std::io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH)
}

#[cfg(not(unix))]
pub fn process_group_alive(_group: u32) -> bool {
    true
}

/// Whether `pid` still exists, so a relaunched agent can take over from one
/// that died without reporting.
#[cfg(unix)]
pub fn process_alive(pid: u32) -> bool {
    let Ok(pid) = libc::pid_t::try_from(pid) else {
        return true;
    };
    // SAFETY: signal 0 performs only the existence and permission checks.
    let result = unsafe { libc::kill(pid, 0) };
    result == 0 || std::io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH)
}

/// Refreshes only that pid in the process table.
#[cfg(not(unix))]
pub fn process_alive(pid: u32) -> bool {
    crate::terminal_host::resources::seal_shell_process(pid).is_some()
}

#[cfg(test)]
#[test]
fn this_process_is_alive_and_an_unused_pid_is_not() {
    assert!(process_alive(std::process::id()));
    assert!(!process_alive(4_000_000));
}

#[cfg(all(test, unix))]
mod tests {
    use std::os::unix::process::CommandExt;

    use super::*;

    // Unix-only test fixture: no console window to suppress.
    #[allow(clippy::disallowed_methods)]
    #[test]
    fn a_live_group_is_alive_and_a_reaped_one_is_not() {
        let mut child = std::process::Command::new("sleep")
            .arg("30")
            .process_group(0)
            .spawn()
            .expect("spawn sleep");
        let group = child.id();
        assert!(process_group_alive(group));
        assert!(process_alive(group));
        child.kill().expect("kill sleep");
        child.wait().expect("reap sleep");
        assert!(!process_group_alive(group));
        assert!(!process_alive(group));
    }
}
