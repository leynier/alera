//! What skill discovery reads from the launch configuration: the session cwd,
//! the environment the CLI is spawned with, and its additional directories.

use super::paths::{join, resolve};
use claude_agent_sdk::ClaudeAgentOptions;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Owned so a send can move it onto a blocking thread.
#[derive(Debug, Clone, Default)]
pub(crate) struct SkillEnvironment {
    cwd: Option<PathBuf>,
    env: BTreeMap<String, String>,
    add_dirs: Vec<String>,
}

impl SkillEnvironment {
    /// T3 Code reads one `--add-dir` from its launch args. Here every
    /// directory the CLI receives counts: each `add_dirs` entry, then an
    /// `add-dir` extra argument, in the order the SDK passes them.
    pub fn new(options: &ClaudeAgentOptions, cwd: Option<&Path>) -> Self {
        let add_dirs = options
            .add_dirs
            .iter()
            .map(|directory| directory.to_string_lossy().into_owned())
            .chain(options.extra_args.get("add-dir").cloned().flatten())
            .collect();
        Self {
            cwd: cwd.map(Path::to_path_buf),
            env: options.env.clone(),
            add_dirs,
        }
    }

    pub fn cwd(&self) -> Option<&Path> {
        self.cwd.as_deref()
    }

    pub fn add_dirs(&self) -> &[String] {
        &self.add_dirs
    }

    /// The spawned CLI sees the options environment over the process one.
    pub fn var(&self, key: &str) -> Option<String> {
        self.env
            .get(key)
            .cloned()
            .or_else(|| std::env::var(key).ok())
    }

    /// The home the spawned CLI resolves `~/.claude` against.
    pub fn home(&self) -> Option<PathBuf> {
        let key = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
        self.var(key)
            .filter(|home| !home.is_empty())
            .map(PathBuf::from)
            .or_else(process_home)
    }

    /// `resolveClaudeConfigDirPath`: a relative `CLAUDE_CONFIG_DIR` is taken
    /// against the cwd and a literal `~` is kept, as the spawned CLI does.
    pub fn config_dir(&self) -> Option<PathBuf> {
        if let Some(configured) = self.var("CLAUDE_CONFIG_DIR") {
            let configured = configured.trim();
            if !configured.is_empty() {
                return Some(resolve(self.cwd(), Path::new(configured)));
            }
        }
        Some(join(&self.home()?, &[".claude"]))
    }

    /// `expandHomePath`: spawned processes treat `~/` as relative otherwise.
    pub fn expand_home(&self, value: &str) -> PathBuf {
        let Some(home) = self.home() else {
            return PathBuf::from(value);
        };
        if value == "~" {
            return home;
        }
        match value
            .strip_prefix("~/")
            .or_else(|| value.strip_prefix("~\\"))
        {
            Some(rest) => join(&home, &[rest]),
            None => PathBuf::from(value),
        }
    }
}

#[allow(deprecated)]
fn process_home() -> Option<PathBuf> {
    std::env::home_dir()
}
