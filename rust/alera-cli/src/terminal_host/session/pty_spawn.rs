use portable_pty::{native_pty_system, Child, ChildKiller, CommandBuilder, MasterPty, PtySize};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostLaunch;
use crate::terminal_host::resources::{seal_shell_process, ShellProcess};

pub(super) struct SpawnedPty {
    pub(super) child: Box<dyn Child + Send + Sync>,
    pub(super) master: Box<dyn MasterPty + Send>,
    pub(super) reader: Box<dyn std::io::Read + Send>,
    pub(super) writer: Box<dyn std::io::Write + Send>,
    pub(super) killer: Box<dyn ChildKiller + Send + Sync>,
    pub(super) shell: Option<ShellProcess>,
}

pub(super) fn spawn_pty(
    launch: TerminalHostLaunch,
    terminal_handle: String,
    working_directory: String,
    cols: u16,
    rows: u16,
) -> HostResult<SpawnedPty> {
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|error| HostError::state(error.to_string()))?;
    let mut command = CommandBuilder::new(&launch.shell);
    command.args(&launch.arguments);
    // Session launch environments are explicit so terminals do not inherit
    // stale variables from the long-running host process.
    command.env_clear();
    for (key, value) in &launch.environment {
        command.env(key, value);
    }
    // A raw terminal launch still belongs to its workspace. Keep the cwd at
    // the PTY boundary so every shell, including Windows shells, starts there
    // even when no startup script emits a `cd` command.
    command.cwd(&working_directory);
    // Agents inside this PTY use the session id as their orchestration identity.
    command.env("ALERA_TERMINAL_HANDLE", terminal_handle);
    let child = pair
        .slave
        .spawn_command(command)
        .map_err(|error| HostError::state(error.to_string()))?;
    // The master must be the only remaining PTY endpoint owned by the host.
    drop(pair.slave);
    let killer = child.clone_killer();
    // Capture identity before the reader owns the child so resource samples can
    // prove that a later PID still belongs to this shell process.
    let shell = child.process_id().and_then(seal_shell_process);
    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|error| HostError::state(error.to_string()))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|error| HostError::state(error.to_string()))?;
    Ok(SpawnedPty {
        child,
        master: pair.master,
        reader,
        writer,
        killer,
        shell,
    })
}
