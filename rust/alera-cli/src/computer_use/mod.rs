//! Reading and driving local desktop UI through the platform accessibility
//! layers.
//!
//! This lives in the sidecar rather than behind the Flutter bridge because the
//! host is the process that sits in the user's desktop session: on Linux it
//! holds the session bus, and on macOS it is the stable identity the operating
//! system grants Accessibility to. A CLI invocation would otherwise ask the
//! terminal that launched it for those grants.
//!
//! The contract lands ahead of the verbs that consume it. The closed error-code
//! set, the app selector, and the blocked-app gate define the shape of the
//! surface, and the observation and action verbs are what will call them; each
//! is covered by its own tests in the meantime. Remove the allow below once
//! those verbs exist, so real dead code stops hiding behind it.
#![allow(dead_code)]

pub mod action_contract;
pub mod action_gate;
pub mod app_selector;
pub mod blocked_apps;
pub mod browser_tab_compaction;
pub mod contract;
pub mod desktop_session;
pub mod element_signature;
pub mod error;
#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(target_os = "macos")]
pub mod macos;
pub mod node_elision;
pub mod repeated_node;
pub mod screenshot_budget;
pub mod screenshot_store;
pub mod secure_nodes;
pub mod snapshot_cache;
pub mod snapshot_contract;
pub mod snapshot_registry;
pub mod tree_render;
pub mod unsupported_provider;
#[cfg(target_os = "windows")]
pub mod windows;

use async_trait::async_trait;

use action_contract::{ActionOutcome, ActionRequest};
use contract::{AppInfo, Capabilities, PermissionsReport};
use error::ComputerResult;
use snapshot_contract::{Snapshot, WindowInfo};
use unsupported_provider::UnsupportedProvider;

/// What every platform provider answers.
///
/// Async because the accessibility layers are: AT-SPI is D-Bus, and a
/// synchronous wrapper would either block the host's actor thread or nest a
/// second runtime inside the one already running.
#[async_trait]
pub trait ComputerUseProvider: Send + Sync {
    /// Describe what this session can do. Called before anything else, and safe
    /// to call on a machine with no desktop.
    async fn handshake(&self) -> ComputerResult<Capabilities>;

    /// Report the operating-system grants computer use depends on.
    ///
    /// Never opens a system prompt: agents retry failed observations, and a
    /// prompt per retry would bury the user in dialogs. Only an explicit setup
    /// flow may do that.
    async fn permissions(&self) -> ComputerResult<PermissionsReport>;

    /// Applications with at least one window.
    async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>>;

    /// The windows of one application, in the order they are addressed by index.
    async fn list_windows(&self, app: &AppInfo) -> ComputerResult<Vec<WindowInfo>>;

    /// Observe one window: the tree, and a screenshot unless it was declined.
    async fn snapshot(&self, request: SnapshotRequest<'_>) -> ComputerResult<Snapshot>;

    /// Do one thing to one element, and report what the window looks like after.
    async fn act(&self, request: ActionRequest<'_>) -> ComputerResult<ActionOutcome>;
}

/// Which window to observe and how much of it to report.
#[derive(Debug, Clone, Copy)]
pub struct SnapshotRequest<'a> {
    pub app: &'a AppInfo,
    pub window_id: Option<i64>,
    pub window_index: Option<usize>,
    pub include_screenshot: bool,
}

/// Name reported for this platform's provider, so a client can tell which
/// implementation answered without inferring it from the platform.
pub fn provider_name() -> String {
    format!("alera-computer-use-{}", std::env::consts::OS)
}

/// The provider for this process, or one that explains why there is none.
///
/// Resolved per call rather than cached: a host outlives the login session it
/// was started in, and a session that appears or disappears must change the
/// answer instead of replaying the state at host startup.
pub fn active_provider() -> Box<dyn ComputerUseProvider> {
    let platform = std::env::consts::OS;
    let provider = provider_name();
    let session = match desktop_session::probe_desktop_session() {
        Err(reason) => return Box::new(UnsupportedProvider::new(platform, provider, reason)),
        Ok(session) => session,
    };
    #[cfg(target_os = "linux")]
    {
        Box::new(linux::LinuxProvider::new(session))
    }
    #[cfg(target_os = "macos")]
    {
        let _ = session;
        Box::new(macos::MacosProvider::new())
    }
    #[cfg(target_os = "windows")]
    {
        let _ = session;
        Box::new(windows::WindowsProvider::new())
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Box::new(UnsupportedProvider::new(
            platform,
            provider,
            format!(
                "A {} desktop session was found, but this Alera build has no computer-use provider for it yet.",
                session.display_server.as_str()
            ),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_provider_name_carries_the_platform() {
        assert_eq!(
            provider_name(),
            format!("alera-computer-use-{}", std::env::consts::OS)
        );
    }

    /// `capabilities` must answer on every machine, including a headless server,
    /// because that is how an agent learns to stop rather than by failing a verb.
    /// The result depends on the machine running the test, so the invariant is
    /// that it answers and that a refusal always carries its reason.
    #[tokio::test]
    async fn the_active_provider_always_answers_a_handshake() {
        let capabilities = active_provider().handshake().await.unwrap();
        assert_eq!(capabilities.platform, std::env::consts::OS);
        assert_eq!(
            capabilities.supported,
            capabilities.unsupported_reason.is_none(),
            "an unsupported session must say why, and a supported one must not"
        );
    }

    #[tokio::test]
    async fn the_active_provider_always_answers_permissions() {
        let report = active_provider().permissions().await.unwrap();
        assert_eq!(report.platform, std::env::consts::OS);
        assert_eq!(report.items.len(), 2);
    }
}
