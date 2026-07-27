use serde_json::{json, Value};

/// Closed set of computer-use failure codes.
///
/// The set is closed because the skill documents a recovery for every code: an
/// agent that meets an undocumented code has nothing to act on and retries the
/// same call forever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComputerErrorCode {
    AppNotFound,
    AppBlocked,
    WindowNotFound,
    WindowNotFocused,
    WindowStale,
    ProviderIncompatible,
    UnsupportedCapability,
    PermissionDenied,
    ElementNotFound,
    ElementNotClickable,
    ActionNotSupported,
    ValueNotSettable,
    InvalidArgument,
    ActionTimeout,
    ScreenshotFailed,
    AccessibilityError,
}

impl ComputerErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            ComputerErrorCode::AppNotFound => "app_not_found",
            ComputerErrorCode::AppBlocked => "app_blocked",
            ComputerErrorCode::WindowNotFound => "window_not_found",
            ComputerErrorCode::WindowNotFocused => "window_not_focused",
            ComputerErrorCode::WindowStale => "window_stale",
            ComputerErrorCode::ProviderIncompatible => "provider_incompatible",
            ComputerErrorCode::UnsupportedCapability => "unsupported_capability",
            ComputerErrorCode::PermissionDenied => "permission_denied",
            ComputerErrorCode::ElementNotFound => "element_not_found",
            ComputerErrorCode::ElementNotClickable => "element_not_clickable",
            ComputerErrorCode::ActionNotSupported => "action_not_supported",
            ComputerErrorCode::ValueNotSettable => "value_not_settable",
            ComputerErrorCode::InvalidArgument => "invalid_argument",
            ComputerErrorCode::ActionTimeout => "action_timeout",
            ComputerErrorCode::ScreenshotFailed => "screenshot_failed",
            ComputerErrorCode::AccessibilityError => "accessibility_error",
        }
    }

    /// What the agent should do next. Returned with every failure so a model
    /// recovers instead of repeating the call that just failed.
    pub fn next_steps(self) -> &'static [&'static str] {
        match self {
            ComputerErrorCode::AppNotFound => &[
                "Run `list-apps` and retry with the exact name or bundle id it reports.",
                "For a website or web app, target the desktop browser app that shows the page; app selectors name desktop apps, not websites.",
            ],
            ComputerErrorCode::AppBlocked => &[
                "Stop. This app is intentionally blocked from computer use and retrying cannot succeed.",
            ],
            ComputerErrorCode::WindowNotFound => &[
                "Run `list-windows --app <app>` and pass a window selector it reports.",
            ],
            ComputerErrorCode::WindowNotFocused => &[
                "Retry once with `--restore-window`.",
                "If restore was already requested, stop retrying it and bring the window forward manually, or check permissions.",
                "For editable fields prefer `set-value`, which does not need keyboard focus.",
            ],
            ComputerErrorCode::WindowStale => &[
                "Run `list-windows --app <app>` for a current selector, then re-read the app state.",
            ],
            ComputerErrorCode::ProviderIncompatible => &[
                "Update Alera so the runtime host and the computer-use provider match.",
            ],
            ComputerErrorCode::UnsupportedCapability => &[
                "Run `capabilities` to see what this desktop session supports.",
                "Use a supported alternative; if the message names a missing dependency, install it and retry.",
            ],
            ComputerErrorCode::PermissionDenied => &[
                "Run `permissions` to see which grant is missing.",
                "Grant it through the system settings flow, then retry. Runtime calls never open a system prompt on their own.",
            ],
            ComputerErrorCode::ElementNotFound => &[
                "The element index is stale. Re-read the app state and use an index from that fresh tree.",
                "Never carry an index across navigation, scrolling, or a focus change.",
            ],
            ComputerErrorCode::ElementNotClickable => &[
                "This element has no actionable frame. Use a parent or child element that has one.",
                "Otherwise pass window-local coordinates taken from the latest screenshot.",
            ],
            ComputerErrorCode::ActionNotSupported => &[
                "Read the element's listed actions and retry with one of those names.",
                "Use `click` or `set-value` when one of them fits.",
            ],
            ComputerErrorCode::ValueNotSettable => &[
                "This element does not accept a direct value write. Focus it and use keyboard input, then inspect the returned state.",
            ],
            ComputerErrorCode::InvalidArgument => &[
                "Fix the flags and rerun. Do not repeat the same command unchanged.",
            ],
            ComputerErrorCode::ActionTimeout => &[
                "Re-read the current state before retrying.",
                "Then use a simpler semantic action, or pass `--no-screenshot` if capture is what is slow.",
            ],
            ComputerErrorCode::ScreenshotFailed => &[
                "Pass `--no-screenshot` if the accessibility tree is enough.",
                "If the message names a screen-recording grant, run `permissions --id screenshots`.",
            ],
            ComputerErrorCode::AccessibilityError => &[
                "Run `capabilities` to check the provider is usable.",
                "If the message names an accessibility grant, run `permissions --id accessibility`.",
            ],
        }
    }
}

/// A computer-use failure: a code the skill documents, a human message, and the
/// recovery steps for that code.
#[derive(Debug, Clone)]
pub struct ComputerError {
    pub code: ComputerErrorCode,
    pub message: String,
}

impl ComputerError {
    pub fn new(code: ComputerErrorCode, message: impl Into<String>) -> Self {
        ComputerError {
            code,
            message: message.into(),
        }
    }

    pub fn unsupported(message: impl Into<String>) -> Self {
        ComputerError::new(ComputerErrorCode::UnsupportedCapability, message)
    }

    pub fn invalid_argument(message: impl Into<String>) -> Self {
        ComputerError::new(ComputerErrorCode::InvalidArgument, message)
    }

    /// The failure as the agent receives it. Travels inside a successful host
    /// response: a blocked app or a stale index is a normal outcome of the
    /// operation, not a fault of the host connection.
    pub fn to_json(&self) -> Value {
        json!({
            "code": self.code.as_str(),
            "message": self.message,
            "nextSteps": self.code.next_steps(),
        })
    }
}

impl std::fmt::Display for ComputerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code.as_str(), self.message)
    }
}

impl std::error::Error for ComputerError {}

pub type ComputerResult<T> = Result<T, ComputerError>;

#[cfg(test)]
mod tests {
    use super::*;

    const ALL_CODES: &[ComputerErrorCode] = &[
        ComputerErrorCode::AppNotFound,
        ComputerErrorCode::AppBlocked,
        ComputerErrorCode::WindowNotFound,
        ComputerErrorCode::WindowNotFocused,
        ComputerErrorCode::WindowStale,
        ComputerErrorCode::ProviderIncompatible,
        ComputerErrorCode::UnsupportedCapability,
        ComputerErrorCode::PermissionDenied,
        ComputerErrorCode::ElementNotFound,
        ComputerErrorCode::ElementNotClickable,
        ComputerErrorCode::ActionNotSupported,
        ComputerErrorCode::ValueNotSettable,
        ComputerErrorCode::InvalidArgument,
        ComputerErrorCode::ActionTimeout,
        ComputerErrorCode::ScreenshotFailed,
        ComputerErrorCode::AccessibilityError,
    ];

    #[test]
    fn every_code_has_a_snake_case_wire_name() {
        for code in ALL_CODES {
            let name = code.as_str();
            assert!(!name.is_empty());
            assert!(
                name.chars().all(|c| c.is_ascii_lowercase() || c == '_'),
                "{name} is not snake_case"
            );
        }
    }

    #[test]
    fn wire_names_are_unique() {
        let mut names: Vec<&str> = ALL_CODES.iter().map(|code| code.as_str()).collect();
        names.sort_unstable();
        let total = names.len();
        names.dedup();
        assert_eq!(names.len(), total, "duplicate error code wire name");
    }

    /// An agent that receives a code with no recovery retries the same call, so
    /// an empty list is a contract break rather than a missing nicety.
    #[test]
    fn every_code_carries_recovery_steps() {
        for code in ALL_CODES {
            assert!(
                !code.next_steps().is_empty(),
                "{} has no next steps",
                code.as_str()
            );
        }
    }

    #[test]
    fn the_json_shape_carries_code_message_and_next_steps() {
        let error = ComputerError::new(ComputerErrorCode::ElementNotFound, "element 42 is stale");
        let value = error.to_json();
        assert_eq!(value["code"], "element_not_found");
        assert_eq!(value["message"], "element 42 is stale");
        assert!(!value["nextSteps"].as_array().unwrap().is_empty());
    }
}
