use alera_provider_protocol::{
    InteractionMode, McpServerSpec, McpTransport, ProviderError, RuntimeMode, SessionStartInput,
    TurnInput,
};
use opencode_agent_sdk::{ClientConfig, Generation, McpServerConfig, OpenCodeServerConfig};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenCodeGeneration {
    Legacy1,
    V2,
}

impl From<OpenCodeGeneration> for Generation {
    fn from(value: OpenCodeGeneration) -> Self {
        match value {
            OpenCodeGeneration::Legacy1 => Generation::Legacy1,
            OpenCodeGeneration::V2 => Generation::V2,
        }
    }
}

#[derive(Debug, Clone)]
pub struct OpenCodeProviderConfig {
    pub provider_instance_id: String,
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub server_url: Option<String>,
    pub server_password: Option<String>,
    pub directory: Option<PathBuf>,
    pub generation: OpenCodeGeneration,
    pub model: Option<String>,
    pub request_timeout: Duration,
    pub max_sse_event_bytes: usize,
}

/// Configuration-level feature support used by provider factories and catalogs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpenCodeConfigSupport {
    pub mcp_stdio: bool,
    pub mcp_http: bool,
    pub external_mcp_injection: bool,
}

impl Default for OpenCodeProviderConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: "opencode".into(),
            executable: PathBuf::from("opencode"),
            args: vec![OsString::from("serve")],
            cwd: None,
            env: BTreeMap::new(),
            server_url: None,
            server_password: None,
            directory: None,
            generation: OpenCodeGeneration::V2,
            model: None,
            request_timeout: Duration::from_secs(120),
            max_sse_event_bytes: 4 * 1024 * 1024,
        }
    }
}

impl OpenCodeProviderConfig {
    pub fn support_table(&self) -> OpenCodeConfigSupport {
        let local = self.server_url.is_none();
        OpenCodeConfigSupport {
            mcp_stdio: local,
            mcp_http: local,
            external_mcp_injection: false,
        }
    }

    pub fn client_config(&self) -> ClientConfig {
        ClientConfig {
            base_url: self
                .server_url
                .clone()
                .unwrap_or_else(|| "http://127.0.0.1:4096".into()),
            directory: self
                .directory
                .as_ref()
                .map(|directory| directory.to_string_lossy().into_owned()),
            password: self.server_password.clone(),
            generation: self.generation.into(),
            max_sse_event_bytes: self.max_sse_event_bytes,
        }
    }

    pub fn process_args(&self) -> Vec<OsString> {
        if self.args.is_empty() {
            vec![OsString::from("serve")]
        } else {
            self.args.clone()
        }
    }

    pub fn local_server_config(&self) -> OpenCodeServerConfig {
        OpenCodeServerConfig {
            executable: self.executable.clone(),
            args: self.process_args(),
            cwd: self.cwd.clone(),
            env: self.env.clone(),
            password: self.server_password.clone(),
            generation: self.generation.into(),
            max_frame_bytes: self.max_sse_event_bytes,
            shutdown_timeout: self.request_timeout.min(Duration::from_secs(30)),
            ..OpenCodeServerConfig::default()
        }
    }
}

pub type OpenCodeConfig = OpenCodeProviderConfig;

pub(crate) fn mcp_config(server: &McpServerSpec) -> McpServerConfig {
    match &server.transport {
        McpTransport::Stdio {
            command,
            args,
            env,
            cwd,
        } => {
            let mut command_line = Vec::with_capacity(args.len() + 1);
            command_line.push(command.to_string_lossy().into_owned());
            command_line.extend(args.iter().cloned());
            McpServerConfig::Local {
                command: command_line,
                cwd: cwd.as_ref().map(|path| path.to_string_lossy().into_owned()),
                environment: env.clone(),
            }
        }
        McpTransport::Http { url, headers } => McpServerConfig::Remote {
            url: url.clone(),
            headers: headers.clone(),
        },
    }
}

pub(crate) fn map_open_code_error(error: opencode_agent_sdk::OpenCodeError) -> ProviderError {
    match error {
        opencode_agent_sdk::OpenCodeError::Closed => ProviderError::Closed,
        opencode_agent_sdk::OpenCodeError::Timeout { operation } => {
            ProviderError::Timeout { operation }
        }
        opencode_agent_sdk::OpenCodeError::Unsupported(operation) => {
            ProviderError::Unsupported(operation)
        }
        other => ProviderError::Protocol(other.to_string()),
    }
}

pub(crate) fn validate_session_options(input: &SessionStartInput) -> Result<(), ProviderError> {
    if input.runtime_mode != RuntimeMode::ApprovalRequired {
        return Err(ProviderError::Unsupported(
            "OpenCode runtime mode policy is not implemented".into(),
        ));
    }
    if input.approval_policy.is_some() {
        return Err(ProviderError::Unsupported(
            "OpenCode approval policy options are not implemented".into(),
        ));
    }
    if input.sandbox_mode.is_some() {
        return Err(ProviderError::Unsupported(
            "OpenCode sandbox policy options are not implemented".into(),
        ));
    }
    if let Some(key) = input.options.keys().next() {
        return Err(ProviderError::Unsupported(format!(
            "OpenCode session option `{key}` is not implemented"
        )));
    }
    Ok(())
}

pub(crate) fn validate_turn_options(input: &TurnInput) -> Result<(), ProviderError> {
    if input.interaction_mode == InteractionMode::Plan {
        return Err(ProviderError::Unsupported(
            "OpenCode plan interaction requires a provider-native plan command".into(),
        ));
    }
    if let Some(key) = input.options.keys().next() {
        return Err(ProviderError::Unsupported(format!(
            "OpenCode turn option `{key}` is not implemented"
        )));
    }
    Ok(())
}

pub(crate) fn prompt_parts(input: &TurnInput) -> Result<Vec<Value>, ProviderError> {
    let mut parts = Vec::new();
    if !input.input.trim().is_empty() {
        parts.push(json!({ "type": "text", "text": input.input }));
    }
    for attachment in &input.attachments {
        match attachment {
            alera_provider_protocol::Attachment::Image { url } => parts.push(json!({
                "type": "file",
                "url": url,
                "mime": "image/*"
            })),
            alera_provider_protocol::Attachment::LocalImage { .. }
            | alera_provider_protocol::Attachment::File { .. } => {
                return Err(ProviderError::Unsupported(
                    "OpenCode adapter only supports URL image attachments".into(),
                ))
            }
        }
    }
    if parts.is_empty() {
        return Err(ProviderError::Validation(
            "OpenCode turn requires text or a URL image".into(),
        ));
    }
    Ok(parts)
}
