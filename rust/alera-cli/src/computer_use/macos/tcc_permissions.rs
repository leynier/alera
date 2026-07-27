//! The macOS grants computer use depends on, read without ever asking for them.
//!
//! Checking and prompting are deliberately separate. Agents retry failed
//! observations, and a runtime call that prompted would open a system dialog on
//! every retry; only an explicit setup flow may do that. So these report state
//! and nothing else.

use crate::computer_use::contract::PermissionId;
use crate::computer_use::contract::{PermissionItem, PermissionState};

/// Whether this process may read and drive other applications.
pub fn accessibility_granted() -> bool {
    // SAFETY: no arguments, no out-parameters. The non-prompting variant: the
    // `WithOptions` form is what opens the system dialog.
    unsafe { objc2_application_services::AXIsProcessTrusted() }
}

/// The two grants, as the permission report presents them.
pub fn permission_items() -> Vec<PermissionItem> {
    let accessibility = accessibility_granted();
    vec![
        PermissionItem {
            id: PermissionId::Accessibility,
            label: "Accessibility".to_string(),
            state: if accessibility {
                PermissionState::Granted
            } else {
                PermissionState::Denied
            },
            detail: (!accessibility).then(accessibility_hint),
        },
        PermissionItem {
            id: PermissionId::Screenshots,
            label: "Screen Recording".to_string(),
            // Not asked for at all: nothing captures the screen yet, and probing
            // the capture APIs is itself enough to raise the system prompt.
            state: PermissionState::NotApplicable,
            detail: Some(
                "Screen capture is not implemented on macOS yet, so this grant is not \
                 requested. Read the accessibility tree instead."
                    .to_string(),
            ),
        },
    ]
}

/// What the user has to do, naming the process that needs the grant.
///
/// The grant belongs to the binary that asks, so the message names the runtime
/// host rather than "Alera": a user who grants it to the app bundle and not to
/// the host would see no change.
pub fn accessibility_hint() -> String {
    let executable = std::env::current_exe()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|_| "the Alera runtime host".to_string());
    format!(
        "Accessibility is not granted to this process. Open System Settings > Privacy & \
         Security > Accessibility and allow `{executable}`. macOS grants this per executable, \
         so allowing another copy or another terminal will not carry over. Runtime calls never \
         open the prompt themselves."
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A user who is told only "permission denied" has nowhere to go, so the
    /// hint has to name the pane and the executable.
    #[test]
    fn the_hint_names_the_settings_pane_and_the_executable() {
        let hint = accessibility_hint();
        assert!(hint.contains("Accessibility"));
        assert!(hint.contains("System Settings"));
        assert!(hint.contains("per executable"));
    }

    /// The report answers whatever the machine's state is, and always covers
    /// both grants so a client can render a stable list.
    #[test]
    fn both_grants_are_always_reported() {
        let items = permission_items();
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].id, PermissionId::Accessibility);
        assert_eq!(items[1].id, PermissionId::Screenshots);
        assert_eq!(items[1].state, PermissionState::NotApplicable);
    }

    /// A denied grant must carry its detail, and a granted one must not pretend
    /// something is wrong.
    #[test]
    fn only_a_denied_grant_carries_a_hint() {
        let items = permission_items();
        let accessibility = &items[0];
        match accessibility.state {
            PermissionState::Granted => assert!(accessibility.detail.is_none()),
            _ => assert!(accessibility.detail.is_some()),
        }
    }
}
