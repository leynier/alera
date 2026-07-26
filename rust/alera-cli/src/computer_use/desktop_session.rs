/// Which display server the session runs on. It decides what synthetic input
/// and screen capture can do, so it is probed rather than assumed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayServer {
    X11,
    Wayland,
    Quartz,
    Windows,
}

impl DisplayServer {
    pub fn as_str(self) -> &'static str {
        match self {
            DisplayServer::X11 => "x11",
            DisplayServer::Wayland => "wayland",
            DisplayServer::Quartz => "quartz",
            DisplayServer::Windows => "windows",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DesktopSession {
    pub display_server: DisplayServer,
}

/// Look for a desktop session this process can drive.
///
/// The error is the sentence the agent will read, because the common case is not
/// a bug: a runtime host started with `alera runtime start` on a server has no
/// desktop at all, and saying so once is better than failing every verb.
pub fn probe_desktop_session() -> Result<DesktopSession, String> {
    #[cfg(target_os = "linux")]
    {
        classify_linux_session(|name| std::env::var(name).ok())
    }
    #[cfg(target_os = "macos")]
    {
        Ok(DesktopSession {
            display_server: DisplayServer::Quartz,
        })
    }
    #[cfg(target_os = "windows")]
    {
        Ok(DesktopSession {
            display_server: DisplayServer::Windows,
        })
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Err("Computer use has no provider for this operating system.".to_string())
    }
}

/// Decide from the environment alone, so the rule is testable without a display.
///
/// AT-SPI rides the session D-Bus, so a missing bus address means there is
/// nothing to talk to no matter what else is set.
#[cfg(any(target_os = "linux", test))]
pub(crate) fn classify_linux_session(
    get: impl Fn(&str) -> Option<String>,
) -> Result<DesktopSession, String> {
    let nonempty = |name: &str| get(name).filter(|value| !value.trim().is_empty());
    let mut missing = Vec::new();
    if nonempty("DBUS_SESSION_BUS_ADDRESS").is_none() {
        missing.push("DBUS_SESSION_BUS_ADDRESS");
    }
    if nonempty("XDG_RUNTIME_DIR").is_none() {
        missing.push("XDG_RUNTIME_DIR");
    }
    if !missing.is_empty() {
        return Err(format!(
            "Computer use needs an active desktop session; {} {} not set. \
             A runtime host started outside the graphical session cannot drive the desktop.",
            missing.join(" and "),
            if missing.len() == 1 { "is" } else { "are" }
        ));
    }
    let session_type = nonempty("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .to_lowercase();
    let wayland = session_type == "wayland" || nonempty("WAYLAND_DISPLAY").is_some();
    if wayland {
        return Ok(DesktopSession {
            display_server: DisplayServer::Wayland,
        });
    }
    if session_type == "x11" || nonempty("DISPLAY").is_some() {
        return Ok(DesktopSession {
            display_server: DisplayServer::X11,
        });
    }
    Err(
        "Computer use needs an active desktop session; neither DISPLAY nor WAYLAND_DISPLAY is set."
            .to_string(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |name| {
            pairs
                .iter()
                .find(|(key, _)| *key == name)
                .map(|(_, value)| (*value).to_string())
        }
    }

    #[test]
    fn a_missing_session_bus_is_reported_by_name() {
        let error =
            classify_linux_session(env(&[("XDG_RUNTIME_DIR", "/run/user/1000")])).unwrap_err();
        assert!(error.contains("DBUS_SESSION_BUS_ADDRESS"));
        assert!(error.contains("is not set"), "{error}");
    }

    #[test]
    fn a_headless_host_is_told_what_is_missing() {
        let error = classify_linux_session(env(&[])).unwrap_err();
        assert!(error.contains("DBUS_SESSION_BUS_ADDRESS"));
        assert!(error.contains("XDG_RUNTIME_DIR"));
        assert!(error.contains("are not set"), "{error}");
    }

    /// An exported-but-empty variable is the same as unset; systemd user units
    /// pass empty values through often enough that treating them as present
    /// would report a working session on a headless host.
    #[test]
    fn empty_values_count_as_missing() {
        let error = classify_linux_session(env(&[
            ("DBUS_SESSION_BUS_ADDRESS", "  "),
            ("XDG_RUNTIME_DIR", "/run/user/1000"),
            ("DISPLAY", ":0"),
        ]))
        .unwrap_err();
        assert!(error.contains("DBUS_SESSION_BUS_ADDRESS"));
    }

    #[test]
    fn an_x11_session_is_detected() {
        let session = classify_linux_session(env(&[
            ("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"),
            ("XDG_RUNTIME_DIR", "/run/user/1000"),
            ("DISPLAY", ":0"),
        ]))
        .unwrap();
        assert_eq!(session.display_server, DisplayServer::X11);
    }

    #[test]
    fn a_wayland_session_is_detected_from_either_signal() {
        for pairs in [
            vec![
                ("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"),
                ("XDG_RUNTIME_DIR", "/run/user/1000"),
                ("XDG_SESSION_TYPE", "wayland"),
            ],
            vec![
                ("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"),
                ("XDG_RUNTIME_DIR", "/run/user/1000"),
                ("WAYLAND_DISPLAY", "wayland-0"),
            ],
        ] {
            let session = classify_linux_session(env(&pairs)).unwrap();
            assert_eq!(session.display_server, DisplayServer::Wayland);
        }
    }

    /// XWayland sets DISPLAY too. Wayland must win, because that is what limits
    /// synthetic input and screen capture.
    #[test]
    fn wayland_wins_when_both_display_variables_are_set() {
        let session = classify_linux_session(env(&[
            ("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"),
            ("XDG_RUNTIME_DIR", "/run/user/1000"),
            ("WAYLAND_DISPLAY", "wayland-0"),
            ("DISPLAY", ":0"),
        ]))
        .unwrap();
        assert_eq!(session.display_server, DisplayServer::Wayland);
    }

    #[test]
    fn a_bus_without_any_display_is_still_unusable() {
        let error = classify_linux_session(env(&[
            ("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus"),
            ("XDG_RUNTIME_DIR", "/run/user/1000"),
        ]))
        .unwrap_err();
        assert!(error.contains("WAYLAND_DISPLAY"));
    }
}
