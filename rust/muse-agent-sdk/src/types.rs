use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct MuseClientOptions {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub client_name: String,
    pub client_version: String,
    pub capabilities: Map<String, Value>,
    pub max_frame_bytes: usize,
    pub request_timeout: Duration,
    pub shutdown_timeout: Duration,
}

impl Default for MuseClientOptions {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("muse"),
            args: vec!["serve".into()],
            cwd: None,
            env: BTreeMap::new(),
            client_name: "alera".into(),
            client_version: env!("CARGO_PKG_VERSION").into(),
            capabilities: Map::new(),
            max_frame_bytes: 10 * 1024 * 1024,
            request_timeout: Duration::from_secs(30),
            shutdown_timeout: Duration::from_secs(30),
        }
    }
}

impl MuseClientOptions {
    pub fn client_info(&self) -> Value {
        serde_json::json!({"name": self.client_name, "version": self.client_version})
    }

    /// Add a capability to the native initialize request without replacing
    /// capabilities supplied by the caller. A non-array value is preserved
    /// and reported as unsupported so the provider can fail honestly later.
    pub fn request_capability(&mut self, capability: impl Into<String>) -> bool {
        let capability = capability.into();
        match self.capabilities.get_mut("requestedCapabilities") {
            None => {
                self.capabilities.insert(
                    "requestedCapabilities".into(),
                    Value::Array(vec![Value::String(capability)]),
                );
                true
            }
            Some(Value::Array(values)) => {
                if !values
                    .iter()
                    .any(|value| value.as_str() == Some(&capability))
                {
                    values.push(Value::String(capability));
                }
                true
            }
            Some(_) => false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResult {
    pub experimental_api: bool,
    #[serde(default)]
    pub granted_capabilities: Vec<String>,
    #[serde(default)]
    pub muse_home: String,
    #[serde(default)]
    pub platform_family: String,
    #[serde(default)]
    pub platform_os: String,
    #[serde(default)]
    pub session_durability: Option<String>,
    #[serde(default)]
    pub user_agent: String,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
    #[serde(skip)]
    pub raw: Value,
}

impl InitializeResult {
    pub fn from_value(raw: Value) -> Self {
        let mut parsed: Self = serde_json::from_value(raw.clone()).unwrap_or_else(|_| Self {
            experimental_api: false,
            granted_capabilities: Vec::new(),
            muse_home: String::new(),
            platform_family: String::new(),
            platform_os: String::new(),
            session_durability: None,
            user_agent: String::new(),
            extra: Map::new(),
            raw: Value::Null,
        });
        parsed.raw = raw;
        parsed
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSummary {
    pub session_id: String,
    pub status: String,
    #[serde(default)]
    pub active_turn_id: Option<String>,
    #[serde(default)]
    pub model_id: Option<String>,
    #[serde(default)]
    pub provider_id: Option<String>,
    #[serde(default)]
    pub workspace_root: Option<String>,
    #[serde(default)]
    pub turn_count: Option<u64>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
    #[serde(skip)]
    pub raw: Value,
}

impl SessionSummary {
    pub fn from_value(raw: Value) -> Option<Self> {
        let mut parsed: Self = serde_json::from_value(raw.clone()).ok()?;
        parsed.raw = raw;
        Some(parsed)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandAck {
    #[serde(default)]
    pub command_id: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub turn_id: Option<String>,
    #[serde(default)]
    pub disposition: Option<String>,
    #[serde(default)]
    pub started_new_turn: Option<bool>,
    #[serde(default)]
    pub approval_id: Option<String>,
    #[serde(default)]
    pub user_input_id: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
    #[serde(skip)]
    pub raw: Value,
}

impl CommandAck {
    pub fn from_value(raw: Value) -> Self {
        let mut parsed = serde_json::from_value(raw.clone()).unwrap_or_else(|_| Self {
            command_id: None,
            status: None,
            turn_id: None,
            disposition: None,
            started_new_turn: None,
            approval_id: None,
            user_input_id: None,
            extra: Map::new(),
            raw: Value::Null,
        });
        parsed.raw = raw;
        parsed
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub model_id: String,
    #[serde(default)]
    pub display_label: Option<String>,
    #[serde(default)]
    pub provider_id: Option<String>,
    #[serde(default)]
    pub is_active: Option<bool>,
    #[serde(default)]
    pub is_default: Option<bool>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum MuseFrame {
    Notification {
        method: String,
        params: Value,
        raw: Value,
    },
    ServerRequest {
        id: Value,
        method: String,
        params: Value,
        raw: Value,
    },
    Unknown(Value),
}

impl MuseFrame {
    pub fn method(&self) -> Option<&str> {
        match self {
            Self::Notification { method, .. } | Self::ServerRequest { method, .. } => Some(method),
            Self::Unknown(_) => None,
        }
    }

    pub fn params(&self) -> Option<&Value> {
        match self {
            Self::Notification { params, .. } | Self::ServerRequest { params, .. } => Some(params),
            Self::Unknown(_) => None,
        }
    }

    pub fn raw(&self) -> &Value {
        match self {
            Self::Notification { raw, .. } | Self::ServerRequest { raw, .. } => raw,
            Self::Unknown(raw) => raw,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct PendingServerRequest {
    pub id: Value,
    pub method: String,
    pub params: Value,
    pub raw: Value,
}
