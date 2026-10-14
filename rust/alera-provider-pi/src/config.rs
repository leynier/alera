use alera_agent_transport::{ProcessConfig, DEFAULT_MAX_FRAME_BYTES, DEFAULT_SHUTDOWN_TIMEOUT};
use alera_provider_protocol::{ApprovalPolicy, McpServerSpec, RuntimeMode, SandboxMode};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

/// Configuration for a Pi RPC process or an injected transport.
#[derive(Clone, Debug)]
pub struct PiProviderConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub instance_id: String,
    pub model: Option<String>,
    pub runtime_mode: RuntimeMode,
    pub approval_policy: Option<ApprovalPolicy>,
    pub sandbox_mode: Option<SandboxMode>,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
    pub request_timeout: Duration,
    pub max_queued_events: usize,
    /// Stdio MCP servers are materialized into the Pi extension before spawn.
    /// SessionStartInput carries the same list as host-owned, non-serialized
    /// metadata and is checked against this launch-time list.
    pub mcp_servers: Vec<McpServerSpec>,
}

impl Default for PiProviderConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("pi"),
            args: vec![OsString::from("--mode"), OsString::from("rpc")],
            cwd: None,
            env: BTreeMap::new(),
            instance_id: "pi-default".into(),
            model: None,
            runtime_mode: RuntimeMode::ApprovalRequired,
            approval_policy: None,
            sandbox_mode: None,
            max_frame_bytes: DEFAULT_MAX_FRAME_BYTES,
            shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
            request_timeout: Duration::from_secs(30),
            max_queued_events: 1024,
            mcp_servers: Vec::new(),
        }
    }
}

impl PiProviderConfig {
    pub(crate) fn validate_launch(&self) -> Result<(), String> {
        if self.executable.as_os_str().is_empty() {
            return Err("Pi executable must not be empty".into());
        }
        if self.max_frame_bytes == 0 {
            return Err("Pi max_frame_bytes must be greater than zero".into());
        }
        if self.max_queued_events == 0 {
            return Err("Pi max_queued_events must be greater than zero".into());
        }
        if let Some(mode_index) = self.args.iter().position(|arg| arg == "--mode") {
            if self.args.get(mode_index + 1).and_then(|arg| arg.to_str()) != Some("rpc") {
                return Err("Pi must be launched with --mode rpc".into());
            }
        }
        if self.instance_id.trim().is_empty() {
            return Err("Pi instance_id must not be empty".into());
        }
        if self.request_timeout.is_zero() {
            return Err("Pi request_timeout must be greater than zero".into());
        }
        for server in &self.mcp_servers {
            server
                .validate()
                .map_err(|error| format!("invalid Pi MCP server: {error}"))?;
        }
        Ok(())
    }

    pub(crate) fn process_config(&self) -> ProcessConfig {
        let mut args = self.args.clone();
        if !args
            .windows(2)
            .any(|window| window[0] == "--mode" && window[1] == "rpc")
        {
            args.extend([OsString::from("--mode"), OsString::from("rpc")]);
        }
        ProcessConfig {
            executable: self.executable.clone(),
            args,
            cwd: self.cwd.clone(),
            env: self.env.clone(),
            max_frame_bytes: self.max_frame_bytes,
            shutdown_timeout: self.shutdown_timeout,
        }
    }
}

/// Short provider-specific alias retained for callers that prefer `PiConfig`.
pub type PiConfig = PiProviderConfig;
