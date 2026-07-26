use objc2_application_services::AXUIElement;
use objc2_core_foundation::CFString;

use crate::computer_use::action_contract::{ActionPath, UnverifiedReason, Verification};
use crate::computer_use::element_signature::signature_parts;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::macos::ax_attributes::{action_names, element_children, string_attribute};
use crate::computer_use::macos::ax_tree::role_of;
use crate::computer_use::snapshot_contract::ElementRecord;

/// What an action did, before the fresh observation is attached.
pub struct PerformedAction {
    pub path: ActionPath,
    pub action_name: Option<String>,
    pub fallback_reason: Option<String>,
    pub verification: Verification,
}

/// Actions that mean "activate this", in the order they should be preferred.
///
/// `AXPress` is the usual one; a few controls only offer `AXConfirm` or
/// `AXPick`, and focusing is never activating.
const ACTIVATION_ACTIONS: &[&str] = &["AXPress", "AXConfirm", "AXPick", "AXOpen", "AXIncrement"];

/// Confirm the live element still matches the one the agent named.
pub fn ensure_still_matches(element: &AXUIElement, record: &ElementRecord) -> ComputerResult<()> {
    let role = role_of(element);
    let name = element_label(element);
    let live = signature_parts(
        &role,
        &name,
        &action_names(element),
        element_children(element).len(),
    );
    if live == record.signature {
        return Ok(());
    }
    Err(ComputerError::new(
        ComputerErrorCode::ElementNotFound,
        format!(
            "Element {} changed since it was read: it was `{} {}` and is now `{role} {name}`. \
             Re-read the app state and use an index from that tree.",
            record.index, record.role, record.name
        ),
    ))
}

/// Invoke the element's primary action.
pub fn click(element: &AXUIElement) -> ComputerResult<PerformedAction> {
    let available = action_names(element);
    let chosen = ACTIVATION_ACTIONS
        .iter()
        .find(|candidate| available.iter().any(|name| name == *candidate))
        .map(|name| (*name).to_string())
        .or_else(|| available.first().cloned())
        .ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::ElementNotClickable,
                "This element exposes no accessibility action to invoke. Choose a parent or \
                 child element that does."
                    .to_string(),
            )
        })?;
    perform(element, &chosen)?;
    Ok(accessibility(&chosen))
}

/// Invoke one action by the name the tree listed.
pub fn perform_named(element: &AXUIElement, wanted: &str) -> ComputerResult<PerformedAction> {
    let wanted = wanted.trim();
    let available = action_names(element);
    let matched = available
        .iter()
        .find(|name| name.eq_ignore_ascii_case(wanted))
        .cloned()
        .ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::ActionNotSupported,
                format!(
                    "`{wanted}` is not an action of this element. It offers: {}.",
                    if available.is_empty() {
                        "none".to_string()
                    } else {
                        available.join(", ")
                    }
                ),
            )
        })?;
    perform(element, &matched)?;
    Ok(accessibility(&matched))
}

/// Write a value, then read it back.
pub fn set_value(element: &AXUIElement, value: &str) -> ComputerResult<PerformedAction> {
    let key = CFString::from_str("AXValue");
    let new_value = CFString::from_str(value);
    // SAFETY: both Core Foundation objects outlive the call, which copies what it
    // needs.
    let error = unsafe { element.set_attribute_value(&key, &new_value) };
    if error.0 != 0 {
        return Err(ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            format!(
                "The element refused the value (AXError {}). Focus it and use keyboard input \
                 instead, then inspect the returned state.",
                error.0
            ),
        ));
    }
    // Read back rather than trust the return code: a field with a formatter
    // accepts the write and stores something else.
    let verification = match string_attribute(element, "AXValue") {
        Some(actual) if actual == value => Verification::Verified {
            property: "value".to_string(),
            expected: value.to_string(),
        },
        Some(_) => Verification::Unverified {
            reason: UnverifiedReason::ValueMismatch,
        },
        None => Verification::Unverified {
            reason: UnverifiedReason::ActionInvoked,
        },
    };
    Ok(PerformedAction {
        path: ActionPath::Accessibility,
        action_name: Some("AXSetValue".to_string()),
        fallback_reason: None,
        verification,
    })
}

fn perform(element: &AXUIElement, action: &str) -> ComputerResult<()> {
    let name = CFString::from_str(action);
    // SAFETY: `name` outlives the call.
    let error = unsafe { element.perform_action(&name) };
    match error.0 {
        0 => Ok(()),
        // -25204 is kAXErrorCannotComplete, which is what an application returns
        // when it is busy or not responding rather than when the action is wrong.
        -25204 => Err(ComputerError::new(
            ComputerErrorCode::ActionTimeout,
            format!("The application did not complete `{action}`. Re-read its state and retry."),
        )),
        code => Err(ComputerError::new(
            ComputerErrorCode::AccessibilityError,
            format!("The `{action}` action failed with AXError {code}."),
        )),
    }
}

fn accessibility(name: &str) -> PerformedAction {
    PerformedAction {
        path: ActionPath::Accessibility,
        action_name: Some(name.to_string()),
        fallback_reason: None,
        verification: Verification::Unverified {
            reason: UnverifiedReason::ActionInvoked,
        },
    }
}

/// The same label the tree reader chose, so a signature computed here matches
/// the one computed there.
fn element_label(element: &AXUIElement) -> String {
    for attribute_name in ["AXTitle", "AXLabel", "AXDescription"] {
        if let Some(text) = string_attribute(element, attribute_name) {
            if !text.trim().is_empty() {
                return text;
            }
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Focusing a control is not activating it, so an activation verb has to win
    /// over whatever the platform happened to list first.
    #[test]
    fn activation_actions_are_ordered_before_the_rest() {
        assert_eq!(ACTIVATION_ACTIONS[0], "AXPress");
        assert!(!ACTIVATION_ACTIONS.contains(&"AXSetFocus"));
        assert!(!ACTIVATION_ACTIONS.contains(&"AXShowMenu"));
    }
}
