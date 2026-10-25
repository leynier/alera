use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

use async_trait::async_trait;

use super::agent_command_runner::SystemAgentCommandRunner;
use super::CleanupFailure;

/// Variables that relocate an agent's storage. Read through the login shell
/// because the host starts detached and would otherwise miss rc exports.
const STORAGE_VARIABLES: [&str; 9] = [
    "CLAUDE_CONFIG_DIR",
    "CCS_DIR",
    "CODEX_HOME",
    "XDG_DATA_HOME",
    "COPILOT_HOME",
    "CURSOR_DATA_DIR",
    "GROK_HOME",
    "PI_CODING_AGENT_DIR",
    "PI_CODING_AGENT_SESSION_DIR",
];

/// Spawns one agent CLI to completion. Injected so tests never run a real one.
#[async_trait]
pub(super) trait AgentCommandRunner: Send + Sync {
    async fn run(
        &self,
        program: &str,
        args: &[String],
        env: &BTreeMap<String, String>,
    ) -> Result<(), String>;
}

/// Everything the cleanup reads from the machine, resolved once up front.
#[derive(Clone)]
pub(super) struct CleanupContext {
    pub home: PathBuf,
    variables: BTreeMap<String, String>,
    runner: Arc<dyn AgentCommandRunner>,
    pub process_alive: fn(u32) -> bool,
}

impl CleanupContext {
    pub async fn resolve() -> Option<Self> {
        let home = dirs::home_dir()?;
        let mut variables = BTreeMap::new();
        for name in STORAGE_VARIABLES {
            if let Some(value) = crate::login_shell_environment::login_shell_variable(name).await {
                variables.insert(name.to_string(), value);
            }
        }
        Some(Self::new(
            home,
            variables,
            Arc::new(SystemAgentCommandRunner),
            crate::terminal_host::session::process_alive,
        ))
    }

    pub fn new(
        home: PathBuf,
        variables: BTreeMap<String, String>,
        runner: Arc<dyn AgentCommandRunner>,
        process_alive: fn(u32) -> bool,
    ) -> Self {
        Self {
            home,
            variables,
            runner,
            process_alive,
        }
    }

    pub fn variable(&self, name: &str) -> Option<&str> {
        self.variables
            .get(name)
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
    }

    /// A directory variable with a leading `~` expanded, as the agents do.
    pub fn directory_variable(&self, name: &str) -> Option<PathBuf> {
        let value = self.variable(name)?;
        if value == "~" {
            return Some(self.home.clone());
        }
        if let Some(rest) = value
            .strip_prefix("~/")
            .or_else(|| value.strip_prefix("~\\"))
        {
            return Some(self.home.join(rest));
        }
        Some(PathBuf::from(value))
    }

    /// `name` from the environment, else `default` under the home directory.
    pub fn directory_or_home(&self, name: &str, default: &[&str]) -> PathBuf {
        self.directory_variable(name).unwrap_or_else(|| {
            default
                .iter()
                .fold(self.home.clone(), |path, part| path.join(part))
        })
    }

    /// The storage variables this agent reads, passed explicitly so the
    /// spawned CLI resolves the same store this cleanup inspected.
    pub fn storage_env(&self, names: &[&str]) -> BTreeMap<String, String> {
        names
            .iter()
            .filter_map(|name| Some((name.to_string(), self.variable(name)?.to_string())))
            .collect()
    }

    pub async fn run_command(
        &self,
        program: &str,
        args: &[&str],
        env: &BTreeMap<String, String>,
    ) -> Result<(), CleanupFailure> {
        let args = args.iter().map(|arg| arg.to_string()).collect::<Vec<_>>();
        self.runner
            .run(program, &args, env)
            .await
            .map_err(|detail| CleanupFailure::new("command_failed", detail))
    }
}
