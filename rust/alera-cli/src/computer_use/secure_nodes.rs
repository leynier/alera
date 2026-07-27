use crate::computer_use::snapshot_contract::RawNode;

/// What replaces the text of a concealed field.
pub const REDACTED: &str = "[redacted]";

/// Roles that always conceal their content, whatever they are called.
const SECURE_ROLES: &[&str] = &["password text", "password_text", "passwordtext"];

/// Words that mark a field as holding a secret. Matched against the role, the
/// name, and the description, because which one carries the hint differs by
/// toolkit: GTK puts it in the name, Qt often only in the description.
const SECURE_HINTS: &[&str] = &[
    "password",
    "passwd",
    "passcode",
    "secret",
    "one-time code",
    "one time code",
    "verification code",
    "security code",
    "cvv",
    "otp",
];

/// Roles that hold text an agent would read back.
///
/// The word hints are limited to these because redaction protects content, and
/// only these roles have any. A button or checkbox named "Password" holds no
/// secret, and concealing it hides a control the agent needs: KRunner's "Pin"
/// checkbox was redacted this way before the rule was narrowed.
const TEXT_INPUT_ROLES: &[&str] = &[
    // AT-SPI spellings.
    "text",
    "entry",
    "editable text",
    "password text",
    "password_text",
    "passwordtext",
    "paragraph",
    // UI Automation spellings. A Windows password box is an ordinary `edit`
    // whose IsPassword property is set, which the provider maps to the platform
    // flag; the word hints still cover fields that do not set it.
    "edit",
    "document",
    "combo box",
];

/// Whether this node's text must never be reported.
///
/// The platform's own flag and the password role are trusted outright; the word
/// list is what catches the common case they miss, a web form whose input is
/// marked `type=password` in the DOM but exposed as an ordinary text field.
pub fn is_secure_node(node: &RawNode) -> bool {
    if node.protected {
        return true;
    }
    let role = node.role.to_lowercase();
    if SECURE_ROLES.contains(&role.as_str()) {
        return true;
    }
    if !TEXT_INPUT_ROLES.contains(&role.as_str()) {
        return false;
    }
    let haystack = format!(
        "{} {} {}",
        role,
        node.name.to_lowercase(),
        node.description
            .as_deref()
            .unwrap_or_default()
            .to_lowercase()
    );
    if SECURE_HINTS.iter().any(|hint| haystack.contains(hint)) {
        return true;
    }
    mentions_a_pin(&haystack)
}

/// `pin` as a standalone word only.
///
/// A substring match would redact half a desktop: "spinner", "pinned tab", and
/// "Pinterest" all contain it.
fn mentions_a_pin(haystack: &str) -> bool {
    haystack
        .split(|c: char| !c.is_ascii_alphanumeric())
        .any(|word| word == "pin")
}

/// The name to report for a node, concealed when it must be.
pub fn redacted_name(node: &RawNode, secure: bool) -> String {
    if secure && !node.name.trim().is_empty() {
        return REDACTED.to_string();
    }
    node.name.clone()
}

/// The value to report for a node.
///
/// A secure field reports no value at all rather than a redacted placeholder:
/// the length of a password is itself worth withholding, and the agent has no
/// use for it.
pub fn redacted_value(node: &RawNode, secure: bool) -> Option<String> {
    if secure {
        return None;
    }
    node.value.clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(role: &str, name: &str) -> RawNode {
        RawNode::named(role, name)
    }

    #[test]
    fn the_platform_protected_flag_is_enough() {
        let mut plain = node("push button", "Search");
        assert!(!is_secure_node(&plain));
        plain.protected = true;
        assert!(is_secure_node(&plain));
    }

    #[test]
    fn a_password_role_is_secure_however_it_is_spelled() {
        for role in ["password text", "PASSWORD_TEXT", "passwordtext"] {
            assert!(is_secure_node(&node(role, "")), "{role}");
        }
    }

    #[test]
    fn secret_words_in_the_name_are_caught() {
        for name in [
            "Password",
            "Confirm passcode",
            "One-time code",
            "Verification code",
            "CVV",
            "Client secret",
            "OTP",
        ] {
            assert!(is_secure_node(&node("entry", name)), "{name}");
        }
    }

    /// Qt frequently leaves the name blank and describes the field instead.
    #[test]
    fn secret_words_in_the_description_are_caught() {
        let mut field = node("entry", "");
        field.description = Some("Enter your account password".to_string());
        assert!(is_secure_node(&field));
    }

    #[test]
    fn a_pin_field_is_secure() {
        assert!(is_secure_node(&node("entry", "PIN")));
        assert!(is_secure_node(&node("entry", "Enter pin")));
        assert!(is_secure_node(&node("entry", "Card PIN:")));
    }

    /// Found against a real desktop: KRunner's "Pin" checkbox came back
    /// concealed, hiding a control the agent needs. Only text-bearing roles can
    /// hold a secret worth withholding.
    #[test]
    fn controls_that_hold_no_text_are_never_concealed() {
        for role in ["check box", "push button", "toggle button", "menu item"] {
            assert!(!is_secure_node(&node(role, "Pin")), "{role} Pin");
            assert!(!is_secure_node(&node(role, "Password")), "{role} Password");
            assert!(!is_secure_node(&node(role, "Show secret")), "{role} secret");
        }
    }

    /// The platform flag still wins, whatever the role: a toolkit that says a
    /// node is concealed knows better than a role list.
    #[test]
    fn a_protected_control_is_concealed_whatever_its_role() {
        let mut checkbox = node("check box", "Pin");
        checkbox.protected = true;
        assert!(is_secure_node(&checkbox));
    }

    /// Redacting every word containing "pin" would blank out ordinary UI.
    #[test]
    fn words_merely_containing_pin_stay_visible() {
        for name in ["Spinner", "Pinned Tabs", "Pinterest", "Shipping"] {
            assert!(!is_secure_node(&node("entry", name)), "{name}");
        }
    }

    #[test]
    fn ordinary_fields_are_not_secure() {
        for name in ["Search", "Email", "Address line 1", "Message"] {
            assert!(!is_secure_node(&node("entry", name)), "{name}");
        }
    }

    #[test]
    fn a_secure_name_is_replaced_and_an_empty_one_is_left_alone() {
        let named = node("entry", "Password");
        assert_eq!(redacted_name(&named, true), REDACTED);
        assert_eq!(redacted_name(&named, false), "Password");
        assert_eq!(redacted_name(&node("entry", "   "), true), "   ");
    }

    /// A placeholder would still leak the length of the secret.
    #[test]
    fn a_secure_value_is_dropped_rather_than_masked() {
        let mut field = node("entry", "Password");
        field.value = Some("hunter2".to_string());
        assert_eq!(redacted_value(&field, true), None);
        assert_eq!(redacted_value(&field, false), Some("hunter2".to_string()));
    }
}
