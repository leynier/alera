use std::collections::BTreeMap;

use alera_core::runtime::{WorkspaceStatus, WorkspaceTabRecord};
use serde_json::{json, Value};

use crate::agent_status::prepare_launch_environment;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{event, TerminalHostLaunch};
use crate::terminal_host::session::{PtyWriteCompletion, Session};

use super::pty_event_forwarder::forward_pty_event;
use super::{ServerActor, ServerCommand};

const DEFAULT_TERMINAL_COLS: u16 = 80;
const DEFAULT_TERMINAL_ROWS: u16 = 24;
const STARTUP_INPUT_DELAY_MS: u64 = 120;
const STARTUP_SUBMIT_DELAY_MS: u64 = 500;

pub(super) struct DefaultTerminalLaunch {
    pub launch: TerminalHostLaunch,
    pub interactive_shell: String,
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
enum TerminalPlatform {
    Posix,
    Windows,
}

impl ServerActor {
    pub(super) async fn reconcile_spawn_on_create_tabs(&mut self) {
        let workspaces = match self.runtime_store.list_all_workspaces().await {
            Ok(workspaces) => workspaces,
            Err(error) => {
                eprintln!("failed to list workspaces for terminal reconciliation: {error}");
                return;
            }
        };
        for workspace in workspaces {
            let tabs = match self.runtime_store.list_workspace_tabs(&workspace.id).await {
                Ok(tabs) => tabs,
                Err(error) => {
                    eprintln!(
                        "failed to list terminal tabs for workspace {}: {error}",
                        workspace.id
                    );
                    continue;
                }
            };
            for tab in tabs.into_iter().filter(spawns_on_create) {
                if let Err(error) = self.ensure_spawn_on_create_terminal(&tab).await {
                    eprintln!(
                        "failed to restore spawn-on-create terminal {}: {}",
                        tab.id,
                        error.wire_message()
                    );
                    let _ = self.runtime_store.remove_workspace_tab(&tab.id).await;
                }
            }
        }
    }

    pub(super) async fn upsert_workspace_tab_and_spawn(
        &mut self,
        tab: WorkspaceTabRecord,
    ) -> HostResult<WorkspaceTabRecord> {
        let saved = self
            .runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        if let Err(error) = self.ensure_spawn_on_create_terminal(&saved).await {
            let _ = self.runtime_store.remove_workspace_tab(&saved.id).await;
            self.terminate_sessions_for_tab(&saved.id).await;
            return Err(error);
        }
        self.broadcast_authenticated(event("workspaceTabsChanged", json!({})));
        Ok(saved)
    }

    pub(super) async fn ensure_spawn_on_create_terminal(
        &mut self,
        tab: &WorkspaceTabRecord,
    ) -> HostResult<bool> {
        if !spawns_on_create(tab) {
            return Ok(false);
        }
        let session_id = terminal_session_id(tab);
        if self.sessions.get(&session_id).is_some_and(Session::running) {
            return Ok(false);
        }
        let workspace = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::state(format!("workspace not found: {}", tab.workspace_id))
            })?;
        if workspace.status != WorkspaceStatus::Active {
            return Err(HostError::state(format!(
                "workspace is not active: {}",
                workspace.id
            )));
        }

        let max_bytes = self.config.scrollback_bytes as usize;
        let (initial_scrollback, initial_output_stream_bytes) = self
            .take_terminal_restart_state(&session_id, &workspace.id, &tab.id, max_bytes)
            .await;
        let default_launch =
            default_terminal_launch(&workspace.path, self.config.login_shell).await;
        self.start_new_terminal_session(
            session_id.clone(),
            workspace.id,
            tab.id.clone(),
            workspace.path,
            default_launch.launch,
            DEFAULT_TERMINAL_COLS,
            DEFAULT_TERMINAL_ROWS,
            initial_scrollback,
            initial_output_stream_bytes,
        )
        .await?;
        if let Some(command) = initial_command(tab) {
            let instance_id = self
                .sessions
                .get(&session_id)
                .map(Session::instance_id)
                .expect("spawned terminal was inserted");
            self.schedule_terminal_startup_input(
                session_id,
                instance_id,
                default_launch.interactive_shell,
                command,
            );
        }
        Ok(true)
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn start_new_terminal_session(
        &mut self,
        session_id: String,
        workspace_id: String,
        tab_id: String,
        working_directory: String,
        mut launch: TerminalHostLaunch,
        cols: u16,
        rows: u16,
        initial_scrollback: Vec<u8>,
        initial_output_stream_bytes: u64,
    ) -> HostResult<()> {
        let agent_settings = self
            .runtime_store
            .agent_status_hook_settings()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let runtime_dir = self.runtime_dir.clone();
        let launch_session_id = session_id.clone();
        let launch_workspace_id = workspace_id.clone();
        let launch_tab_id = tab_id.clone();
        let mut environment = std::mem::take(&mut launch.environment);
        launch.environment = tokio::task::spawn_blocking(move || {
            prepare_launch_environment(
                &runtime_dir,
                &launch_session_id,
                &launch_workspace_id,
                &launch_tab_id,
                &agent_settings,
                &mut environment,
            )?;
            Ok::<_, anyhow::Error>(environment)
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .map_err(|error| HostError::state(error.to_string()))?;
        let inbox = self.inbox.clone();
        let reader_session_id = session_id.clone();
        let session = Session::start(
            session_id.clone(),
            workspace_id,
            tab_id,
            working_directory,
            &launch,
            cols,
            rows,
            self.config.scrollback_bytes as usize,
            &initial_scrollback,
            initial_output_stream_bytes,
            &self.store,
            move |event| forward_pty_event(&inbox, &reader_session_id, event),
        )
        .await?;
        self.sessions.insert(session_id, session);
        Ok(())
    }

    pub(super) async fn take_terminal_restart_state(
        &mut self,
        session_id: &str,
        workspace_id: &str,
        tab_id: &str,
        max_bytes: usize,
    ) -> (Vec<u8>, u64) {
        if let Some(mut dead) = self.sessions.remove(session_id) {
            let scrollback = dead.buffer.to_bytes();
            let output_stream_bytes = dead.output_stream_range().1;
            dead.terminate(false, &self.store).await;
            self.agent_presence.remove(session_id);
            return (scrollback, output_stream_bytes);
        }
        if let Some(restored) = Session::restore_exited(
            session_id.to_string(),
            workspace_id.to_string(),
            tab_id.to_string(),
            &self.store,
            max_bytes,
        )
        .await
        {
            return (restored.buffer.to_bytes(), restored.output_stream_range().1);
        }
        (Vec::new(), 0)
    }

    fn schedule_terminal_startup_input(
        &self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_INPUT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupInput {
                session_id,
                session_instance_id,
                interactive_shell,
                command,
            });
        });
    }

    pub(super) fn handle_terminal_startup_input(
        &mut self,
        session_id: String,
        session_instance_id: u64,
        interactive_shell: String,
        command: String,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        let uses_paste = crate::terminal_host::orchestration::agent_prompt_injection::should_use_bracketed_paste_for_startup(&command)
            && crate::terminal_host::orchestration::agent_prompt_injection::shell_supports_bracketed_paste(&interactive_shell);
        let bytes = if uses_paste {
            crate::terminal_host::orchestration::agent_prompt_injection::build_agent_prompt_paste_bytes(&command)
        } else {
            crate::terminal_host::orchestration::agent_prompt_injection::build_plain_startup_command_bytes(&command)
        };
        let completion = if uses_paste {
            PtyWriteCompletion::StartupPaste {
                session_instance_id,
            }
        } else {
            PtyWriteCompletion::StartupPlain {
                session_instance_id,
            }
        };
        if let Err(error) = session.queue_write(completion, &bytes) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }

    pub(super) fn schedule_terminal_startup_submit(
        &self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(STARTUP_SUBMIT_DELAY_MS)).await;
            let _ = inbox.send(ServerCommand::TerminalStartupSubmit {
                session_id,
                session_instance_id,
            });
        });
    }

    pub(super) fn handle_terminal_startup_submit(
        &mut self,
        session_id: String,
        session_instance_id: u64,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        if session.instance_id() != session_instance_id || !session.running() {
            return;
        }
        if let Err(error) = session.queue_write(
            PtyWriteCompletion::StartupSubmit {
                session_instance_id,
            },
            crate::terminal_host::orchestration::agent_prompt_injection::AGENT_PROMPT_SUBMIT,
        ) {
            self.broadcast_terminal_error(&session_id, error.wire_message());
        }
    }
}

pub(super) async fn default_terminal_launch(
    working_directory: &str,
    login_shell: bool,
) -> DefaultTerminalLaunch {
    let environment = terminal_environment().await;
    #[cfg(windows)]
    let platform = TerminalPlatform::Windows;
    #[cfg(not(windows))]
    let platform = TerminalPlatform::Posix;
    let shell = match platform {
        TerminalPlatform::Windows => {
            std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
        }
        TerminalPlatform::Posix => std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string()),
    };
    default_terminal_launch_for(
        platform,
        working_directory,
        &shell,
        environment,
        login_shell,
    )
}

fn default_terminal_launch_for(
    platform: TerminalPlatform,
    working_directory: &str,
    interactive_shell: &str,
    environment: BTreeMap<String, String>,
    login_shell: bool,
) -> DefaultTerminalLaunch {
    match platform {
        TerminalPlatform::Windows => DefaultTerminalLaunch {
            interactive_shell: interactive_shell.to_string(),
            launch: TerminalHostLaunch {
                label: "shell".to_string(),
                shell: interactive_shell.to_string(),
                arguments: vec![
                    "/d".to_string(),
                    "/s".to_string(),
                    "/k".to_string(),
                    format!("cd /d {}", cmd_quote(working_directory)),
                ],
                environment,
            },
        },
        TerminalPlatform::Posix => {
            let mut exec_command = format!(
                "cd {} || true; exec {}",
                sh_quote(working_directory),
                sh_quote(interactive_shell)
            );
            if login_shell {
                for argument in login_shell_arguments(interactive_shell) {
                    exec_command.push(' ');
                    exec_command.push_str(&sh_quote(argument));
                }
            }
            DefaultTerminalLaunch {
                interactive_shell: interactive_shell.to_string(),
                launch: TerminalHostLaunch {
                    label: "shell".to_string(),
                    shell: "/bin/sh".to_string(),
                    arguments: vec!["-c".to_string(), exec_command],
                    environment,
                },
            }
        }
    }
}

async fn terminal_environment() -> BTreeMap<String, String> {
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if !cfg!(windows) {
        if let Some(path) = crate::login_shell_environment::login_shell_merged_path(
            environment.get("PATH").map(String::as_str),
        )
        .await
        {
            environment.insert("PATH".to_string(), path);
        }
        environment
            .entry("PATH".to_string())
            .or_insert_with(|| "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin".to_string());
        environment
            .entry("TERM".to_string())
            .or_insert_with(|| "xterm-256color".to_string());
    }
    environment
}

/// Flags that make `shell` read the login profile files (`~/.zprofile`,
/// `~/.profile`). Unknown shells are left alone rather than guessing a flag.
fn login_shell_arguments(shell: &str) -> &'static [&'static str] {
    let executable = shell.rsplit('/').next().unwrap_or(shell);
    match executable {
        "zsh" | "bash" | "sh" | "dash" | "ksh" | "ksh93" | "mksh" | "tcsh" | "csh" => &["-l"],
        "fish" | "nu" | "nushell" | "elvish" | "xonsh" => &["--login"],
        _ => &[],
    }
}

fn spawns_on_create(tab: &WorkspaceTabRecord) -> bool {
    tab.kind == "terminal"
        && tab.payload.get("spawnOnCreate").and_then(Value::as_bool) == Some(true)
}

fn terminal_session_id(tab: &WorkspaceTabRecord) -> String {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .unwrap_or(&tab.id)
        .to_string()
}

fn initial_command(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("initialCommand")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn cmd_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_launches_are_explicit_for_posix_and_windows() {
        let posix = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo's root",
            "/bin/zsh",
            BTreeMap::new(),
            false,
        );
        assert_eq!(posix.launch.shell, "/bin/sh");
        assert_eq!(
            posix.launch.arguments,
            ["-c", "cd '/repo'\\''s root' || true; exec '/bin/zsh'"]
        );
        assert_eq!(posix.interactive_shell, "/bin/zsh");

        let windows = default_terminal_launch_for(
            TerminalPlatform::Windows,
            r#"C:\repo "main""#,
            "cmd.exe",
            BTreeMap::new(),
            false,
        );
        assert_eq!(windows.launch.shell, "cmd.exe");
        assert_eq!(
            windows.launch.arguments,
            ["/d", "/s", "/k", r#"cd /d "C:\repo ""main""""#]
        );
    }

    #[test]
    fn posix_login_launch_adds_the_shell_login_flag() {
        let zsh = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/bin/zsh",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            zsh.launch.arguments,
            ["-c", "cd '/repo' || true; exec '/bin/zsh' '-l'"]
        );

        let fish = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/opt/homebrew/bin/fish",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            fish.launch.arguments,
            [
                "-c",
                "cd '/repo' || true; exec '/opt/homebrew/bin/fish' '--login'"
            ]
        );
    }

    #[test]
    fn unknown_login_shells_keep_their_default_arguments() {
        let launch = default_terminal_launch_for(
            TerminalPlatform::Posix,
            "/repo",
            "/usr/local/bin/exoticsh",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            launch.launch.arguments,
            ["-c", "cd '/repo' || true; exec '/usr/local/bin/exoticsh'"]
        );
    }

    #[test]
    fn windows_launch_ignores_the_login_shell_flag() {
        let windows = default_terminal_launch_for(
            TerminalPlatform::Windows,
            r"C:\repo",
            "cmd.exe",
            BTreeMap::new(),
            true,
        );
        assert_eq!(
            windows.launch.arguments,
            ["/d", "/s", "/k", r#"cd /d "C:\repo""#]
        );
    }
}
