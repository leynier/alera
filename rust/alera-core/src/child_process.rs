//! Spawning rules shared by every process Alera starts on the user's machine.
//!
//! Both processes that spawn children run without a console on Windows: the
//! Flutter runner is a GUI-subsystem binary and the terminal-host sidecar is
//! started with `DETACHED_PROCESS`. Windows gives a console child launched from
//! such a process a brand new console *with a visible window*, which is the
//! terminal that flashes on screen for the length of a `git fetch`. The flag
//! below asks for a console without a window instead, and because grandchildren
//! inherit it, marking a `cmd.exe` wrapper covers the whole chain.
//!
//! The constructors here are the only supported way to build a command: a
//! `clippy.toml` lint rejects `Command::new` everywhere else, so the flag cannot
//! be forgotten at a new call site.

use std::ffi::OsStr;
use std::process::Command;

/// `CREATE_NO_WINDOW`. Spelled out here so `alera-core` does not need the
/// `windows` crate for a single constant.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// A [`Command`] that will not open a console window.
#[allow(clippy::disallowed_methods)]
pub fn windowless_command(program: impl AsRef<OsStr>) -> Command {
    #[cfg_attr(not(windows), allow(unused_mut))]
    let mut command = Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;

        command.creation_flags(CREATE_NO_WINDOW);
    }
    command
}

/// [`windowless_command`] for the async command the sidecar spawns with.
#[cfg(feature = "async-process")]
#[allow(clippy::disallowed_methods)]
pub fn windowless_async_command(program: impl AsRef<OsStr>) -> tokio::process::Command {
    #[cfg_attr(not(windows), allow(unused_mut))]
    let mut command = tokio::process::Command::new(program);
    #[cfg(windows)]
    command.creation_flags(CREATE_NO_WINDOW);
    command
}

/// A background [`tokio::process::Command`] that also survives its launcher's
/// terminal session closing.
#[cfg(feature = "async-process")]
pub fn detached_windowless_async_command(program: impl AsRef<OsStr>) -> tokio::process::Command {
    #[cfg_attr(not(unix), allow(unused_mut))]
    let mut command = windowless_async_command(program);
    #[cfg(unix)]
    unsafe {
        command.pre_exec(|| {
            // `pre_exec` runs after fork, where only async-signal-safe work is
            // valid. `setsid` is the single syscall needed to leave the
            // launcher's controlling terminal and process group.
            if libc::setsid() == -1 {
                Err(std::io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    command
}
