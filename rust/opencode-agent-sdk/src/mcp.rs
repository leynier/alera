use crate::{wire::percent_encode, Generation, HttpTransport, OpenCodeClient, OpenCodeError};
use serde_json::{json, Value};
use std::{collections::BTreeMap, fmt};

/// Runtime MCP configuration accepted by the public server APIs.
#[derive(Clone, PartialEq, Eq)]
pub enum McpServerConfig {
    Local {
        command: Vec<String>,
        cwd: Option<String>,
        environment: BTreeMap<String, String>,
    },
    Remote {
        url: String,
        headers: BTreeMap<String, String>,
    },
}

impl fmt::Debug for McpServerConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Local {
                command,
                environment,
                ..
            } => f
                .debug_struct("Local")
                .field("command", &command.first())
                .field("env_keys", &environment.keys().collect::<Vec<_>>())
                .finish_non_exhaustive(),
            Self::Remote { headers, .. } => f
                .debug_struct("Remote")
                .field("header_keys", &headers.keys().collect::<Vec<_>>())
                .finish_non_exhaustive(),
        }
    }
}

/// Native MCP namespaces use JavaScript's `/[^a-zA-Z0-9_-]/g` replacement.
pub fn normalized_mcp_server_name(name: &str) -> String {
    name.encode_utf16()
        .map(|unit| match unit {
            48..=57 | 65..=90 | 97..=122 | 95 | 45 => char::from(unit as u8),
            _ => '_',
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct PermissionRule {
    pub action: String,
    pub resource: String,
    pub effect: String,
}

impl McpServerConfig {
    fn wire(&self) -> Value {
        match self {
            Self::Local {
                command,
                cwd,
                environment,
            } => {
                let mut value = json!({
                    "type": "local",
                    "command": command,
                    "environment": environment,
                });
                if let Some(cwd) = cwd {
                    value["cwd"] = Value::String(cwd.clone());
                }
                value
            }
            Self::Remote { url, headers } => json!({
                "type": "remote",
                "url": url,
                "headers": headers,
                "oauth": false,
            }),
        }
    }
}

impl<T: HttpTransport> OpenCodeClient<T> {
    /// Reads configured names, including disabled servers, without changing them.
    pub async fn mcp_server_names(&mut self) -> Result<Vec<String>, OpenCodeError> {
        let body = self.raw_request("GET", "/mcp", None).await?.body;
        let malformed = || OpenCodeError::protocol("invalid OpenCode MCP list response");
        match self.config().generation {
            Generation::Legacy1 => {
                let servers = body.as_object().ok_or_else(malformed)?;
                for status in servers.values() {
                    if status.get("status").and_then(Value::as_str).is_none() {
                        return Err(malformed());
                    }
                }
                // serde_json's key order follows workspace feature unification
                // (`preserve_order`), so sort to keep the list deterministic.
                let mut names: Vec<String> = servers.keys().cloned().collect();
                names.sort();
                Ok(names)
            }
            Generation::V2 => {
                if body
                    .get("location")
                    .and_then(|location| location.get("directory"))
                    .and_then(Value::as_str)
                    .is_none()
                {
                    return Err(malformed());
                }
                let servers = body
                    .get("data")
                    .and_then(Value::as_array)
                    .ok_or_else(malformed)?;
                servers
                    .iter()
                    .map(|server| {
                        if server
                            .get("status")
                            .and_then(|status| status.get("status"))
                            .and_then(Value::as_str)
                            .is_none()
                        {
                            return Err(malformed());
                        }
                        let name = server
                            .get("name")
                            .and_then(Value::as_str)
                            .ok_or_else(malformed)?;
                        if name.is_empty() {
                            return Err(malformed());
                        }
                        Ok(name.to_owned())
                    })
                    .collect()
            }
        }
    }

    /// Registers an MCP server in the process or directory scope used by this client.
    pub async fn add_mcp_server(
        &mut self,
        name: &str,
        config: McpServerConfig,
    ) -> Result<Value, OpenCodeError> {
        if name.trim().is_empty() {
            return Err(OpenCodeError::protocol("MCP server name is empty"));
        }
        let config = config.wire();
        let (path, body) = match self.config().generation {
            Generation::Legacy1 => ("/mcp".to_owned(), json!({ "name": name, "config": config })),
            Generation::V2 => (
                format!("/experimental/mcp/{}", percent_encode(name)),
                json!({ "config": config }),
            ),
        };
        let method = if self.config().generation == Generation::V2 {
            "PUT"
        } else {
            "POST"
        };
        Ok(self.raw_request(method, &path, Some(body)).await?.body)
    }

    /// Removes a previously registered MCP server from the client scope.
    pub async fn remove_mcp_server(&mut self, name: &str) -> Result<Value, OpenCodeError> {
        if name.trim().is_empty() {
            return Err(OpenCodeError::protocol("MCP server name is empty"));
        }
        let encoded = percent_encode(name);
        let (method, path) = match self.config().generation {
            Generation::Legacy1 => ("POST", format!("/mcp/{encoded}/disconnect")),
            Generation::V2 => ("DELETE", format!("/experimental/mcp/{encoded}")),
        };
        Ok(self.raw_request(method, &path, None).await?.body)
    }

    pub async fn update_session_permissions(
        &mut self,
        session_id: &str,
        rules: Vec<PermissionRule>,
    ) -> Result<Value, OpenCodeError> {
        if self.config().generation == Generation::Legacy1 {
            return Err(OpenCodeError::Unsupported(
                "session permission rules are only available in OpenCode V2".into(),
            ));
        }
        Ok(self
            .raw_request(
                "PATCH",
                &format!("/session/{session_id}"),
                Some(json!({ "permissions": rules })),
            )
            .await?
            .body)
    }
}
