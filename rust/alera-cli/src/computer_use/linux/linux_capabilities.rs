use crate::computer_use::contract::{
    ActionSupport, AppSupport, Capabilities, ObservationSupport, SupportMatrix, WindowSupport,
    PROVIDER_VERSION,
};
use crate::computer_use::desktop_session::{DesktopSession, DisplayServer};

/// What this Linux session can actually do.
///
/// Answered from a live probe of the bus rather than compiled in, because
/// at-spi2-core can be missing or stopped on a session that otherwise looks
/// complete. Reading does not depend on the display server: AT-SPI is D-Bus, so
/// the tree is available under Wayland exactly as under X11. What Wayland costs
/// is synthetic input and screen capture, reported separately.
pub fn capabilities(bus_reachable: bool, provider: String) -> Capabilities {
    if !bus_reachable {
        return Capabilities::unsupported(
            std::env::consts::OS,
            provider,
            "The accessibility bus did not answer. Install at-spi2-core and enable \
             accessibility for your desktop session, then retry."
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
                // AT-SPI reports a display name only; there is no bundle id to
                // match against on this platform.
                bundle_ids: false,
                pids: true,
            },
            windows: WindowSupport {
                list: true,
                // No stable handle exists, so an index is the only address.
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
                // Accessibility actions go through the application itself, so
                // they work on an unfocused window and under any display server.
                click: true,
                set_value: true,
                perform_action: true,
                // Synthetic input still needs a route into the session. Under
                // Wayland that is the remote-desktop portal, which this build
                // does not use, so these stay off rather than failing per call.
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

/// Whether synthetic pointer and keyboard input can work at all here.
///
/// Kept next to the capability matrix so the action phase reports the same
/// answer this one does, rather than deciding again.
pub fn supports_synthetic_input(session: DesktopSession) -> bool {
    // Under Wayland a client cannot inject input without the remote-desktop
    // portal; X11 lets any client do it.
    session.display_server != DisplayServer::Wayland
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session(display_server: DisplayServer) -> DesktopSession {
        DesktopSession { display_server }
    }

    /// An unreachable bus is the one failure an agent can fix itself, so the
    /// reason names the package to install.
    #[test]
    fn an_unreachable_bus_reports_unsupported_with_the_fix() {
        let capabilities = capabilities(false, "p".to_string());
        assert!(!capabilities.supported);
        let reason = capabilities.unsupported_reason.unwrap();
        assert!(reason.contains("at-spi2-core"));
    }

    #[test]
    fn a_reachable_bus_advertises_tree_reading() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(capabilities.supported);
        assert!(capabilities.supports.observation.tree);
        assert!(capabilities.supports.observation.element_frames);
        assert!(capabilities.supports.apps.list);
        assert!(capabilities.supports.windows.list);
    }

    #[test]
    fn window_ids_are_never_advertised_on_at_spi() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(!capabilities.supports.windows.target_by_id);
        assert!(capabilities.supports.windows.target_by_index);
    }

    /// The accessibility route works under any display server, because it asks
    /// the application rather than the compositor.
    #[test]
    fn accessibility_actions_are_advertised() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(capabilities.supports.actions.click);
        assert!(capabilities.supports.actions.set_value);
        assert!(capabilities.supports.actions.perform_action);
    }

    /// Advertising synthetic input before there is a route into the session would
    /// have the agent plan around verbs that cannot work.
    #[test]
    fn synthetic_input_actions_are_not_advertised() {
        let capabilities = capabilities(true, "p".to_string());
        assert!(!capabilities.supports.actions.type_text);
        assert!(!capabilities.supports.actions.press_key);
        assert!(!capabilities.supports.actions.hotkey);
        assert!(!capabilities.supports.actions.scroll);
        assert!(!capabilities.supports.actions.drag);
        assert!(!capabilities.supports.actions.paste_text);
    }

    #[test]
    fn synthetic_input_is_ruled_out_under_wayland() {
        assert!(!supports_synthetic_input(session(DisplayServer::Wayland)));
        assert!(supports_synthetic_input(session(DisplayServer::X11)));
    }
}
