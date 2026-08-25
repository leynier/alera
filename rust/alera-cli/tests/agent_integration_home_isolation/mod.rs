use std::path::Path;
use std::process::Command;

/// Builds an `alera` command whose home directory is the runtime directory the
/// test already owns.
///
/// `terminal-host` and the `runtime` commands reconcile the agent-status
/// integrations of whoever owns the home directory: they install the managed
/// hooks for every enabled agent and strip them for every disabled one. A test
/// process runs with all of them off, so without this it would uninstall the
/// developer's own hooks - including the Claude ones in `~/.claude/settings.json`
/// - on every `cargo test`.
///
/// `dirs::home_dir()` reads `HOME` on Unix. On Windows it asks the shell for the
/// profile folder and ignores the variables, so the isolation there is
/// best-effort; `cargo test --workspace` runs on Linux in CI.
pub fn alera_command_with_isolated_home(runtime_dir: &Path) -> Command {
    let home = runtime_dir.join("agent-integration-home");
    let _ = std::fs::create_dir_all(&home);
    let mut command = alera_core::child_process::windowless_command(env!("CARGO_BIN_EXE_alera"));
    command.env("HOME", &home);
    command.env("USERPROFILE", &home);
    command
}
