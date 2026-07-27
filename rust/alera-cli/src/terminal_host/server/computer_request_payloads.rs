//! Parsing of `computer.*` request payloads.
//!
//! Separate from the dispatch so the rules that turn a caller's JSON into a typed
//! request are testable without a provider, and so the dispatcher stays a list of
//! verbs.

use serde_json::Value;

use crate::computer_use::action_contract::{ActionRequest, ActionTarget, ElementRef};
use crate::computer_use::app_selector::{resolve_app, AppSelector};
use crate::computer_use::contract::{AppInfo, PermissionId};
use crate::computer_use::error::{ComputerError, ComputerResult};
use crate::computer_use::ComputerUseProvider;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn action_request<'a>(
    app: &'a AppInfo,
    payload: &Value,
) -> ComputerResult<ActionRequest<'a>> {
    let index = payload
        .get("elementIndex")
        .and_then(Value::as_u64)
        .and_then(|index| usize::try_from(index).ok())
        .ok_or_else(|| {
            ComputerError::invalid_argument(
                "`elementIndex` is required, and must be an index from the tree you just read.",
            )
        })?;
    let verb = payload
        .get("action")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let target = match verb {
        "click" => ActionTarget::Click,
        "setValue" => ActionTarget::SetValue {
            value: required_string(payload, "value")?,
        },
        "performAction" => ActionTarget::PerformAction {
            action: required_string(payload, "actionName")?,
        },
        other => {
            return Err(ComputerError::invalid_argument(format!(
                "`{other}` is not an action. Use click, setValue, or performAction."
            )))
        }
    };
    Ok(ActionRequest {
        app,
        element: ElementRef {
            snapshot_id: payload
                .get("snapshotId")
                .and_then(Value::as_str)
                .map(str::to_string),
            index,
        },
        target,
        include_screenshot: include_screenshot(payload),
        namespace: namespace(payload),
    })
}

fn required_string(payload: &Value, key: &str) -> ComputerResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| ComputerError::invalid_argument(format!("`{key}` is required.")))
}

pub(super) fn include_screenshot(payload: &Value) -> bool {
    payload
        .get("includeScreenshot")
        .and_then(Value::as_bool)
        .unwrap_or(true)
}

/// Which caller's observations an element index resolves against.
///
/// Two agents working in different workspaces must not share element indexes: a
/// collision there is a click on the wrong control rather than an error, so an
/// absent namespace gets its own bucket instead of a shared default.
pub(super) fn namespace(payload: &Value) -> String {
    payload
        .get("namespace")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("unscoped")
        .to_string()
}

/// Turn the caller's `app` selector into one running application.
///
/// Resolved against a live listing rather than trusted: the pid an agent read a
/// minute ago may belong to something else by now, and the operating system
/// recycles pids freely.
pub(super) async fn resolve_requested_app(
    provider: &dyn ComputerUseProvider,
    payload: &Value,
) -> ComputerResult<AppInfo> {
    let raw = payload
        .get("app")
        .and_then(Value::as_str)
        .ok_or_else(|| ComputerError::invalid_argument("An `app` selector is required."))?;
    let selector = AppSelector::parse(raw)?;
    let apps = provider.list_apps().await?;
    resolve_app(&selector, &apps).cloned()
}

pub(super) fn optional_index(payload: &Value, key: &str) -> ComputerResult<Option<usize>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_u64()
            .and_then(|index| usize::try_from(index).ok())
            .map(Some)
            .ok_or_else(|| {
                ComputerError::invalid_argument(format!("`{key}` must be a non-negative integer."))
            }),
    }
}

/// An unknown permission id is a client bug, not a desktop condition, so it
/// fails as a request error instead of a computer-use outcome.
pub(super) fn parse_permission_id(payload: &Value) -> HostResult<Option<PermissionId>> {
    match payload.get("id") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(raw)) => PermissionId::parse(raw.trim()).map(Some).ok_or_else(|| {
            HostError::state(format!(
                "`{raw}` is not a computer-use permission id. Use accessibility or screenshots."
            ))
        }),
        Some(_) => Err(HostError::state(
            "A computer-use permission id must be a string.",
        )),
    }
}
