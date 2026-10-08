use std::str::FromStr;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{api_models::ClientKind, error::ApiError};

pub const SCOPE_READ: &str = "mcp:read";
pub const SCOPE_EXECUTE: &str = "mcp:execute";

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum McpAccess {
    #[default]
    Off,
    Read,
    Full,
}

impl McpAccess {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Read => "read",
            Self::Full => "full",
        }
    }
}

impl FromStr for McpAccess {
    type Err = ApiError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "off" => Ok(Self::Off),
            "read" => Ok(Self::Read),
            "full" => Ok(Self::Full),
            _ => Err(ApiError::bad_request(
                "invalid_mcp_access",
                "The MCP access level is invalid.",
            )),
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ToolAccess {
    Read,
    Execute,
}

impl ToolAccess {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Execute => "execute",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CallOutcome {
    Ok,
    ToolError,
    RuntimeOffline,
    Timeout,
    Failed,
}

impl CallOutcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::ToolError => "tool_error",
            Self::RuntimeOffline => "runtime_offline",
            Self::Timeout => "timeout",
            Self::Failed => "failed",
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpRuntimeSummary {
    pub id: String,
    pub name: String,
    pub online: bool,
    pub mcp_access: McpAccess,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpRuntimeList {
    pub runtimes: Vec<McpRuntimeSummary>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateMcpCallRequest {
    #[serde(default)]
    pub runtime: Option<String>,
    pub tool: String,
    pub access: ToolAccess,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateMcpCallResponse {
    pub call_id: Uuid,
    pub runtime_id: String,
    pub runtime_name: String,
    pub grant: String,
    pub expires_in: i64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpCallOutcomeRequest {
    pub outcome: CallOutcome,
    pub duration_ms: i64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpGrantSummary {
    pub id: Uuid,
    pub client_id: String,
    pub client_name: String,
    pub redirect_host: String,
    pub scopes: Vec<String>,
    pub all_runtimes: bool,
    pub runtime_ids: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpGrantList {
    pub grants: Vec<McpGrantSummary>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameRuntimeRequest {
    pub name: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeCapabilitiesRequest {
    pub mcp_access: McpAccess,
    pub mobile_access: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameRuntimeResponse {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartDeviceAuthorizationRequest {
    pub client_id: String,
    pub client_kind: ClientKind,
    pub device_name: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceAuthorizationResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub verification_uri_complete: String,
    pub expires_in: i64,
    pub interval: i64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceTokenRequest {
    pub device_code: String,
}

/// Splits a space-separated scope string into its known MCP scopes.
pub fn scope_list(scopes: &str) -> Vec<String> {
    scopes.split_whitespace().map(ToOwned::to_owned).collect()
}
