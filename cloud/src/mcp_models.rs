use std::str::FromStr;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{api_models::ClientKind, error::ApiError};

pub const SCOPE_READ: &str = "mcp:read";
pub const SCOPE_EXECUTE: &str = "mcp:execute";
/// Administrative tools. Never part of a default scope: a grant holds it only when the
/// client asked for it and the person ticked the administrative tools box on consent.
pub const SCOPE_ADMIN: &str = "mcp:admin";
/// Every MCP scope, in the order discovery documents advertise them.
pub const SCOPES_SUPPORTED: [&str; 3] = [SCOPE_READ, SCOPE_EXECUTE, SCOPE_ADMIN];

/// The MCP Control level a runtime reports. Levels are ordered: each one allows
/// everything the previous one does.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum McpAccess {
    #[default]
    Off,
    Read,
    Full,
    Admin,
}

impl McpAccess {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Read => "read",
            Self::Full => "full",
            Self::Admin => "admin",
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
            "admin" => Ok(Self::Admin),
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
    Admin,
}

impl ToolAccess {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::Execute => "execute",
            Self::Admin => "admin",
        }
    }

    /// The OAuth scope a grant needs to call a tool of this class.
    pub fn scope(self) -> &'static str {
        match self {
            Self::Read => SCOPE_READ,
            Self::Execute => SCOPE_EXECUTE,
            Self::Admin => SCOPE_ADMIN,
        }
    }

    /// The lowest runtime MCP Control level that runs a tool of this class.
    pub fn minimum_runtime_access(self) -> McpAccess {
        match self {
            Self::Read => McpAccess::Read,
            Self::Execute => McpAccess::Full,
            Self::Admin => McpAccess::Admin,
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

#[cfg(test)]
mod tests {
    use super::{McpAccess, ToolAccess, SCOPES_SUPPORTED};

    #[test]
    fn access_levels_are_ordered_and_parse_admin() {
        assert!(McpAccess::Off < McpAccess::Read);
        assert!(McpAccess::Read < McpAccess::Full);
        assert!(McpAccess::Full < McpAccess::Admin);
        for level in [
            McpAccess::Off,
            McpAccess::Read,
            McpAccess::Full,
            McpAccess::Admin,
        ] {
            assert_eq!(level.as_str().parse::<McpAccess>().ok(), Some(level));
        }
        assert!("owner".parse::<McpAccess>().is_err());
        let reported: McpAccess = serde_json::from_str("\"admin\"").unwrap_or_default();
        assert_eq!(reported, McpAccess::Admin);
        let tool: Option<ToolAccess> = serde_json::from_str("\"admin\"").ok();
        assert_eq!(tool, Some(ToolAccess::Admin));
    }

    #[test]
    fn tool_classes_map_to_scope_and_runtime_level() {
        assert_eq!(ToolAccess::Read.scope(), "mcp:read");
        assert_eq!(ToolAccess::Execute.scope(), "mcp:execute");
        assert_eq!(ToolAccess::Admin.scope(), "mcp:admin");
        assert_eq!(
            ToolAccess::Execute.minimum_runtime_access(),
            McpAccess::Full
        );
        assert_eq!(ToolAccess::Admin.minimum_runtime_access(), McpAccess::Admin);
        assert_eq!(SCOPES_SUPPORTED, ["mcp:read", "mcp:execute", "mcp:admin"]);
    }
}
