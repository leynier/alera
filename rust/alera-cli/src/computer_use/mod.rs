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

pub mod app_selector;
pub mod blocked_apps;
pub mod contract;
pub mod desktop_session;
pub mod error;
pub mod unsupported_provider;

use contract::{Capabilities, PermissionsReport};
use error::ComputerResult;
use unsupported_provider::UnsupportedProvider;

/// What every platform provider answers.
///
/// Observation and action verbs join this trait alongside the platform code that
/// implements them; until then a provider only has to describe itself.
pub trait ComputerUseProvider: Send + Sync {
    /// Describe what this session can do. Called before anything else, and safe
    /// to call on a machine with no desktop.
    fn handshake(&self) -> ComputerResult<Capabilities>;

    /// Report the operating-system grants computer use depends on.
    ///
    /// Never opens a system prompt: agents retry failed observations, and a
    /// prompt per retry would bury the user in dialogs. Only an explicit setup
    /// flow may do that.
    fn permissions(&self) -> ComputerResult<PermissionsReport>;
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
    match desktop_session::probe_desktop_session() {
        Err(reason) => Box::new(UnsupportedProvider::new(platform, provider, reason)),
        Ok(session) => Box::new(UnsupportedProvider::new(
            platform,
            provider,
            format!(
                "A {} desktop session was found, but this Alera build has no computer-use provider for it yet.",
                session.display_server.as_str()
            ),
        )),
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
    #[test]
    fn the_active_provider_always_answers_a_handshake() {
        let capabilities = active_provider().handshake().unwrap();
        assert_eq!(capabilities.platform, std::env::consts::OS);
        assert!(
            capabilities.unsupported_reason.is_some(),
            "an unsupported session must say why"
        );
    }

    #[test]
    fn the_active_provider_always_answers_permissions() {
        let report = active_provider().permissions().unwrap();
        assert_eq!(report.platform, std::env::consts::OS);
        assert_eq!(report.items.len(), 2);
    }
}
