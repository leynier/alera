use crate::computer_use::contract::{
    ActionSupport, AppSupport, Capabilities, ObservationSupport, SupportMatrix, WindowSupport,
    PROVIDER_VERSION,
};
use crate::computer_use::macos::tcc_permissions::accessibility_hint;

/// What this macOS session can do.
///
/// The one question that matters is the Accessibility grant: without it every
/// attribute read fails, so an agent would see an empty tree rather than a clear
/// reason. macOS awards it per executable, which is why the reason names the
/// binary rather than the application.
pub fn capabilities(accessibility_granted: bool, provider: String) -> Capabilities {
    if !accessibility_granted {
        return Capabilities::unsupported(std::env::consts::OS, provider, accessibility_hint());
    }
    Capabilities {
        platform: std::env::consts::OS.to_string(),
        provider,
        provider_version: PROVIDER_VERSION.to_string(),
        supported: true,
        unsupported_reason: None,
        supports: SupportMatrix {
            apps: AppSupport {
                list: true,
                // The bundle identifier lives in a property list this build does
                // not read, so apps are matched by name or pid.
                bundle_ids: false,
                pids: true,
            },
            windows: WindowSupport {
                list: true,
                // The accessibility API exposes no reusable window handle, so the
                // index is the address, as on AT-SPI.
                target_by_id: false,
                target_by_index: true,
                restore: false,
            },
            observation: ObservationSupport {
                tree: true,
                screenshot: false,
                element_frames: true,
            },
            actions: ActionSupport {
                // Accessibility actions are accepted by the application itself,
                // so they need no frontmost window.
                click: true,
                set_value: true,
                perform_action: true,
                // Synthetic input would need its own grant and a route into the
                // session; advertising it before that exists would have agents
                // plan around verbs that fail.
                type_text: false,
                press_key: false,
                hotkey: false,
                paste_text: false,
                scroll: false,
                drag: false,
            },
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The grant is the whole story on macOS, and the reason has to be actionable
    /// because the user is the only one who can fix it.
    #[test]
    fn a_missing_grant_reports_unsupported_with_the_settings_path() {
        let capabilities = capabilities(false, "p".to_string());
        assert!(!capabilities.supported);
        let reason = capabilities.unsupported_reason.unwrap();
        assert!(reason.contains("System Settings"));
        assert!(reason.contains("Accessibility"));
    }

    #[test]
    fn a_granted_session_advertises_reading_and_accessibility_actions() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(capabilities.supported);
        assert!(capabilities.supports.observation.tree);
        assert!(capabilities.supports.actions.click);
        assert!(capabilities.supports.actions.set_value);
        assert!(capabilities.supports.actions.perform_action);
    }

    /// Unlike Windows, macOS has no window handle to hand back, so an agent must
    /// be told to address windows by index.
    #[test]
    fn window_ids_are_not_advertised() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(!capabilities.supports.windows.target_by_id);
        assert!(capabilities.supports.windows.target_by_index);
    }

    #[test]
    fn synthetic_input_and_capture_are_not_advertised() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(!capabilities.supports.actions.type_text);
        assert!(!capabilities.supports.actions.hotkey);
        assert!(!capabilities.supports.observation.screenshot);
    }
}
