use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};

/// Bundle identifiers refused outright, matched exactly.
const BLOCKED_BUNDLE_IDS: &[&str] = &[
    "com.1password.1password",
    "com.1password.safari",
    "com.agilebits.onepassword7",
    "com.bitwarden.desktop",
    "com.dashlane.dashlanephonefinal",
    "com.lastpass.lastpass",
    "com.nordsec.nordpass",
    "me.proton.pass.catalyst",
    "me.proton.pass.electron",
];

/// Name fragments refused on platforms with no stable bundle identifier, where
/// the display name is all the accessibility layer reports.
const BLOCKED_NAME_FRAGMENTS: &[&str] = &[
    "1password",
    "bitwarden",
    "dashlane",
    "keepass",
    "lastpass",
    "nordpass",
    "proton pass",
];

/// Whether this app is off limits for computer use.
///
/// Password managers are refused wholesale rather than redacted field by field:
/// their whole window is the secret, and an agent reading one has already leaked
/// it by the time any per-field rule could apply.
pub fn is_blocked_app(name: &str, bundle_id: Option<&str>) -> bool {
    if let Some(bundle_id) = bundle_id {
        let bundle_id = bundle_id.trim().to_lowercase();
        if BLOCKED_BUNDLE_IDS.contains(&bundle_id.as_str()) {
            return true;
        }
    }
    let name = name.to_lowercase();
    BLOCKED_NAME_FRAGMENTS
        .iter()
        .any(|fragment| name.contains(fragment))
}

/// Reject a blocked app before anything is observed or driven.
pub fn ensure_app_allowed(app: &AppInfo) -> ComputerResult<()> {
    if is_blocked_app(&app.name, app.bundle_id.as_deref()) {
        return Err(ComputerError::new(
            ComputerErrorCode::AppBlocked,
            format!(
                "`{}` is a password manager and is blocked from computer use.",
                app.name
            ),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_password_managers_are_blocked_by_bundle_id() {
        assert!(is_blocked_app("Whatever", Some("com.1password.1password")));
        assert!(is_blocked_app("Whatever", Some("com.bitwarden.desktop")));
        assert!(is_blocked_app("Whatever", Some("me.proton.pass.electron")));
    }

    /// AT-SPI reports no bundle id, so the name is the only thing left to match.
    #[test]
    fn known_password_managers_are_blocked_by_name() {
        assert!(is_blocked_app("1Password", None));
        assert!(is_blocked_app("Bitwarden", None));
        assert!(is_blocked_app("Proton Pass", None));
        assert!(is_blocked_app("KeePassXC", None));
    }

    #[test]
    fn matching_ignores_case_and_surrounding_whitespace() {
        assert!(is_blocked_app("BITWARDEN", None));
        assert!(is_blocked_app("x", Some("  COM.NORDSEC.NORDPASS  ")));
    }

    #[test]
    fn ordinary_apps_are_allowed() {
        assert!(!is_blocked_app("Spotify", Some("com.spotify.client")));
        assert!(!is_blocked_app("Firefox", None));
        assert!(!is_blocked_app(
            "Passwords Tab",
            Some("org.mozilla.firefox")
        ));
    }

    #[test]
    fn a_blocked_app_reports_app_blocked_and_names_itself() {
        let app = AppInfo {
            name: "1Password".to_string(),
            bundle_id: Some("com.1password.1password".to_string()),
            pid: 7,
        };
        let error = ensure_app_allowed(&app).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::AppBlocked);
        assert!(error.message.contains("1Password"));
    }

    #[test]
    fn an_allowed_app_passes_the_gate() {
        let app = AppInfo {
            name: "Spotify".to_string(),
            bundle_id: Some("com.spotify.client".to_string()),
            pid: 8,
        };
        assert!(ensure_app_allowed(&app).is_ok());
    }
}
