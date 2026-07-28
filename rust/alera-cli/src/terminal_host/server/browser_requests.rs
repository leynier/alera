use chrono::Utc;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{event, ok_response};

use super::browser_artifact_requests::{
    finalize_capture_outcome, normalize_browser_outcome, prepare_browser_call_params,
    remove_browser_artifact,
};
use super::browser_broker::{BrowserCall, BrowserDrain, RemovedBrowserCall};
use super::browser_catalog_requests::browser_failure;
use super::client_delivery::LocalClientRole;
use super::requests::{optional_string_key, require_string_key};
use super::{ClientKind, ServerActor, ServerCommand};

const DEFAULT_BROWSER_TIMEOUT_MS: u64 = 30_000;
const MAX_BROWSER_TIMEOUT_MS: u64 = 600_000;

impl ServerActor {
    pub(super) async fn handle_browser_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        self.sweep_browser_deadlines();
        if let Some(value) = self
            .handle_browser_catalog_request(request_type, payload)
            .await?
        {
            return Ok(Some(value));
        }
        if let Some(value) = self
            .handle_browser_tab_request(request_type, payload)
            .await?
        {
            return Ok(Some(value));
        }
        if let Some(value) = self
            .handle_browser_driver_request(client_id, request_type, payload)
            .await?
        {
            return Ok(Some(value));
        }
        match request_type {
            "browser.capabilities" => Ok(Some(json!({
                "ok": true,
                "routing": {
                    "registeredDrivers": self.browser.pages().iter()
                        .map(|page| page.owner_client_id)
                        .collect::<std::collections::HashSet<_>>()
                        .len(),
                    "activePages": self.browser.pages(),
                    "activeJobs": self.browser.active_jobs(),
                    "maxCallsPerTab": super::browser_broker::MAX_BROWSER_CALLS_PER_TAB,
                    "maxCallsTotal": super::browser_broker::MAX_BROWSER_CALLS_TOTAL,
                    "maxTimeoutMs": MAX_BROWSER_TIMEOUT_MS,
                }
            }))),
            "browser.cancel" => {
                let correlation_id = require_string_key(payload, "correlationId")?;
                let Some(call) = self.browser.call(&correlation_id) else {
                    return Ok(Some(browser_failure(
                        "request_not_found",
                        format!("Browser request {correlation_id} is no longer active."),
                        &["Discard the cancellation; the request already finished."],
                    )));
                };
                if call.requester_client_id != client_id {
                    return Ok(Some(browser_failure(
                        "not_request_owner",
                        "Only the connection that started a browser request may cancel it."
                            .to_string(),
                        &["Cancel the request from its original client connection."],
                    )));
                }
                let drain = self.browser.remove_correlation(&correlation_id);
                self.apply_browser_drain(
                    drain,
                    browser_failure_value(
                        "cancelled",
                        "The browser request was cancelled.",
                        &["Start a new request if the operation is still needed."],
                    ),
                );
                Ok(Some(json!({
                    "ok": true,
                    "cancelled": true,
                    "correlationId": correlation_id,
                })))
            }
            request_type if is_routed_browser_request(request_type) => {
                self.start_browser_call(client_id, request_id, request_type, payload)
            }
            _ => Err(HostError::state(format!(
                "Unknown browser host request: {request_type}"
            ))),
        }
    }

    fn start_browser_call(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Option<Value>> {
        let tab_id = browser_page_id(payload)?;
        let Some(page) = self.browser.page(&tab_id).cloned() else {
            return Ok(Some(browser_failure(
                "page_unavailable",
                format!("Browser tab {tab_id} has no registered app page."),
                &["Open or focus the tab in the Alera desktop app and retry."],
            )));
        };
        let timeout_ms = payload
            .get("timeoutMs")
            .and_then(Value::as_u64)
            .unwrap_or(DEFAULT_BROWSER_TIMEOUT_MS)
            .clamp(1, MAX_BROWSER_TIMEOUT_MS);
        let correlation_id = Uuid::new_v4().to_string();
        let params = match prepare_browser_call_params(
            &self.runtime_dir,
            request_type,
            payload,
            &correlation_id,
        ) {
            Ok(params) => params,
            Err(error) => {
                return Ok(Some(artifact_reservation_failure(&error)));
            }
        };
        let call = BrowserCall {
            correlation_id: correlation_id.clone(),
            requester_client_id: client_id,
            requester_request_id: request_id,
            owner_client_id: page.owner_client_id,
            request_type: request_type.to_string(),
            tab_id,
            generation: page.generation,
            params,
            deadline_at_ms: Utc::now()
                .timestamp_millis()
                .saturating_add(timeout_ms as i64),
        };
        match self.browser.enqueue(call.clone()) {
            Ok(enqueued) => {
                self.cancel_shutdown_timer();
                self.schedule_browser_timeout(correlation_id, timeout_ms);
                if enqueued.dispatch_now {
                    self.dispatch_browser_call(&enqueued.call);
                }
                Ok(None)
            }
            Err(error) => {
                remove_browser_artifact(&self.runtime_dir, &call);
                Ok(Some(error.payload()))
            }
        }
    }

    fn schedule_browser_timeout(&self, correlation_id: String, timeout_ms: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(timeout_ms)).await;
            let _ = inbox.send(ServerCommand::BrowserRequestTimeout { correlation_id });
        });
    }

    fn dispatch_browser_call(&self, call: &BrowserCall) {
        let driver_instance_id = self
            .browser
            .driver(call.owner_client_id)
            .map(|driver| driver.driver_instance_id.clone());
        self.client_write(
            call.owner_client_id,
            event(
                "browserDriverRequest",
                json!({
                    "correlationId": call.correlation_id,
                    "pageId": call.tab_id,
                    "tabId": call.tab_id,
                    "generation": call.generation,
                    "method": call.request_type,
                    "params": call.params,
                    "deadlineAt": call.deadline_at_ms,
                    "driverInstanceId": driver_instance_id,
                }),
            ),
        );
    }

    pub(super) fn apply_browser_drain(&mut self, drain: BrowserDrain, failure: Value) {
        for removed in drain.removed {
            self.finish_removed_browser_call(removed, &failure);
        }
        for call in drain.promoted {
            self.dispatch_browser_call(&call);
        }
        self.schedule_shutdown_if_idle();
    }

    fn finish_removed_browser_call(&self, removed: RemovedBrowserCall, failure: &Value) {
        remove_browser_artifact(&self.runtime_dir, &removed.call);
        if removed.was_in_flight {
            self.client_write(
                removed.call.owner_client_id,
                event(
                    "browserDriverCancel",
                    json!({
                        "correlationId": removed.call.correlation_id,
                        "pageId": removed.call.tab_id,
                        "generation": removed.call.generation,
                    }),
                ),
            );
        }
        if self.clients.contains_key(&removed.call.requester_client_id) {
            self.client_write(
                removed.call.requester_client_id,
                ok_response(removed.call.requester_request_id, failure.clone()),
            );
        }
    }

    pub(super) fn handle_browser_timeout(&mut self, correlation_id: &str) {
        let drain = self.browser.remove_correlation(correlation_id);
        if drain.removed.is_empty() {
            return;
        }
        self.apply_browser_drain(
            drain,
            browser_failure_value(
                "timeout",
                "The browser driver did not finish before the request deadline.",
                &[
                    "Do not assume a timed-out mutation was rolled back.",
                    "Wait for the native operation to drain before retrying.",
                ],
            ),
        );
    }

    fn sweep_browser_deadlines(&mut self) {
        let expired = self
            .browser
            .expired_correlations(Utc::now().timestamp_millis());
        for correlation_id in expired {
            self.handle_browser_timeout(&correlation_id);
        }
    }

    pub(super) fn handle_browser_client_disconnect(&mut self, client_id: u64) {
        let requester_drain = self.browser.remove_requester(client_id);
        self.apply_browser_drain(
            requester_drain,
            browser_failure_value(
                "requester_disconnected",
                "The browser request owner disconnected.",
                &["Start a new request from a connected client."],
            ),
        );
        let owner_drain = self.browser.remove_driver(client_id);
        self.apply_browser_drain(
            owner_drain,
            browser_failure_value(
                "driver_disconnected",
                "The Alera app connection that owned this page disconnected.",
                &["Wait for the desktop app to reconnect and synchronize its pages."],
            ),
        );
    }

    pub(super) fn handle_browser_tab_removed(&mut self, tab_id: &str) {
        let drain = self.browser.remove_page(tab_id);
        self.apply_browser_drain(
            drain,
            browser_failure_value(
                "page_closed",
                format!("Browser tab {tab_id} was closed."),
                &["Choose another browser tab and retry."],
            ),
        );
    }

    pub(super) fn require_browser_app_client(&self, client_id: u64) -> HostResult<()> {
        match self.clients.get(&client_id) {
            Some(client)
                if client.authenticated
                    && client.kind == ClientKind::Local
                    && client.local_role == LocalClientRole::App =>
            {
                Ok(())
            }
            _ => Err(HostError::state(
                "Browser driver requests require a local app client.",
            )),
        }
    }

    pub(super) fn respond_browser_completion(
        &mut self,
        completion: super::browser_broker::BrowserCompletion,
        mut outcome: Value,
    ) {
        normalize_browser_outcome(&mut outcome);
        if completion.call.request_type == "browser.cookies.list" {
            strip_cookie_values(&mut outcome);
        }
        if let Some(failure) =
            finalize_capture_outcome(&self.runtime_dir, &completion.call, &mut outcome)
        {
            outcome = browser_failure_value(failure.code, failure.message, failure.next_steps);
        }
        self.client_write(
            completion.call.requester_client_id,
            ok_response(completion.call.requester_request_id, outcome),
        );
        if let Some(call) = completion.promoted {
            self.dispatch_browser_call(&call);
        }
        self.schedule_shutdown_if_idle();
    }
}

pub(super) fn browser_page_id(payload: &Value) -> HostResult<String> {
    optional_string_key(payload, "pageId")
        .or_else(|| optional_string_key(payload, "tabId"))
        .ok_or_else(|| HostError::format("pageId is required."))
}

fn browser_failure_value(code: &str, message: impl Into<String>, next_steps: &[&str]) -> Value {
    browser_failure(code, message.into(), next_steps)
}

fn artifact_reservation_failure(error: &std::io::Error) -> Value {
    if error.kind() == std::io::ErrorKind::QuotaExceeded {
        return browser_failure_value(
            "artifact_quota_exceeded",
            "The browser artifact store has no remaining capacity.",
            &["Delete no-longer-needed artifact files or wait for their expiry, then retry."],
        );
    }
    browser_failure_value(
        "artifact_unavailable",
        format!("Could not reserve a private browser artifact: {error}"),
        &["Check the Alera runtime directory permissions and retry."],
    )
}

fn is_routed_browser_request(request_type: &str) -> bool {
    matches!(
        request_type,
        "browser.navigate"
            | "browser.back"
            | "browser.forward"
            | "browser.reload"
            | "browser.stop"
            | "browser.snapshot"
            | "browser.ref.click"
            | "browser.ref.fill"
            | "browser.ref.type"
            | "browser.ref.select"
            | "browser.ref.focus"
            | "browser.ref.hover"
            | "browser.ref.scroll"
            | "browser.wait"
            | "browser.eval"
            | "browser.screenshot"
            | "browser.pdf"
            | "browser.cookies.list"
            | "browser.cookies.delete"
            | "browser.cookies.clear"
    )
}

fn strip_cookie_values(value: &mut Value) {
    match value {
        Value::Object(object) => {
            object.remove("value");
            object.remove("cookieValue");
            for child in object.values_mut() {
                strip_cookie_values(child);
            }
        }
        Value::Array(items) => {
            for item in items {
                strip_cookie_values(item);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cookie_outcomes_never_expose_values() {
        let mut value = json!({
            "ok": true,
            "cookies": [{
                "name": "session",
                "value": "secret",
                "domain": "example.com",
                "nested": {"cookieValue": "also-secret"},
            }]
        });
        strip_cookie_values(&mut value);
        assert_eq!(value["cookies"][0]["name"], "session");
        assert_eq!(value["cookies"][0].get("value"), None);
        assert_eq!(value["cookies"][0]["nested"].get("cookieValue"), None);
    }

    #[test]
    fn browser_page_ids_accept_the_tab_alias() {
        assert_eq!(
            browser_page_id(&json!({"tabId": "page-1"})).unwrap(),
            "page-1"
        );
    }

    #[test]
    fn artifact_quota_reservation_failures_have_a_stable_code() {
        let error = std::io::Error::new(std::io::ErrorKind::QuotaExceeded, "full");

        let failure = artifact_reservation_failure(&error);

        assert_eq!(failure["error"]["code"], "artifact_quota_exceeded");
        assert_eq!(failure["error"]["retryable"], true);
    }
}
