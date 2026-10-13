use crate::{error::nonempty, ProviderError};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fmt, path::PathBuf};

/// Host-provided tool server configuration. Credentials belong in private
/// files or environment entries, never in client-facing chat snapshots.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServerSpec {
    pub name: String,
    #[serde(flatten)]
    pub transport: McpTransport,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "transport", rename_all = "camelCase")]
pub enum McpTransport {
    Stdio {
        command: PathBuf,
        #[serde(default)]
        args: Vec<String>,
        #[serde(default)]
        env: BTreeMap<String, String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        cwd: Option<PathBuf>,
    },
    Http {
        url: String,
        #[serde(default)]
        headers: BTreeMap<String, String>,
    },
}

impl fmt::Debug for McpServerSpec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("McpServerSpec")
            .field("name", &self.name)
            .field("transport", &self.transport)
            .finish()
    }
}

impl fmt::Debug for McpTransport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Stdio { command, env, .. } => f
                .debug_struct("Stdio")
                .field("command", command)
                .field("env_keys", &env.keys().collect::<Vec<_>>())
                .finish_non_exhaustive(),
            Self::Http { headers, .. } => f
                .debug_struct("Http")
                .field("header_keys", &headers.keys().collect::<Vec<_>>())
                .finish_non_exhaustive(),
        }
    }
}

impl McpServerSpec {
    pub fn validate(&self) -> Result<(), ProviderError> {
        nonempty(&self.name, "MCP server name")?;
        if self.name.len() > 128
            || !self
                .name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'))
        {
            return Err(ProviderError::Validation("invalid MCP server name".into()));
        }
        match &self.transport {
            McpTransport::Stdio { command, env, .. } => {
                if command.as_os_str().is_empty() {
                    return Err(ProviderError::Validation("empty MCP command".into()));
                }
                if env
                    .keys()
                    .any(|key| key.is_empty() || key.contains('=') || key.contains('\0'))
                    || env.values().any(|value| value.contains('\0'))
                {
                    return Err(ProviderError::Validation("invalid MCP environment".into()));
                }
            }
            McpTransport::Http { url, headers } => {
                if !(url.starts_with("http://") || url.starts_with("https://"))
                    || url.chars().any(char::is_whitespace)
                {
                    return Err(ProviderError::Validation("invalid MCP HTTP URL".into()));
                }
                if headers.iter().any(|(key, value)| {
                    key.trim().is_empty()
                        || key.chars().any(|c| c.is_control() || c.is_whitespace())
                        || value.chars().any(char::is_control)
                }) {
                    return Err(ProviderError::Validation("invalid MCP HTTP headers".into()));
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct McpInjectionCapabilities {
    pub stdio: bool,
    pub http: bool,
}

impl McpInjectionCapabilities {
    pub fn is_empty(&self) -> bool {
        !self.stdio && !self.http
    }

    pub fn supports(&self, server: &McpServerSpec) -> bool {
        match server.transport {
            McpTransport::Stdio { .. } => self.stdio,
            McpTransport::Http { .. } => self.http,
        }
    }
}
