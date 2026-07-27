use uiautomation::patterns::{
    UIInvokePattern, UISelectionItemPattern, UITogglePattern, UIValuePattern,
};
use uiautomation::UIElement;

use crate::computer_use::action_contract::{ActionPath, UnverifiedReason, Verification};
use crate::computer_use::element_signature::signature_parts;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_contract::ElementRecord;
use crate::computer_use::windows::uia_tree::{available_actions, role_of, UiaSession};

/// What an action did, before the fresh observation is attached.
pub struct PerformedAction {
    pub path: ActionPath,
    pub action_name: Option<String>,
    pub fallback_reason: Option<String>,
    pub verification: Verification,
}

/// Confirm the live element still matches the one the agent named.
///
/// The child-index path is not identity: a list that gained a row above the
/// target keeps every path resolvable while every path points one row off.
pub fn ensure_still_matches(
    session: &UiaSession,
    element: &UIElement,
    record: &ElementRecord,
) -> ComputerResult<()> {
    let live = signature_parts(
        &role_of(element),
        &element.get_name().unwrap_or_default(),
        &available_actions(element),
        session.child_count(element),
    );
    if live == record.signature {
        return Ok(());
    }
    Err(ComputerError::new(
        ComputerErrorCode::ElementNotFound,
        format!(
            "Element {} changed since it was read: it was `{} {}` and is now `{} {}`. \
             Re-read the app state and use an index from that tree.",
            record.index,
            record.role,
            record.name,
            role_of(element),
            element.get_name().unwrap_or_default()
        ),
    ))
}

/// Invoke the element's primary action.
///
/// UI Automation models capabilities as patterns rather than a list of verbs, so
/// the order here is the semantic one: invoking is what a click means, toggling
/// and selecting are what a click means for controls that have no Invoke.
pub fn click(element: &UIElement) -> ComputerResult<PerformedAction> {
    if let Ok(invoke) = element.get_pattern::<UIInvokePattern>() {
        invoke.invoke().map_err(|error| failed("Invoke", error))?;
        return Ok(accessibility("Invoke"));
    }
    if let Ok(toggle) = element.get_pattern::<UITogglePattern>() {
        toggle.toggle().map_err(|error| failed("Toggle", error))?;
        return Ok(accessibility("Toggle"));
    }
    if let Ok(selection) = element.get_pattern::<UISelectionItemPattern>() {
        selection
            .select()
            .map_err(|error| failed("Select", error))?;
        return Ok(accessibility("Select"));
    }
    Err(ComputerError::new(
        ComputerErrorCode::ElementNotClickable,
        "This element exposes no invoke, toggle, or selection pattern. Choose a parent or \
         child element that does."
            .to_string(),
    ))
}

/// Invoke one action by the name the tree listed.
pub fn perform_named(element: &UIElement, wanted: &str) -> ComputerResult<PerformedAction> {
    let wanted = wanted.trim();
    let available = available_actions(element);
    if !available
        .iter()
        .any(|name| name.eq_ignore_ascii_case(wanted))
    {
        return Err(ComputerError::new(
            ComputerErrorCode::ActionNotSupported,
            format!(
                "`{wanted}` is not an action of this element. It offers: {}.",
                if available.is_empty() {
                    "none".to_string()
                } else {
                    available.join(", ")
                }
            ),
        ));
    }
    match wanted.to_lowercase().as_str() {
        "invoke" => element
            .get_pattern::<UIInvokePattern>()
            .and_then(|pattern| pattern.invoke())
            .map(|_| accessibility("Invoke"))
            .map_err(|error| failed("Invoke", error)),
        "toggle" => element
            .get_pattern::<UITogglePattern>()
            .and_then(|pattern| pattern.toggle())
            .map(|_| accessibility("Toggle"))
            .map_err(|error| failed("Toggle", error)),
        "select" => element
            .get_pattern::<UISelectionItemPattern>()
            .and_then(|pattern| pattern.select())
            .map(|_| accessibility("Select"))
            .map_err(|error| failed("Select", error)),
        "setfocus" => element
            .set_focus()
            .map(|_| accessibility("SetFocus"))
            .map_err(|error| failed("SetFocus", error)),
        "setvalue" => Err(ComputerError::invalid_argument(
            "Use `set-value --value <text>` to write a value.".to_string(),
        )),
        other => Err(ComputerError::new(
            ComputerErrorCode::ActionNotSupported,
            format!("`{other}` cannot be invoked on this platform."),
        )),
    }
}

/// Write a value through the Value pattern, then read it back.
pub fn set_value(element: &UIElement, value: &str) -> ComputerResult<PerformedAction> {
    let pattern = element.get_pattern::<UIValuePattern>().map_err(|_| {
        ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            "This element does not expose a value, so it cannot be written directly.".to_string(),
        )
    })?;
    if pattern.is_readonly().unwrap_or(false) {
        return Err(ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            "This element's value is read-only.".to_string(),
        ));
    }
    pattern.set_value(value).map_err(|error| {
        ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            format!("The element refused the value: {error}"),
        )
    })?;
    // Read back rather than trust the call: a field with a mask or a formatter
    // accepts the write and stores something else.
    let verification = match pattern.get_value() {
        Ok(actual) if actual == value => Verification::Verified {
            property: "value".to_string(),
            expected: value.to_string(),
        },
        Ok(_) => Verification::Unverified {
            reason: UnverifiedReason::ValueMismatch,
        },
        Err(_) => Verification::Unverified {
            reason: UnverifiedReason::ActionInvoked,
        },
    };
    Ok(PerformedAction {
        path: ActionPath::Accessibility,
        action_name: Some("SetValue".to_string()),
        fallback_reason: None,
        verification,
    })
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

fn failed(name: &str, error: uiautomation::Error) -> ComputerError {
    ComputerError::new(
        ComputerErrorCode::AccessibilityError,
        format!("The `{name}` action failed: {error}"),
    )
}
