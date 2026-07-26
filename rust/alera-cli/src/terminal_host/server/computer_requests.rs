use serde_json::{json, Value};

use super::ServerActor;
use crate::computer_use::contract::PermissionId;
use crate::computer_use::error::ComputerResult;
use crate::computer_use::{active_provider, ComputerUseProvider};
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {
    /// Answer a `computer.*` verb, or report that this is not one.
    ///
    /// Returns `Ok(None)` for an unrelated verb so the caller keeps walking its
    /// dispatch chain, matching how the other request groups hand off.
    pub(super) fn handle_computer_request(
        &mut self,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let outcome = match request_type {
            "computer.capabilities" => capabilities(active_provider().as_ref()),
            "computer.permissions" => permissions(active_provider().as_ref(), payload)?,
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
        Err(error) => json!({ "ok": false, "error": error.to_json() }),
    }
}

fn capabilities(provider: &dyn ComputerUseProvider) -> Value {
    envelope(provider.handshake(), "capabilities", |capabilities| {
        serde_json::to_value(capabilities).unwrap_or_else(|_| json!({}))
    })
}

fn permissions(provider: &dyn ComputerUseProvider, payload: &Value) -> HostResult<Value> {
    let requested = parse_permission_id(payload)?;
    Ok(envelope(provider.permissions(), "permissions", |report| {
        let mut report = report;
        // Filtering here rather than in the provider keeps every platform
        // answering the full set, so a narrowed request cannot hide a grant the
        // provider does know about.
        if let Some(id) = requested {
            report.items.retain(|item| item.id == id);
        }
        serde_json::to_value(report).unwrap_or_else(|_| json!({}))
    }))
}

/// An unknown permission id is a client bug, not a desktop condition, so it
/// fails as a request error instead of a computer-use outcome.
fn parse_permission_id(payload: &Value) -> HostResult<Option<PermissionId>> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::computer_use::contract::{Capabilities, PermissionsReport};
    use crate::computer_use::error::{ComputerError, ComputerErrorCode};
    use crate::computer_use::unsupported_provider::UnsupportedProvider;

    struct FailingProvider;

    impl ComputerUseProvider for FailingProvider {
        fn handshake(&self) -> ComputerResult<Capabilities> {
            Err(ComputerError::new(
                ComputerErrorCode::AccessibilityError,
                "the accessibility bus refused the connection",
            ))
        }

        fn permissions(&self) -> ComputerResult<PermissionsReport> {
            Err(ComputerError::new(
                ComputerErrorCode::PermissionDenied,
                "accessibility is not granted",
            ))
        }
    }

    fn unsupported() -> UnsupportedProvider {
        UnsupportedProvider::new("linux", "alera-computer-use-linux", "no desktop session")
    }

    #[test]
    fn capabilities_answer_even_when_the_session_is_unusable() {
        let value = capabilities(&unsupported());
        assert_eq!(value["ok"], true);
        assert_eq!(value["capabilities"]["supported"], false);
        assert_eq!(
            value["capabilities"]["unsupportedReason"],
            "no desktop session"
        );
    }

    /// The agent needs the code and its recovery steps, so a provider failure
    /// must not collapse into a bare transport error string.
    #[test]
    fn a_provider_failure_is_reported_with_its_code_and_next_steps() {
        let value = capabilities(&FailingProvider);
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "accessibility_error");
        assert!(!value["error"]["nextSteps"].as_array().unwrap().is_empty());
    }

    #[test]
    fn permissions_report_every_grant_by_default() {
        let value = permissions(&unsupported(), &json!({})).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["permissions"]["items"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn a_requested_permission_id_narrows_the_report() {
        let value = permissions(&unsupported(), &json!({ "id": "accessibility" })).unwrap();
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

    #[test]
    fn a_permission_failure_keeps_its_code() {
        let value = permissions(&FailingProvider, &json!({})).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "permission_denied");
    }

    /// A paired phone must never drive the desktop's pointer and keyboard. The
    /// allowlist is a whitelist, so this holds by omission; the test keeps a
    /// later "just add the verb" change from quietly granting it.
    #[test]
    fn mobile_clients_cannot_call_computer_verbs() {
        for verb in [
            "computer.capabilities",
            "computer.permissions",
            "computer.getAppState",
            "computer.act",
        ] {
            assert!(
                !super::super::mobile_terminal_requests::mobile_request_allowed(verb),
                "{verb} must stay off the mobile allowlist"
            );
        }
    }
}
