use serde::Serialize;

use crate::computer_use::contract::AppInfo;
use crate::computer_use::snapshot_contract::Snapshot;

/// How an action reached the application.
///
/// Reported on every outcome because it changes how much the agent may assume: an
/// accessibility action was accepted by the application itself, while synthetic
/// input was merely delivered to the desktop.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ActionPath {
    Accessibility,
    Synthetic,
    Clipboard,
}

/// Whether the effect of an action was actually observed.
///
/// An agent that cannot tell "done" from "delivered" carries on building work on
/// a step that may never have happened, so the distinction is part of the reply
/// rather than something to infer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verification {
    /// The value was read back and matched.
    Verified { property: String, expected: String },
    /// The action was invoked but its effect could not be confirmed.
    Unverified { reason: UnverifiedReason },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum UnverifiedReason {
    /// An accessibility action was accepted; what it did is for the agent to
    /// read in the returned tree.
    ActionInvoked,
    /// Keyboard or pointer input was handed to the desktop, with no way to know
    /// which window consumed it.
    SyntheticInput,
    /// Text was pasted through the clipboard.
    ClipboardPaste,
    /// The value was written but read back as something else.
    ValueMismatch,
    /// The window changed between the action and the re-read.
    WindowChanged,
}

impl UnverifiedReason {
    pub fn as_str(self) -> &'static str {
        match self {
            UnverifiedReason::ActionInvoked => "action_invoked",
            UnverifiedReason::SyntheticInput => "synthetic_input",
            UnverifiedReason::ClipboardPaste => "clipboard_paste",
            UnverifiedReason::ValueMismatch => "value_mismatch",
            UnverifiedReason::WindowChanged => "window_changed",
        }
    }
}

impl Serialize for Verification {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeMap as _;
        let mut map = serializer.serialize_map(None)?;
        match self {
            Verification::Verified { property, expected } => {
                map.serialize_entry("state", "verified")?;
                map.serialize_entry("property", property)?;
                map.serialize_entry("expected", expected)?;
            }
            Verification::Unverified { reason } => {
                map.serialize_entry("state", "unverified")?;
                map.serialize_entry("reason", reason.as_str())?;
            }
        }
        map.end()
    }
}

/// What happened, and what the window looks like now.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionOutcome {
    pub path: ActionPath,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action_name: Option<String>,
    /// Why a more semantic route was not taken, when one was expected.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
    pub verification: Verification,
    /// The window after the action, so the agent never has to ask for state
    /// before choosing its next element index.
    ///
    /// Absent only when the window went away between the action and the re-read.
    /// The action still happened, and saying so beats reporting a failure the
    /// agent would retry.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snapshot: Option<Snapshot>,
}

/// Which element an action targets.
#[derive(Debug, Clone)]
pub struct ElementRef {
    /// The observation the index came from, which is how a caller keeps two
    /// windows apart. When absent, the newest observation of that app is used.
    ///
    /// It cannot resurrect a superseded read: re-reading a window retires the
    /// indexes it replaced, by id as well as by name.
    pub snapshot_id: Option<String>,
    pub index: usize,
}

/// One thing to do to one element.
#[derive(Debug, Clone)]
pub enum ActionTarget {
    /// Invoke the element's own primary action.
    Click,
    /// Write a value directly, which needs no keyboard focus.
    SetValue { value: String },
    /// Invoke one named accessibility action.
    PerformAction { action: String },
}

impl ActionTarget {
    pub fn verb(&self) -> &'static str {
        match self {
            ActionTarget::Click => "click",
            ActionTarget::SetValue { .. } => "set-value",
            ActionTarget::PerformAction { .. } => "perform-secondary-action",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ActionRequest<'a> {
    pub app: &'a AppInfo,
    pub element: ElementRef,
    pub target: ActionTarget,
    pub include_screenshot: bool,
    /// Keeps one caller's element indexes from resolving against another's
    /// observation.
    pub namespace: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_verified_write_reports_the_property_it_checked() {
        let value = serde_json::to_value(Verification::Verified {
            property: "value".to_string(),
            expected: "alera".to_string(),
        })
        .unwrap();
        assert_eq!(value["state"], "verified");
        assert_eq!(value["property"], "value");
        assert_eq!(value["expected"], "alera");
    }

    /// The agent branches on this, so the reason has to be a stable token rather
    /// than prose.
    #[test]
    fn an_unverified_action_reports_a_machine_readable_reason() {
        let value = serde_json::to_value(Verification::Unverified {
            reason: UnverifiedReason::SyntheticInput,
        })
        .unwrap();
        assert_eq!(value["state"], "unverified");
        assert_eq!(value["reason"], "synthetic_input");
        assert!(value.get("property").is_none());
    }

    #[test]
    fn every_unverified_reason_has_a_snake_case_token() {
        for reason in [
            UnverifiedReason::ActionInvoked,
            UnverifiedReason::SyntheticInput,
            UnverifiedReason::ClipboardPaste,
            UnverifiedReason::ValueMismatch,
            UnverifiedReason::WindowChanged,
        ] {
            let token = reason.as_str();
            assert!(!token.is_empty());
            assert!(token.chars().all(|c| c.is_ascii_lowercase() || c == '_'));
        }
    }

    #[test]
    fn action_paths_serialize_as_the_skill_documents_them() {
        assert_eq!(
            serde_json::to_value(ActionPath::Accessibility).unwrap(),
            "accessibility"
        );
        assert_eq!(
            serde_json::to_value(ActionPath::Synthetic).unwrap(),
            "synthetic"
        );
        assert_eq!(
            serde_json::to_value(ActionPath::Clipboard).unwrap(),
            "clipboard"
        );
    }

    #[test]
    fn targets_name_the_verb_that_produced_them() {
        assert_eq!(ActionTarget::Click.verb(), "click");
        assert_eq!(
            ActionTarget::SetValue {
                value: String::new()
            }
            .verb(),
            "set-value"
        );
        assert_eq!(
            ActionTarget::PerformAction {
                action: "Toggle".to_string()
            }
            .verb(),
            "perform-secondary-action"
        );
    }
}
