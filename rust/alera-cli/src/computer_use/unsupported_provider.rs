use crate::computer_use::contract::{
    Capabilities, PermissionId, PermissionItem, PermissionState, PermissionsReport,
};
use crate::computer_use::error::ComputerResult;
use crate::computer_use::ComputerUseProvider;

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

impl ComputerUseProvider for UnsupportedProvider {
    fn handshake(&self) -> ComputerResult<Capabilities> {
        Ok(Capabilities::unsupported(
            self.platform.clone(),
            self.provider.clone(),
            self.reason.clone(),
        ))
    }

    fn permissions(&self) -> ComputerResult<PermissionsReport> {
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

    #[test]
    fn the_handshake_reports_the_reason_it_was_built_with() {
        let provider = UnsupportedProvider::new("linux", "alera-computer-use-linux", "no session");
        let capabilities = provider.handshake().unwrap();
        assert!(!capabilities.supported);
        assert_eq!(
            capabilities.unsupported_reason.as_deref(),
            Some("no session")
        );
        assert_eq!(capabilities.platform, "linux");
    }

    /// Reporting Denied would send the user to a settings pane that cannot help,
    /// because no grant was ever checked.
    #[test]
    fn permissions_are_unknown_rather_than_denied() {
        let provider = UnsupportedProvider::new("linux", "p", "no session");
        let report = provider.permissions().unwrap();
        assert_eq!(report.items.len(), 2);
        for item in &report.items {
            assert_eq!(item.state, PermissionState::Unknown);
            assert_eq!(item.detail.as_deref(), Some("no session"));
        }
    }
}
