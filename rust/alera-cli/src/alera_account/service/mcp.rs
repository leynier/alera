//! Account calls behind MCP Control: naming, connected apps, relay capability
//! reports, and the device sign-in for runtimes without a local browser.

use alera_core::runtime::LocalAleraAccount;
use anyhow::Result;

use super::super::cloud_client::{
    CloudRequestError, DeviceAuthorization, McpGrant, RelayCapabilities,
};
use super::AleraAccountService;
use crate::mcp_settings::{mcp_access, McpAccess};

/// What a device sign-in poll learned.
pub(crate) enum DevicePoll {
    Pending { slow_down: bool },
    Completed(Box<LocalAleraAccount>),
}

impl AleraAccountService {
    pub(crate) async fn relay_capabilities(&self) -> RelayCapabilities {
        let mcp = mcp_access(&self.store).await.unwrap_or(McpAccess::Off);
        let mobile_access = self
            .store
            .mobile_access_settings()
            .await
            .map(|settings| settings.remote_access_enabled)
            .unwrap_or(false);
        RelayCapabilities {
            mcp_access: mcp.as_str(),
            mobile_access,
        }
    }

    /// Tells the cloud the current levels right away. A runtime that turns both
    /// features off stops requesting relay grants, which would otherwise be the
    /// only report.
    pub(crate) async fn report_capabilities(&self) -> Result<()> {
        let token = self.access_token().await?;
        let capabilities = self.relay_capabilities().await;
        self.cloud.report_capabilities(&token, capabilities).await
    }

    pub(crate) async fn rename_runtime(&self, name: &str) -> Result<()> {
        let token = self.access_token().await?;
        self.cloud.rename_runtime(&token, name).await
    }

    pub(crate) async fn mcp_grants(&self) -> Result<Vec<McpGrant>> {
        let token = self.access_token().await?;
        self.cloud.mcp_grants(&token).await
    }

    pub(crate) async fn revoke_mcp_grant(&self, grant_id: &str) -> Result<()> {
        let token = self.access_token().await?;
        self.cloud.revoke_mcp_grant(&token, grant_id).await
    }

    pub(crate) async fn start_device_sign_in(
        &self,
        device_name: &str,
    ) -> Result<DeviceAuthorization> {
        self.cloud
            .start_device_authorization(&self.runtime_id, device_name)
            .await
    }

    pub(crate) async fn poll_device_sign_in(&self, device_code: &str) -> Result<DevicePoll> {
        match self.cloud.poll_device_authorization(device_code).await {
            Ok(envelope) => Ok(DevicePoll::Completed(Box::new(
                self.complete_auth(envelope).await?,
            ))),
            Err(error) => {
                let request = error.downcast_ref::<CloudRequestError>();
                if request.is_some_and(CloudRequestError::is_rate_limited) {
                    return Ok(DevicePoll::Pending { slow_down: true });
                }
                match request.and_then(CloudRequestError::code) {
                    Some("authorization_pending") => Ok(DevicePoll::Pending { slow_down: false }),
                    Some("slow_down") => Ok(DevicePoll::Pending { slow_down: true }),
                    _ => Err(error),
                }
            }
        }
    }
}

impl AleraAccountService {
    /// The chosen runtime name, else the host name. Sent on every sign-in so
    /// the cloud never falls back to the host name after a rename.
    pub(crate) async fn runtime_display_name(&self) -> String {
        crate::mcp_settings::effective_runtime_name(&self.store).await
    }
}
