pub mod at_spi_tree;
pub mod linux_capabilities;

use async_trait::async_trait;
use uuid::Uuid;

use crate::computer_use::blocked_apps::ensure_app_allowed;
use crate::computer_use::contract::{
    AppInfo, Capabilities, PermissionId, PermissionItem, PermissionState, PermissionsReport,
};
use crate::computer_use::desktop_session::DesktopSession;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_contract::{Snapshot, WindowInfo, WINDOW_COORDINATE_SPACE};
use crate::computer_use::tree_render::{render_window_tree, DEFAULT_BUDGET};
use crate::computer_use::{provider_name, ComputerUseProvider, SnapshotRequest};
use at_spi_tree::AtSpiSession;

/// Reads and drives desktop UI through AT-SPI.
pub struct LinuxProvider {
    session: DesktopSession,
}

impl LinuxProvider {
    pub fn new(session: DesktopSession) -> Self {
        LinuxProvider { session }
    }

    /// Connect per call rather than holding a connection.
    ///
    /// The host outlives login sessions and screen locks; a cached bus
    /// connection would keep answering for a session that has gone away.
    async fn connect(&self) -> ComputerResult<AtSpiSession> {
        AtSpiSession::connect().await
    }
}

#[async_trait]
impl ComputerUseProvider for LinuxProvider {
    async fn handshake(&self) -> ComputerResult<Capabilities> {
        // Probing the bus rather than trusting the environment: at-spi2-core can
        // be absent or stopped on a session that otherwise looks complete.
        let reachable = self.connect().await.is_ok();
        Ok(linux_capabilities::capabilities(reachable, provider_name()))
    }

    async fn permissions(&self) -> ComputerResult<PermissionsReport> {
        // Linux has no per-app grant to award: either the accessibility bus is
        // reachable or it is not, and that is what the report says.
        let reachable = self.connect().await.is_ok();
        let accessibility = PermissionItem {
            id: PermissionId::Accessibility,
            label: "Accessibility".to_string(),
            state: if reachable {
                PermissionState::Granted
            } else {
                PermissionState::Denied
            },
            detail: (!reachable).then(|| {
                "The accessibility bus did not answer. Install at-spi2-core and \
                 enable accessibility for your desktop session."
                    .to_string()
            }),
        };
        let screenshots = PermissionItem {
            id: PermissionId::Screenshots,
            label: "Screen Recording".to_string(),
            state: PermissionState::NotApplicable,
            detail: Some(screenshot_detail(self.session)),
        };
        Ok(PermissionsReport {
            platform: std::env::consts::OS.to_string(),
            items: vec![accessibility, screenshots],
        })
    }

    async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
        self.connect().await?.list_apps().await
    }

    async fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
        ensure_app_allowed(app)?;
        self.connect().await?.list_windows(app).await
    }

    async fn snapshot(&self, request: SnapshotRequest<'_>) -> ComputerResult<Snapshot> {
        ensure_app_allowed(request.app)?;
        if request.window_id.is_some() {
            return Err(ComputerError::new(
                ComputerErrorCode::UnsupportedCapability,
                "AT-SPI exposes no stable window handle. Address windows by index on Linux."
                    .to_string(),
            ));
        }
        let session = self.connect().await?;
        let window_index = match request.window_index {
            Some(index) => index,
            None => session.default_window_index(request.app).await?,
        };
        let (root, window) = session
            .read_window(request.app, window_index, DEFAULT_BUDGET.max_nodes)
            .await?;
        // Frames arrive window-local from AT-SPI, so the renderer is told not to
        // subtract the window origin a second time.
        let rendered = render_window_tree(&root, None, DEFAULT_BUDGET);
        let screenshot_error = request
            .include_screenshot
            .then(|| screenshot_detail(self.session));
        Ok(Snapshot {
            snapshot_id: Uuid::new_v4().to_string(),
            app: request.app.clone(),
            window,
            coordinate_space: WINDOW_COORDINATE_SPACE,
            tree_text: rendered.tree_text,
            element_count: rendered.elements.len(),
            focused_element_index: rendered.focused_element_index,
            truncation: rendered.truncation,
            screenshot: None,
            screenshot_error,
            elements: rendered.elements,
        })
    }
}

/// Why there is no screenshot yet, in the words the agent should act on.
fn screenshot_detail(session: DesktopSession) -> String {
    use crate::computer_use::desktop_session::DisplayServer;
    match session.display_server {
        DisplayServer::Wayland => "Screen capture under Wayland needs the desktop portal, \
             which Alera does not use yet. Read the accessibility tree instead."
            .to_string(),
        _ => "Screen capture is not implemented on Linux yet. Read the accessibility \
             tree instead."
            .to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::computer_use::desktop_session::DisplayServer;

    fn provider(display_server: DisplayServer) -> LinuxProvider {
        LinuxProvider::new(DesktopSession { display_server })
    }

    /// The agent is told which of the two problems it has, because the fix
    /// differs: a portal is Alera's work, a missing bus is the user's.
    #[test]
    fn the_screenshot_reason_names_wayland_when_that_is_the_cause() {
        assert!(screenshot_detail(DesktopSession {
            display_server: DisplayServer::Wayland
        })
        .contains("portal"));
        assert!(!screenshot_detail(DesktopSession {
            display_server: DisplayServer::X11
        })
        .contains("portal"));
    }

    #[tokio::test]
    async fn a_blocked_app_is_refused_before_the_bus_is_touched() {
        let blocked = AppInfo {
            name: "Bitwarden".to_string(),
            bundle_id: None,
            pid: 1,
        };
        let error = provider(DisplayServer::Wayland)
            .list_windows(&blocked)
            .await
            .unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::AppBlocked);
    }

    /// A window id would silently observe whatever window happened to be at that
    /// index, so it is refused rather than approximated.
    #[tokio::test]
    async fn a_window_id_is_refused_on_at_spi() {
        let app = AppInfo {
            name: "Spotify".to_string(),
            bundle_id: None,
            pid: 1,
        };
        let error = provider(DisplayServer::X11)
            .snapshot(SnapshotRequest {
                app: &app,
                window_id: Some(7),
                window_index: None,
                include_screenshot: false,
            })
            .await
            .unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::UnsupportedCapability);
        assert!(error.message.contains("index"));
    }
}
