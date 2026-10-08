//! Cloud calls for MCP Control: runtime naming, connected apps, and the device
//! sign-in used by headless runtimes.

use anyhow::Result;
use chrono::{DateTime, Utc};
use reqwest::Method;
use serde::{Deserialize, Serialize};

use super::{AuthEnvelope, CloudAccountClient, RelayGrant};

/// What a runtime reports with each relay grant request, so the cloud can
/// route MCP calls and hide the runtime from phones when Remote Access is off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RelayCapabilities {
    pub(crate) mcp_access: &'static str,
    pub(crate) mobile_access: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct McpGrant {
    pub(crate) id: String,
    pub(crate) client_id: String,
    pub(crate) client_name: String,
    #[serde(default)]
    pub(crate) redirect_host: Option<String>,
    #[serde(default)]
    pub(crate) scopes: Vec<String>,
    #[serde(default)]
    pub(crate) all_runtimes: bool,
    #[serde(default)]
    pub(crate) runtime_ids: Vec<String>,
    pub(crate) created_at: DateTime<Utc>,
    #[serde(default)]
    pub(crate) last_used_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
struct McpGrantList {
    grants: Vec<McpGrant>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DeviceAuthorization {
    #[serde(skip_serializing)]
    pub(crate) device_code: String,
    pub(crate) user_code: String,
    pub(crate) verification_uri: String,
    pub(crate) verification_uri_complete: String,
    pub(crate) expires_in: i64,
    pub(crate) interval: i64,
}

impl CloudAccountClient {
    pub(crate) async fn relay_grant(
        &self,
        access_token: &str,
        runtime_id: &str,
        capabilities: RelayCapabilities,
    ) -> Result<RelayGrant> {
        self.json(
            Method::POST,
            "/v1/relay/grants",
            Some(access_token),
            Some(serde_json::json!({
                "runtimeId": runtime_id,
                "mcpAccess": capabilities.mcp_access,
                "mobileAccess": capabilities.mobile_access,
            })),
        )
        .await
    }

    pub(crate) async fn report_capabilities(
        &self,
        access_token: &str,
        capabilities: RelayCapabilities,
    ) -> Result<()> {
        self.request(
            Method::PUT,
            "/v1/runtime/capabilities",
            Some(access_token),
            Some(serde_json::json!({
                "mcpAccess": capabilities.mcp_access,
                "mobileAccess": capabilities.mobile_access,
            })),
        )
        .await?;
        Ok(())
    }

    pub(crate) async fn rename_runtime(&self, access_token: &str, name: &str) -> Result<()> {
        self.request(
            Method::PUT,
            "/v1/runtime/name",
            Some(access_token),
            Some(serde_json::json!({ "name": name })),
        )
        .await?;
        Ok(())
    }

    pub(crate) async fn mcp_grants(&self, access_token: &str) -> Result<Vec<McpGrant>> {
        let list: McpGrantList = self
            .json(Method::GET, "/v1/mcp/grants", Some(access_token), None)
            .await?;
        Ok(list.grants)
    }

    pub(crate) async fn revoke_mcp_grant(&self, access_token: &str, grant_id: &str) -> Result<()> {
        let path = format!("/v1/mcp/grants/{}", urlencode(grant_id));
        self.request(Method::DELETE, &path, Some(access_token), None)
            .await?;
        Ok(())
    }

    pub(crate) async fn start_device_authorization(
        &self,
        runtime_id: &str,
        device_name: &str,
    ) -> Result<DeviceAuthorization> {
        self.json(
            Method::POST,
            "/v1/auth/device",
            None,
            Some(serde_json::json!({
                "clientId": runtime_id,
                "clientKind": "runtime",
                "deviceName": device_name,
            })),
        )
        .await
    }

    pub(crate) async fn poll_device_authorization(
        &self,
        device_code: &str,
    ) -> Result<AuthEnvelope> {
        self.json(
            Method::POST,
            "/v1/auth/device/token",
            None,
            Some(serde_json::json!({ "deviceCode": device_code })),
        )
        .await
    }
}

fn urlencode(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}
