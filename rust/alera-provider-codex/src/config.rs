use alera_agent_transport::{ProcessConfig, DEFAULT_SHUTDOWN_TIMEOUT};
use alera_provider_protocol::{ApprovalPolicy, SandboxMode};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

/// Codex app-server frames carry base64 images and whole diffs, so they get
/// the same 128 MiB ceiling T3 Code uses instead of the shared 4 MiB default.
pub const CODEX_MAX_FRAME_BYTES: usize = 128 * 1024 * 1024;

/// Configuration for one Codex app-server connection.
#[derive(Clone, Debug)]
pub struct CodexProviderConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub instance_id: String,
    pub client_name: String,
    pub client_title: String,
    pub client_version: String,
    pub model: Option<String>,
    pub approval_policy: Option<ApprovalPolicy>,
    pub sandbox_mode: Option<SandboxMode>,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
    pub request_timeout: Duration,
    pub max_queued_events: usize,
}

impl Default for CodexProviderConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("codex"),
            args: vec![OsString::from("app-server")],
            cwd: None,
            env: BTreeMap::new(),
            instance_id: String::from("codex-default"),
            client_name: String::from("alera"),
            client_title: String::from("Alera"),
            client_version: env!("CARGO_PKG_VERSION").to_owned(),
            model: None,
            approval_policy: None,
            sandbox_mode: None,
            max_frame_bytes: CODEX_MAX_FRAME_BYTES,
            shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
            request_timeout: Duration::from_secs(120),
            max_queued_events: 1024,
        }
    }
}

impl CodexProviderConfig {
    pub(crate) fn process_config(&self) -> ProcessConfig {
        let mut env = self.env.clone();
        env.entry(OsString::from("CODEX_INTERNAL_ORIGINATOR_OVERRIDE"))
            .or_insert_with(|| {
                let name = self.client_name.trim();
                OsString::from(if name.is_empty() { "alera" } else { name })
            });
        ProcessConfig {
            executable: self.executable.clone(),
            args: self.args.clone(),
            cwd: self.cwd.clone(),
            env,
            max_frame_bytes: self.max_frame_bytes,
            shutdown_timeout: self.shutdown_timeout,
        }
    }

    pub(crate) fn client_info(&self) -> serde_json::Value {
        serde_json::json!({
            "name": self.client_name,
            "title": self.client_title,
            "version": self.client_version,
        })
    }
}

/// Short name retained for callers that prefer a provider-specific config type.
pub type CodexConfig = CodexProviderConfig;

impl From<CodexProviderConfig> for ProcessConfig {
    fn from(config: CodexProviderConfig) -> Self {
        config.process_config()
    }
}
