use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;
use std::collections::BTreeMap;

use crate::models::ModelSelection;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UserMessage {
    pub text: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub images: Vec<SdkImage>,
}

#[derive(Debug, Clone)]
pub enum SdkImage {
    Url { url: String },
    Data { data: String, mime_type: String },
}

impl Serialize for SdkImage {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Url { url } => serde_json::json!({ "url": { "url": url } }).serialize(serializer),
            Self::Data { data, mime_type } => serde_json::json!({
                "data": { "data": data, "mimeType": mime_type }
            })
            .serialize(serializer),
        }
    }
}

impl<'de> Deserialize<'de> for SdkImage {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = Value::deserialize(deserializer)?;
        if let Some(url) = value
            .get("url")
            .and_then(|value| value.get("url"))
            .and_then(Value::as_str)
        {
            return Ok(Self::Url {
                url: url.to_owned(),
            });
        }
        let data = value
            .get("data")
            .and_then(|value| value.get("data"))
            .and_then(Value::as_str)
            .ok_or_else(|| serde::de::Error::custom("image requires url or data"))?;
        let mime_type = value
            .get("data")
            .and_then(|value| value.get("mimeType"))
            .and_then(Value::as_str)
            .unwrap_or("application/octet-stream")
            .to_owned();
        Ok(Self::Data {
            data: data.to_owned(),
            mime_type,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McpServerConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stdio: Option<StdioMcpServerConfig>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http: Option<HttpMcpServerConfig>,
}

#[derive(Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct StdioMcpServerConfig {
    pub command: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub args: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub cwd: String,
}

impl std::fmt::Debug for StdioMcpServerConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("StdioMcpServerConfig")
            .field("command", &self.command)
            .field("env_keys", &self.env.keys().collect::<Vec<_>>())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HttpMcpTransportType {
    Http,
    Sse,
    Unspecified,
}

impl Serialize for HttpMcpTransportType {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(match self {
            Self::Http => "HTTP_MCP_TRANSPORT_TYPE_HTTP",
            Self::Sse => "HTTP_MCP_TRANSPORT_TYPE_SSE",
            Self::Unspecified => "HTTP_MCP_TRANSPORT_TYPE_UNSPECIFIED",
        })
    }
}

impl<'de> Deserialize<'de> for HttpMcpTransportType {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(match String::deserialize(deserializer)?.as_str() {
            "HTTP_MCP_TRANSPORT_TYPE_HTTP" => Self::Http,
            "HTTP_MCP_TRANSPORT_TYPE_SSE" => Self::Sse,
            _ => Self::Unspecified,
        })
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HttpMcpServerConfig {
    #[serde(rename = "type")]
    pub transport_type: HttpMcpTransportType,
    pub url: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub headers: BTreeMap<String, String>,
}

impl std::fmt::Debug for HttpMcpServerConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpMcpServerConfig")
            .field("transport_type", &self.transport_type)
            .field("header_keys", &self.headers.keys().collect::<Vec<_>>())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LocalAgentOptions {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cwd: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sandbox_options: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_review: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AgentOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<ModelSelection>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub api_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub local: Option<LocalAgentOptions>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<AgentMode>,
    #[serde(rename = "mcpServers", skip_serializing_if = "Option::is_none")]
    pub mcp_servers: Option<BTreeMap<String, McpServerConfig>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SendOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<ModelSelection>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enable_deltas: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enable_steps: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<AgentMode>,
    #[serde(rename = "mcpServers", skip_serializing_if = "Option::is_none")]
    pub mcp_servers: Option<BTreeMap<String, McpServerConfig>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AgentMode {
    Agent,
    Plan,
    Unknown(String),
}

impl Serialize for AgentMode {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let value = match self {
            Self::Agent => "AGENT_MODE_OPTION_AGENT",
            Self::Plan => "AGENT_MODE_OPTION_PLAN",
            Self::Unknown(value) => value,
        };
        serializer.serialize_str(value)
    }
}

impl<'de> Deserialize<'de> for AgentMode {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = String::deserialize(deserializer)?;
        Ok(match value.as_str() {
            "AGENT_MODE_OPTION_AGENT" => Self::Agent,
            "AGENT_MODE_OPTION_PLAN" => Self::Plan,
            _ => Self::Unknown(value),
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateAgentResponse {
    pub agent_id: String,
    #[serde(default)]
    pub model: Option<ModelSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResumeAgentResponse {
    pub agent_id: String,
    #[serde(default)]
    pub model: Option<ModelSelection>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RunStreamMessage {
    #[serde(default)]
    pub sdk_message: Option<Value>,
    #[serde(default)]
    pub result: Option<Value>,
    #[serde(default)]
    pub done: Option<Value>,
    #[serde(default)]
    pub interaction_update: Option<Value>,
    #[serde(default)]
    pub step: Option<Value>,
    #[serde(default)]
    pub offset: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

impl RunStreamMessage {
    pub fn is_empty_envelope(&self) -> bool {
        self.sdk_message.is_none()
            && self.result.is_none()
            && self.done.is_none()
            && self.interaction_update.is_none()
            && self.step.is_none()
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadyHandshake {
    pub schema_version: u64,
    pub server_version: String,
    pub pid: Option<u64>,
    pub transport: String,
    pub protocol: String,
    pub host: String,
    pub port: u16,
    pub url: Option<String>,
    pub auth_token_file: Option<String>,
    pub auth_token: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

impl std::fmt::Debug for ReadyHandshake {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ReadyHandshake")
            .field("schema_version", &self.schema_version)
            .field("server_version", &self.server_version)
            .field("pid", &self.pid)
            .field("transport", &self.transport)
            .field("protocol", &self.protocol)
            .field("host", &self.host)
            .field("port", &self.port)
            .field("url", &self.url)
            .field("auth_token_file", &self.auth_token_file)
            .field(
                "auth_token",
                &self.auth_token.as_ref().map(|_| "<redacted>"),
            )
            .field("extra", &"<omitted>")
            .finish()
    }
}

impl ReadyHandshake {
    pub const PREFIX: &'static str = "cursor-sdk-bridge ready ";

    /// Parse one stderr line without retaining or logging the bearer token.
    pub fn parse_line(line: &str) -> Option<Result<Self, crate::CursorSdkError>> {
        let payload = line.strip_prefix(Self::PREFIX)?;
        Some(Self::parse_payload(payload))
    }

    fn parse_payload(payload: &str) -> Result<Self, crate::CursorSdkError> {
        let value: Value = serde_json::from_str(payload.trim())
            .map_err(|error| crate::CursorSdkError::Handshake(format!("ready JSON: {error}")))?;
        let handshake: Self = serde_json::from_value(value)
            .map_err(|error| crate::CursorSdkError::Handshake(format!("ready fields: {error}")))?;
        if handshake.schema_version != 1 {
            return Err(crate::CursorSdkError::Handshake(format!(
                "unsupported ready schema {}",
                handshake.schema_version
            )));
        }
        if handshake.transport != "tcp" || handshake.protocol != "connect" {
            return Err(crate::CursorSdkError::Handshake(
                "ready transport must be tcp/connect".into(),
            ));
        }
        if handshake.port == 0 {
            return Err(crate::CursorSdkError::Handshake(
                "ready port is zero".into(),
            ));
        }
        Ok(handshake)
    }

    pub fn endpoint(&self) -> String {
        self.url.clone().unwrap_or_else(|| {
            if self.host.contains(':') && !self.host.starts_with('[') {
                format!("http://[{}]:{}", self.host, self.port)
            } else {
                format!("http://{}:{}", self.host, self.port)
            }
        })
    }

    pub fn bearer_token_from_file(&self) -> Result<String, crate::CursorSdkError> {
        let path = self.auth_token_file.as_deref().ok_or_else(|| {
            crate::CursorSdkError::Handshake("ready payload omitted authTokenFile".into())
        })?;
        let token = std::fs::read_to_string(path).map_err(|error| {
            crate::CursorSdkError::Handshake(format!("read auth token: {error}"))
        })?;
        let token = token.trim().to_owned();
        if token.is_empty() {
            return Err(crate::CursorSdkError::Handshake(
                "auth token is empty".into(),
            ));
        }
        Ok(token)
    }
}

#[cfg(test)]
mod mcp_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn mcp_debug_redacts_secrets_in_nested_agent_and_send_options() {
        let servers = BTreeMap::from([
            ("local".into(), McpServerConfig {
                stdio: Some(StdioMcpServerConfig {
                    command: "mcp-tools".into(),
                    args: vec!["argument-secret".into()],
                    env: BTreeMap::from([
                        ("Z_TOKEN".into(), "environment-secret".into()),
                        ("A_TOKEN".into(), "other-secret".into()),
                    ]),
                    cwd: "/project".into(),
                }),
                http: None,
            }),
            ("remote".into(), McpServerConfig {
                stdio: None,
                http: Some(HttpMcpServerConfig {
                    transport_type: HttpMcpTransportType::Http,
                    url: "https://user:password@mcp.example.test/private?token=query-secret#fragment-secret".into(),
                    headers: BTreeMap::from([("Authorization".into(), "header-secret".into())]),
                }),
            }),
        ]);
        assert_eq!(format!("{:?}", servers["local"].stdio.as_ref().unwrap()),
            "StdioMcpServerConfig { command: \"mcp-tools\", env_keys: [\"A_TOKEN\", \"Z_TOKEN\"], .. }");
        assert_eq!(
            format!("{:?}", servers["remote"].http.as_ref().unwrap()),
            "HttpMcpServerConfig { transport_type: Http, header_keys: [\"Authorization\"], .. }"
        );
        let agent = AgentOptions {
            mcp_servers: Some(servers.clone()),
            ..AgentOptions::default()
        };
        let send = SendOptions {
            mcp_servers: Some(servers),
            ..SendOptions::default()
        };
        for output in [format!("{agent:?}"), format!("{send:?}")] {
            for secret in [
                "argument-secret",
                "environment-secret",
                "other-secret",
                "password",
                "query-secret",
                "fragment-secret",
                "header-secret",
                "mcp.example.test",
            ] {
                assert!(!output.contains(secret));
            }
            assert!(output.contains("Authorization"));
            assert!(output.contains("A_TOKEN"));
        }
        let value = serde_json::to_value(&agent).unwrap();
        assert_eq!(
            value["mcpServers"]["local"],
            json!({
                "stdio": {"command":"mcp-tools","args":["argument-secret"],"env":{"A_TOKEN":"other-secret","Z_TOKEN":"environment-secret"},"cwd":"/project"}
            })
        );
        assert_eq!(
            value["mcpServers"]["remote"],
            json!({
                "http": {"type":"HTTP_MCP_TRANSPORT_TYPE_HTTP","url":"https://user:password@mcp.example.test/private?token=query-secret#fragment-secret","headers":{"Authorization":"header-secret"}}
            })
        );
        let roundtrip: AgentOptions = serde_json::from_value(value.clone()).unwrap();
        assert_eq!(serde_json::to_value(roundtrip).unwrap(), value);
        assert_eq!(serde_json::to_value(agent.clone()).unwrap(), value);
        assert_eq!(
            serde_json::to_value(send.clone()).unwrap()["mcpServers"],
            value["mcpServers"]
        );
    }
}
