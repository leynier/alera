use atspi::proxy::accessible::AccessibleProxy;
use atspi::proxy::proxy_ext::ProxyExt as _;

use crate::computer_use::action_contract::{ActionPath, UnverifiedReason, Verification};
use crate::computer_use::element_signature::signature_parts;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::linux::at_spi_tree::distinct_action_names;
use crate::computer_use::snapshot_contract::ElementRecord;

/// What an action did, before the fresh observation is attached.
pub struct PerformedAction {
    pub path: ActionPath,
    pub action_name: Option<String>,
    pub fallback_reason: Option<String>,
    pub verification: Verification,
}

/// Confirm the live object still matches the element the agent named.
///
/// The path is not identity on its own: a list that gained a row above the
/// target keeps every path resolvable while every path now points one row off.
/// Refusing here is the difference between a recoverable error and a click on
/// someone else's row.
pub async fn ensure_still_matches(
    proxy: &AccessibleProxy<'_>,
    element: &ElementRecord,
) -> ComputerResult<()> {
    let role = proxy.get_role_name().await.unwrap_or_default();
    let name = proxy.name().await.unwrap_or_default();
    let child_count = usize::try_from(proxy.child_count().await.unwrap_or(0)).unwrap_or(0);
    let actions = live_action_names(proxy).await;
    let live = signature_parts(&role, &name, &actions, child_count);
    if live == element.signature {
        return Ok(());
    }
    Err(ComputerError::new(
        ComputerErrorCode::ElementNotFound,
        format!(
            "Element {} changed since it was read: it was `{} {}` and is now `{role} {name}`. \
             Re-read the app state and use an index from that tree.",
            element.index, element.role, element.name
        ),
    ))
}

/// Invoke the element's primary action.
///
/// Semantic before synthetic: an accessibility action is accepted by the
/// application itself, so it works on an unfocused window and cannot land on
/// whatever moved under the pointer.
pub async fn click(proxy: &AccessibleProxy<'_>) -> ComputerResult<PerformedAction> {
    let actions = live_action_names(proxy).await;
    let Some(preferred) = preferred_action_index(&actions) else {
        return Err(ComputerError::new(
            ComputerErrorCode::ElementNotClickable,
            "This element exposes no accessibility action to invoke. Synthetic pointer input \
             is not available in this session, so choose a parent or child element that does."
                .to_string(),
        ));
    };
    let name = actions[preferred].clone();
    invoke(proxy, preferred, &name).await?;
    Ok(PerformedAction {
        path: ActionPath::Accessibility,
        action_name: Some(name),
        fallback_reason: None,
        verification: Verification::Unverified {
            reason: UnverifiedReason::ActionInvoked,
        },
    })
}

/// Invoke one action by name.
pub async fn perform_named(
    proxy: &AccessibleProxy<'_>,
    wanted: &str,
) -> ComputerResult<PerformedAction> {
    let actions = live_action_names(proxy).await;
    let position = actions
        .iter()
        .position(|name| name.eq_ignore_ascii_case(wanted.trim()))
        .ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::ActionNotSupported,
                format!(
                    "`{wanted}` is not an action of this element. It offers: {}.",
                    if actions.is_empty() {
                        "none".to_string()
                    } else {
                        actions.join(", ")
                    }
                ),
            )
        })?;
    let name = actions[position].clone();
    invoke(proxy, position, &name).await?;
    Ok(PerformedAction {
        path: ActionPath::Accessibility,
        action_name: Some(name),
        fallback_reason: None,
        verification: Verification::Unverified {
            reason: UnverifiedReason::ActionInvoked,
        },
    })
}

/// Write a value directly, then read it back.
///
/// Preferred over typing for text fields: it needs no keyboard focus, so it
/// cannot deliver characters to whatever window took focus in between, and it is
/// the one action whose effect can actually be confirmed.
pub async fn set_value(
    proxy: &AccessibleProxy<'_>,
    value: &str,
) -> ComputerResult<PerformedAction> {
    let proxies = proxy.proxies().await.map_err(|error| {
        ComputerError::new(
            ComputerErrorCode::AccessibilityError,
            format!("Could not reach this element's interfaces: {error}"),
        )
    })?;
    let editable = proxies.editable_text().await.map_err(|_| {
        ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            "This element does not expose editable text, so its value cannot be written \
             directly."
                .to_string(),
        )
    })?;
    let accepted = editable.set_text_contents(value).await.map_err(|error| {
        ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            format!("The element refused the value: {error}"),
        )
    })?;
    if !accepted {
        return Err(ComputerError::new(
            ComputerErrorCode::ValueNotSettable,
            "The element refused the value without saying why. Focus it and use keyboard input \
             instead, then inspect the returned state."
                .to_string(),
        ));
    }
    // Read back rather than trust the return: a field with a formatter or an
    // input mask accepts the call and stores something else.
    let readback = match proxies.text().await {
        Ok(text) => text.get_text(0, -1).await.ok(),
        Err(_) => None,
    };
    let verification = match readback {
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
        action_name: Some("setValue".to_string()),
        fallback_reason: None,
        verification,
    })
}

/// Which action `click` should use.
///
/// The first action a toolkit lists is its primary one, but an activation verb is
/// preferred when present: Qt lists `SetFocus` alongside `Press`, and focusing a
/// button is not clicking it.
fn preferred_action_index(actions: &[String]) -> Option<usize> {
    const ACTIVATION: &[&str] = &["click", "press", "activate", "jump", "open", "toggle"];
    if actions.is_empty() {
        return None;
    }
    actions
        .iter()
        .position(|name| ACTIVATION.contains(&name.to_lowercase().trim()))
        .or(Some(0))
}

async fn invoke(proxy: &AccessibleProxy<'_>, index: usize, name: &str) -> ComputerResult<()> {
    let proxies = proxy.proxies().await.map_err(|error| {
        ComputerError::new(
            ComputerErrorCode::AccessibilityError,
            format!("Could not reach this element's interfaces: {error}"),
        )
    })?;
    let action = proxies.action().await.map_err(|_| {
        ComputerError::new(
            ComputerErrorCode::ActionNotSupported,
            "This element exposes no accessibility actions.".to_string(),
        )
    })?;
    let index = i32::try_from(index).map_err(|_| {
        ComputerError::new(
            ComputerErrorCode::ActionNotSupported,
            "The element reports more actions than can be addressed.".to_string(),
        )
    })?;
    match action.do_action(index).await {
        Ok(true) => Ok(()),
        Ok(false) => Err(ComputerError::new(
            ComputerErrorCode::ActionNotSupported,
            format!("The element refused the `{name}` action."),
        )),
        Err(error) => Err(ComputerError::new(
            ComputerErrorCode::AccessibilityError,
            format!("The `{name}` action failed: {error}"),
        )),
    }
}

/// The element's action names as it reports them right now.
async fn live_action_names(proxy: &AccessibleProxy<'_>) -> Vec<String> {
    let Ok(proxies) = proxy.proxies().await else {
        return Vec::new();
    };
    let Ok(action) = proxies.action().await else {
        return Vec::new();
    };
    let Ok(actions) = action.get_actions().await else {
        return Vec::new();
    };
    distinct_action_names(actions.into_iter().map(|action| action.name))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    /// Qt lists SetFocus next to Press. Focusing a button is not clicking it, so
    /// position alone is not enough to pick the action.
    #[test]
    fn an_activation_action_is_preferred_over_the_first_listed() {
        assert_eq!(
            preferred_action_index(&names(&["SetFocus", "Press"])),
            Some(1)
        );
        assert_eq!(
            preferred_action_index(&names(&["SetFocus", "Toggle", "Press"])),
            Some(1)
        );
    }

    #[test]
    fn the_first_action_is_used_when_none_looks_like_activation() {
        assert_eq!(
            preferred_action_index(&names(&["Increase", "Decrease"])),
            Some(0)
        );
    }

    #[test]
    fn matching_the_activation_verb_ignores_case() {
        assert_eq!(preferred_action_index(&names(&["press"])), Some(0));
        assert_eq!(preferred_action_index(&names(&["CLICK"])), Some(0));
    }

    /// Nothing to invoke has to be refused, not approximated: this session has no
    /// synthetic pointer to fall back to.
    #[test]
    fn an_element_with_no_actions_has_nothing_to_click() {
        assert_eq!(preferred_action_index(&[]), None);
    }
}
