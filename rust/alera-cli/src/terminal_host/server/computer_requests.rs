use serde_json::{json, Value};

use super::ServerActor;
use crate::computer_use::error::{ComputerError, ComputerResult};
use crate::computer_use::snapshot_registry;
use crate::computer_use::{active_provider, ComputerUseProvider, SnapshotRequest};
use crate::terminal_host::host_error::HostResult;

use super::computer_request_payloads::{
    action_request, include_screenshot, namespace, optional_index, parse_permission_id,
    resolve_requested_app,
};

impl ServerActor {
    /// Answer a `computer.*` verb, or report that this is not one.
    ///
    /// Returns `Ok(None)` for an unrelated verb so the caller keeps walking its
    /// dispatch chain, matching how the other request groups hand off.
    pub(super) async fn handle_computer_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let provider = active_provider();
        let outcome = match request_type {
            "computer.capabilities" => capabilities(provider.as_ref()).await,
            "computer.permissions" => permissions(provider.as_ref(), payload).await?,
            "computer.listApps" => list_apps(provider.as_ref()).await,
            "computer.listWindows" => list_windows(provider.as_ref(), payload).await,
            "computer.getAppState" => get_app_state(provider.as_ref(), payload).await,
            "computer.act" => act(provider.as_ref(), payload).await,
            _ => return Ok(None),
        };
        Ok(Some(outcome))
    }
}

/// Wrap a computer-use result the way agents read it.
///
/// A failure travels inside a successful host response because a blocked app or
/// a missing desktop session is an outcome of the operation, not a fault of the
/// connection: the transport error channel stays reserved for a host that could
/// not process the request at all, which is what clients treat as fatal.
fn envelope<T>(result: ComputerResult<T>, key: &str, to_value: impl FnOnce(T) -> Value) -> Value {
    match result {
        Ok(value) => json!({ "ok": true, key: to_value(value) }),
        Err(error) => failure(&error),
    }
}

fn failure(error: &ComputerError) -> Value {
    json!({ "ok": false, "error": error.to_json() })
}

fn to_value<T: serde::Serialize>(value: T) -> Value {
    serde_json::to_value(value).unwrap_or_else(|_| json!({}))
}

async fn capabilities(provider: &dyn ComputerUseProvider) -> Value {
    envelope(provider.handshake().await, "capabilities", to_value)
}

async fn permissions(provider: &dyn ComputerUseProvider, payload: &Value) -> HostResult<Value> {
    let requested = parse_permission_id(payload)?;
    Ok(envelope(
        provider.permissions().await,
        "permissions",
        |mut report| {
            // Filtering here rather than in the provider keeps every platform
            // answering the full set, so a narrowed request cannot hide a grant
            // the provider does know about.
            if let Some(id) = requested {
                report.items.retain(|item| item.id == id);
            }
            to_value(report)
        },
    ))
}

async fn list_apps(provider: &dyn ComputerUseProvider) -> Value {
    envelope(provider.list_apps().await, "apps", to_value)
}

async fn list_windows(provider: &dyn ComputerUseProvider, payload: &Value) -> Value {
    match resolve_requested_app(provider, payload).await {
        Err(error) => failure(&error),
        Ok(app) => match provider.list_windows(&app).await {
            Err(error) => failure(&error),
            Ok(windows) => json!({
                "ok": true,
                "app": to_value(&app),
                "windows": to_value(windows),
            }),
        },
    }
}

async fn get_app_state(provider: &dyn ComputerUseProvider, payload: &Value) -> Value {
    let app = match resolve_requested_app(provider, payload).await {
        Err(error) => return failure(&error),
        Ok(app) => app,
    };
    let window_index = match optional_index(payload, "windowIndex") {
        Err(error) => return failure(&error),
        Ok(index) => index,
    };
    let request = SnapshotRequest {
        app: &app,
        window_id: payload.get("windowId").and_then(Value::as_i64),
        window_index,
        include_screenshot: include_screenshot(payload),
    };
    // Remembered here rather than in each provider so every platform's element
    // indexes resolve the same way, and so an observation an agent read is the
    // one its next action addresses.
    let observed = provider.snapshot(request).await;
    if let Ok(snapshot) = &observed {
        snapshot_registry::remember(&namespace(payload), snapshot);
    }
    envelope(observed, "snapshot", to_value)
}

async fn act(provider: &dyn ComputerUseProvider, payload: &Value) -> Value {
    let app = match resolve_requested_app(provider, payload).await {
        Err(error) => return failure(&error),
        Ok(app) => app,
    };
    let request = match action_request(&app, payload) {
        Err(error) => return failure(&error),
        Ok(request) => request,
    };
    envelope(provider.act(request).await, "action", to_value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::computer_use::action_contract::{ActionOutcome, ActionRequest};
    use crate::computer_use::contract::{AppInfo, Capabilities, PermissionId, PermissionsReport};
    use crate::computer_use::error::ComputerErrorCode;
    use crate::computer_use::snapshot_contract::{Snapshot, WindowInfo};
    use crate::computer_use::unsupported_provider::UnsupportedProvider;
    use async_trait::async_trait;

    struct FailingProvider;

    #[async_trait]
    impl ComputerUseProvider for FailingProvider {
        async fn handshake(&self) -> ComputerResult<Capabilities> {
            Err(ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                "the accessibility bus refused the connection",
            ))
        }

        async fn permissions(&self) -> ComputerResult<PermissionsReport> {
            Err(ComputerError::new(
                ComputerErrorCode::PermissionDenied,
                "accessibility is not granted",
            ))
        }

        async fn list_apps(&self) -> ComputerResult<Vec<AppInfo>> {
            Ok(vec![AppInfo {
                name: "Spotify".to_string(),
                bundle_id: None,
                pid: 42,
            }])
        }

        async fn list_windows(&self, _app: &AppInfo) -> ComputerResult<Vec<WindowInfo>> {
            Ok(vec![WindowInfo {
                id: None,
                index: 0,
                title: "Spotify".to_string(),
                bounds: None,
                is_active: true,
            }])
        }

        async fn snapshot(&self, _request: SnapshotRequest<'_>) -> ComputerResult<Snapshot> {
            Err(ComputerError::new(
                ComputerErrorCode::WindowNotFound,
                "no window",
            ))
        }

        async fn act(&self, _request: ActionRequest<'_>) -> ComputerResult<ActionOutcome> {
            Ok(ActionOutcome {
                path: crate::computer_use::action_contract::ActionPath::Accessibility,
                action_name: Some("Press".to_string()),
                fallback_reason: None,
                verification: crate::computer_use::action_contract::Verification::Unverified {
                    reason: crate::computer_use::action_contract::UnverifiedReason::ActionInvoked,
                },
                snapshot: None,
            })
        }
    }

    fn unsupported() -> UnsupportedProvider {
        UnsupportedProvider::new("linux", "alera-computer-use-linux", "no desktop session")
    }

    #[tokio::test]
    async fn capabilities_answer_even_when_the_session_is_unusable() {
        let value = capabilities(&unsupported()).await;
        assert_eq!(value["ok"], true);
        assert_eq!(value["capabilities"]["supported"], false);
        assert_eq!(
            value["capabilities"]["unsupportedReason"],
            "no desktop session"
        );
    }

    /// The agent needs the code and its recovery steps, so a provider failure
    /// must not collapse into a bare transport error string.
    #[tokio::test]
    async fn a_provider_failure_is_reported_with_its_code_and_next_steps() {
        let value = capabilities(&FailingProvider).await;
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "accessibility_error");
        assert!(!value["error"]["nextSteps"].as_array().unwrap().is_empty());
    }

    #[tokio::test]
    async fn permissions_report_every_grant_by_default() {
        let value = permissions(&unsupported(), &json!({})).await.unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["permissions"]["items"].as_array().unwrap().len(), 2);
    }

    #[tokio::test]
    async fn a_requested_permission_id_narrows_the_report() {
        let value = permissions(&unsupported(), &json!({ "id": "accessibility" }))
            .await
            .unwrap();
        let items = value["permissions"]["items"].as_array().unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["id"], "accessibility");
    }

    #[test]
    fn a_blank_or_absent_permission_id_is_accepted() {
        assert_eq!(parse_permission_id(&json!({})).unwrap(), None);
        assert_eq!(parse_permission_id(&json!({ "id": null })).unwrap(), None);
        assert_eq!(
            parse_permission_id(&json!({ "id": " screenshots " })).unwrap(),
            Some(PermissionId::Screenshots)
        );
    }

    #[test]
    fn an_unknown_permission_id_is_a_request_error() {
        assert!(parse_permission_id(&json!({ "id": "camera" })).is_err());
        assert!(parse_permission_id(&json!({ "id": 3 })).is_err());
    }

    #[tokio::test]
    async fn a_permission_failure_keeps_its_code() {
        let value = permissions(&FailingProvider, &json!({})).await.unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "permission_denied");
    }

    #[tokio::test]
    async fn listing_windows_reports_the_app_it_resolved() {
        let value = list_windows(&FailingProvider, &json!({ "app": "spot" })).await;
        assert_eq!(value["ok"], true);
        assert_eq!(value["app"]["pid"], 42);
        assert_eq!(value["windows"][0]["index"], 0);
    }

    /// Without an app selector there is nothing to observe, and guessing one
    /// would drive whichever window happened to be first.
    #[tokio::test]
    async fn a_missing_app_selector_is_an_invalid_argument() {
        let value = list_windows(&FailingProvider, &json!({})).await;
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "invalid_argument");
    }

    #[tokio::test]
    async fn an_unmatched_app_selector_reports_app_not_found() {
        let value = list_windows(&FailingProvider, &json!({ "app": "Gmail" })).await;
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "app_not_found");
    }

    /// Screenshots are on unless declined, so an agent that wants pixels does
    /// not have to know to ask.
    #[test]
    fn a_window_index_must_be_a_non_negative_integer() {
        assert_eq!(optional_index(&json!({}), "windowIndex").unwrap(), None);
        assert_eq!(
            optional_index(&json!({ "windowIndex": 2 }), "windowIndex").unwrap(),
            Some(2)
        );
        assert!(optional_index(&json!({ "windowIndex": -1 }), "windowIndex").is_err());
        assert!(optional_index(&json!({ "windowIndex": "two" }), "windowIndex").is_err());
    }

    #[tokio::test]
    async fn a_snapshot_failure_keeps_its_code() {
        let value = get_app_state(&FailingProvider, &json!({ "app": "Spotify" })).await;
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "window_not_found");
    }

    fn app() -> AppInfo {
        AppInfo {
            name: "Spotify".to_string(),
            bundle_id: None,
            pid: 42,
        }
    }

    /// An action without an element index has no target. Defaulting to zero would
    /// act on the window itself, which is not what any caller meant.
    #[test]
    fn an_action_without_an_element_index_is_refused() {
        let app = app();
        let error = action_request(&app, &json!({ "action": "click" })).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::InvalidArgument);
        assert!(error.message.contains("elementIndex"));
    }

    #[test]
    fn an_unknown_action_verb_is_refused_by_name() {
        let app = app();
        let error =
            action_request(&app, &json!({ "elementIndex": 1, "action": "explode" })).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::InvalidArgument);
        assert!(error.message.contains("explode"));
    }

    #[test]
    fn set_value_needs_a_value_and_perform_action_needs_a_name() {
        let app = app();
        assert!(action_request(&app, &json!({ "elementIndex": 1, "action": "setValue" })).is_err());
        assert!(action_request(
            &app,
            &json!({ "elementIndex": 1, "action": "performAction" })
        )
        .is_err());
        assert!(action_request(
            &app,
            &json!({ "elementIndex": 1, "action": "setValue", "value": "x" })
        )
        .is_ok());
    }

    #[test]
    fn an_action_carries_the_snapshot_id_and_namespace_it_was_given() {
        let app = app();
        let request = action_request(
            &app,
            &json!({
                "elementIndex": 4,
                "action": "click",
                "snapshotId": "s1",
                "namespace": " ws1 ",
            }),
        )
        .unwrap();
        assert_eq!(request.element.index, 4);
        assert_eq!(request.element.snapshot_id.as_deref(), Some("s1"));
        assert_eq!(request.namespace, "ws1");
        assert!(request.include_screenshot);
    }

    /// Two callers without a namespace must not land in a shared bucket, because
    /// a collision there is a click on the wrong control rather than an error.
    #[test]
    fn a_missing_namespace_does_not_become_a_shared_default() {
        assert_eq!(namespace(&json!({})), "unscoped");
        assert_eq!(namespace(&json!({ "namespace": "   " })), "unscoped");
        assert_eq!(namespace(&json!({ "namespace": "ws1" })), "ws1");
    }

    /// A paired phone must never drive the desktop's pointer and keyboard. The
    /// allowlist is a whitelist, so this holds by omission; the test keeps a
    /// later "just add the verb" change from quietly granting it.
    #[test]
    fn mobile_clients_cannot_call_computer_verbs() {
        for verb in [
            "computer.capabilities",
            "computer.permissions",
            "computer.listApps",
            "computer.listWindows",
            "computer.getAppState",
            "computer.act",
        ] {
            assert!(
                !super::super::mobile_gateway_surface::mobile_request_allowed(verb),
                "{verb} must stay off the mobile allowlist"
            );
        }
    }
}
