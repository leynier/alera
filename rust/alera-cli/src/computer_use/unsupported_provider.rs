use async_trait::async_trait;

use crate::computer_use::action_contract::{ActionOutcome, ActionRequest};
use crate::computer_use::contract::{
    AppInfo, Capabilities, PermissionId, PermissionItem, PermissionState, PermissionsReport,
};
use crate::computer_use::error::{ComputerError, ComputerResult};
use crate::computer_use::snapshot_contract::{Snapshot, WindowInfo};
use crate::computer_use::{ComputerUseProvider, SnapshotRequest};

/// The provider used when nothing can be driven: no desktop session, or no
/// platform provider built yet.
///
/// It answers instead of failing so an agent learns the situation from one
/// `capabilities` call, and keeps the reason it was created with rather than
/// re-deriving a generic message per verb.
pub struct UnsupportedProvider {
    platform: String,
    provider: String,
    reason: String,
}

impl UnsupportedProvider {
    pub fn new(
        platform: impl Into<String>,
        provider: impl Into<String>,
        reason: impl Into<String>,
    ) -> Self {
        UnsupportedProvider {
            platform: platform.into(),
            provider: provider.into(),
            reason: reason.into(),
        }
    }
}

#[async_trait]
impl ComputerUseProvider for UnsupportedProvider {
    async fn handshake(&self) -> ComputerResult<Capabilities> {
        Ok(Capabilities::unsupported(
            self.platform.clone(),
            self.provider.clone(),
            self.reason.clone(),
        ))
    }

    async fn permissions(&self) -> ComputerResult<PermissionsReport> {
        // Unknown rather than Denied: without a provider nothing has been
        // checked, and telling the user a grant was refused would send them to
        // a settings pane that would not fix anything.
        let items = [PermissionId::Accessibility, PermissionId::Screenshots]
            .into_iter()
            .map(|id| PermissionItem {
                id,
                label: label_for(id).to_string(),
                state: PermissionState::Unknown,
                detail: Some(self.reason.clone()),
            })
            .collect();
        Ok(PermissionsReport {
            platform: self.platform.clone(),
            items,
        })
    }

    async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        Err(self.refusal())
    }

    async fn list_windows(&self, _app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        Err(self.refusal())
    }

    async fn snapshot(&self, _request: SnapshotRequest<'_>) -> ComputerResult<Snapshot> {
        Err(self.refusal())
    }

    async fn act(&self, _request: ActionRequest<'_>) -> ComputerResult<ActionOutcome> {
        Err(self.refusal())
    }
}

impl UnsupportedProvider {
    /// Every verb fails the same way, carrying the reason from the handshake so
    /// the agent is not told something different depending on which one it tried.
    fn refusal(&self) -> ComputerError {
        ComputerError::unsupported(self.reason.clone())
    }
}

pub(crate) fn label_for(id: PermissionId) -> &'static str {
    match id {
        PermissionId::Accessibility => "Accessibility",
        PermissionId::Screenshots => "Screen Recording",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_handshake_reports_the_reason_it_was_built_with() {
        let provider = UnsupportedProvider::new("linux", "alera-computer-use-linux", "no session");
        let capabilities = provider.handshake().await.unwrap();
        assert!(!capabilities.supported);
        assert_eq!(
            capabilities.unsupported_reason.as_deref(),
            Some("no session")
        );
        assert_eq!(capabilities.platform, "linux");
    }

    /// Reporting Denied would send the user to a settings pane that cannot help,
    /// because no grant was ever checked.
    #[tokio::test]
    async fn permissions_are_unknown_rather_than_denied() {
        let provider = UnsupportedProvider::new("linux", "p", "no session");
        let report = provider.permissions().await.unwrap();
        assert_eq!(report.items.len(), 2);
        for item in &report.items {
            assert_eq!(item.state, PermissionState::Unknown);
            assert_eq!(item.detail.as_deref(), Some("no session"));
        }
    }
}
