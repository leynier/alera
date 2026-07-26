use crate::computer_use::contract::{
    ActionSupport, AppSupport, Capabilities, ObservationSupport, SupportMatrix, WindowSupport,
    PROVIDER_VERSION,
};

/// What this Windows session can do.
///
/// UI Automation needs no grant to award and is present on every supported
/// Windows version, so the only question is whether the service answered.
pub fn capabilities(automation_reachable: bool, provider: String) -> Capabilities {
    if !automation_reachable {
        return Capabilities::unsupported(
            std::env::consts::OS,
            provider,
            "UI Automation did not answer. A session without an interactive desktop, such as \
             a service or an SSH login with no console, cannot drive the UI."
                .to_string(),
        );
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
                // Windows has no bundle identifier; apps are matched by the
                // executable name.
                bundle_ids: false,
                pids: true,
            },
            windows: WindowSupport {
                // Unlike AT-SPI, a window handle is stable here, so an agent may
                // address a window by id across reads.
                list: true,
                target_by_id: true,
                target_by_index: true,
                restore: false,
            },
            observation: ObservationSupport {
                tree: true,
                screenshot: false,
                element_frames: true,
            },
            actions: ActionSupport {
                // Patterns are invoked on the element itself, so they need no
                // foreground window and no synthetic input.
                click: true,
                set_value: true,
                perform_action: true,
                // Synthetic input and capture are not wired up on any platform
                // yet; advertising them would have agents plan around verbs that
                // fail.
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

    /// The common way this fails is a session with no interactive desktop, and
    /// the reason has to name that rather than look like a bug.
    #[test]
    fn an_unreachable_service_explains_the_likely_cause() {
        let capabilities = capabilities(false, "p".to_string());
        assert!(!capabilities.supported);
        let reason = capabilities.unsupported_reason.unwrap();
        assert!(reason.contains("interactive desktop"));
    }

    #[test]
    fn a_reachable_service_advertises_reading_and_accessibility_actions() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(capabilities.supported);
        assert!(capabilities.supports.observation.tree);
        assert!(capabilities.supports.actions.click);
        assert!(capabilities.supports.actions.set_value);
    }

    /// The one capability that genuinely differs from Linux: Windows has a
    /// stable window handle, so agents may address windows by id.
    #[test]
    fn window_ids_are_advertised_on_windows() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(capabilities.supports.windows.target_by_id);
        assert!(capabilities.supports.windows.target_by_index);
    }

    #[test]
    fn synthetic_input_is_not_advertised() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(!capabilities.supports.actions.type_text);
        assert!(!capabilities.supports.actions.press_key);
        assert!(!capabilities.supports.observation.screenshot);
    }
}
