use alera_agent_transport::{ProcessConfig, DEFAULT_MAX_FRAME_BYTES, DEFAULT_SHUTDOWN_TIMEOUT};
use alera_provider_protocol::{ProviderKind, RuntimeMode};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum AcpFlavor {
    #[default]
    Generic,
    Grok,
    Antigravity,
    Registry,
}

#[derive(Debug, Clone)]
pub struct AcpSpawnConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
}

impl Default for AcpSpawnConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("agent"),
            args: Vec::new(),
            cwd: None,
            env: BTreeMap::new(),
            max_frame_bytes: DEFAULT_MAX_FRAME_BYTES,
            shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
        }
    }
}

impl From<AcpSpawnConfig> for ProcessConfig {
    fn from(config: AcpSpawnConfig) -> Self {
        Self {
            executable: config.executable,
            args: config.args,
            cwd: config.cwd,
            env: config.env,
            max_frame_bytes: config.max_frame_bytes,
            shutdown_timeout: config.shutdown_timeout,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AcpProviderConfig {
    pub provider: ProviderKind,
    pub provider_instance_id: String,
    pub process: ProcessConfig,
    pub client_name: String,
    pub client_version: String,
    pub auth_method: Option<String>,
    pub authenticate_eagerly: bool,
    pub flavor: AcpFlavor,
    pub runtime_mode: RuntimeMode,
    pub request_timeout: Duration,
    pub max_queued_events: usize,
    pub session_mode: Option<String>,
}

impl Default for AcpProviderConfig {
    fn default() -> Self {
        Self {
            provider: ProviderKind::Other("acp".into()),
            provider_instance_id: "acp-default".into(),
            process: AcpSpawnConfig::default().into(),
            client_name: "alera".into(),
            client_version: env!("CARGO_PKG_VERSION").into(),
            auth_method: None,
            authenticate_eagerly: false,
            flavor: AcpFlavor::Generic,
            runtime_mode: RuntimeMode::ApprovalRequired,
            request_timeout: Duration::from_secs(120),
            max_queued_events: 1024,
            session_mode: None,
        }
    }
}

impl AcpProviderConfig {
    pub fn with_process(mut self, process: ProcessConfig) -> Self {
        self.process = process;
        self
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.provider_instance_id.trim().is_empty() {
            return Err("providerInstanceId must not be empty".into());
        }
        if self.client_name.trim().is_empty() {
            return Err("clientName must not be empty".into());
        }
        if self.process.executable.as_os_str().is_empty() {
            return Err("executable must not be empty".into());
        }
        Ok(())
    }
}
