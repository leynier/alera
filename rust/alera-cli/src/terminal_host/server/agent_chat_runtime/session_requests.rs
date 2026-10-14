//! Runtime requests are persisted with app-owned ids. Native request ids are
//! kept in memory for the live provider and in the core native-id table.

use alera_provider_protocol::{
    ApprovalDecision, ElicitationAction, ProviderEvent, RequestId, RequestKind, RuntimeResponse,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx};
use super::ids::{native_key, new_id, now};
use super::request_view::{build_request_view, is_approval};
use super::session::ChatSession;
use super::wire::ChatRequest;

impl ChatSession {
    pub(super) async fn open_request(&mut self, event: &ProviderEvent) {
        let Some(request) = event.runtime_request.as_ref() else {
            return;
        };
        let native = serde_json::to_value(&request.request_id).unwrap_or(Value::Null);
        let kind = self.epoch_kind("request");
        let key = native_key(&kind, &native);
        if let Some(request_id) = self.native_ids.get(&key).cloned() {
            if self
                .header
                .pending_requests
                .iter()
                .any(|pending| pending.request_id == request_id)
            {
                return;
            }
        }
        let request_id = new_id("request");
        self.native_ids.insert(key, request_id.clone());
        self.map_native("request", native.clone(), &request_id)
            .await;
        let item_id = request.item_id.as_deref().and_then(|native_item| {
            self.native_ids
                .get(&native_key(
                    &self.epoch_kind("item"),
                    &Value::String(native_item.to_owned()),
                ))
                .cloned()
        });
        let view = build_request_view(
            &self.header.provider,
            request_id.clone(),
            request,
            &event.payload,
            self.app_turn_id(event),
            item_id,
            &now(),
        );
        self.record_request_history(&view, "pending", None, None);
        self.open_requests.push(super::session::OpenRequest {
            request_id,
            native: request.request_id.clone(),
        });
        self.header.pending_requests.push(view);
        self.set_status("waiting");
        self.pending.session();
    }

    /// The provider settled a request itself (timeout, auto-approval, or a
    /// native response). The app request remains in the event stream until
    /// this method removes it from the pending snapshot.
    pub(super) fn resolve_request_from_provider(&mut self, event: &ProviderEvent) {
        let Some(native_text) = event.request_id.as_deref() else {
            return;
        };
        let app_id = if let Some(request) = self
            .header
            .pending_requests
            .iter()
            .find(|request| request.request_id == native_text)
        {
            request.request_id.clone()
        } else if let Some(open) = self.open_requests.iter().find(|open| {
            open.native.to_string() == native_text
                || open.native.to_string().trim_matches('"') == native_text
        }) {
            open.request_id.clone()
        } else {
            return;
        };
        if let Some(row) = self
            .header
            .pending_requests
            .iter()
            .find(|request| request.request_id == app_id)
            .cloned()
        {
            self.record_request_history(&row, "providerResolved", None, None);
        }
        self.header
            .pending_requests
            .retain(|request| request.request_id != app_id);
        self.open_requests.retain(|open| open.request_id != app_id);
        self.refresh_waiting_status();
    }

    pub(super) async fn respond(
        &mut self,
        runtime_request_id: &str,
        response: Value,
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        let Some(index) = self
            .header
            .pending_requests
            .iter()
            .position(|request| request.request_id == runtime_request_id)
        else {
            return Err(conflict(
                "request_resolved",
                "This request was already answered or has expired.",
            ));
        };
        let row = self.header.pending_requests[index].clone();
        let Some(open) = self
            .open_requests
            .iter()
            .find(|open| open.request_id == runtime_request_id)
            .cloned()
        else {
            return Err(conflict(
                "request_resolved",
                "The provider is no longer waiting for this request.",
            ));
        };
        let native = native_response(&row, open.native, &response)?;
        let Some(provider) = self.provider.as_mut() else {
            return Err(conflict(
                "request_resolved",
                "The provider for this request is no longer running.",
            ));
        };
        provider
            .respond(native)
            .await
            .map_err(|error| match error {
                alera_provider_protocol::ProviderError::Unsupported(message) => {
                    unsupported(message)
                }
                other => HostError::state(other.to_string()),
            })?;
        self.events_armed = true;
        self.record_request_history(&row, "resolved", Some(&response), Some(&ctx.actor));
        self.header.pending_requests.remove(index);
        self.open_requests
            .retain(|request| request.request_id != runtime_request_id);
        self.refresh_waiting_status();
        Ok(json!({"resolved": true}))
    }

    pub(super) fn expire_requests_of_turn(&mut self, turn_id: Option<&str>) {
        let expired: Vec<_> = self
            .header
            .pending_requests
            .iter()
            .filter(|request| turn_id.is_none_or(|id| request.turn_id.as_deref() == Some(id)))
            .cloned()
            .collect();
        for request in expired {
            self.record_request_history(&request, "expired", None, None);
        }
        self.header
            .pending_requests
            .retain(|request| turn_id.is_some_and(|id| request.turn_id.as_deref() != Some(id)));
        self.open_requests.retain(|request| {
            self.header
                .pending_requests
                .iter()
                .any(|pending| pending.request_id == request.request_id)
        });
        self.refresh_waiting_status();
    }

    fn refresh_waiting_status(&mut self) {
        if self.header.pending_requests.is_empty() && self.header.session.status == "waiting" {
            self.set_status(if self.header.session.active_turn_id.is_some() {
                "running"
            } else {
                "ready"
            });
        }
    }
}

fn kind_of(request: &ChatRequest) -> RequestKind {
    serde_json::from_value(Value::String(request.kind.clone())).unwrap_or(RequestKind::Unknown)
}

fn native_response(
    row: &ChatRequest,
    request_id: RequestId,
    response: &Value,
) -> HostResult<RuntimeResponse> {
    let kind = kind_of(row);
    match response["type"].as_str().unwrap_or_default() {
        "approval" if is_approval(kind) => {
            let decision = response["decision"].as_str().unwrap_or_default();
            if !row.decisions.iter().any(|offered| offered == decision) {
                return Err(unsupported(format!(
                    "This request does not offer the decision {decision:?}."
                )));
            }
            let decision: ApprovalDecision = serde_json::from_value(Value::String(decision.into()))
                .map_err(|_| unsupported("Unknown approval decision."))?;
            Ok(RuntimeResponse::Approval {
                request_id,
                decision,
                updated_input: None,
            })
        }
        "userInput" if kind == RequestKind::ToolUserInput => {
            let answers = response["answers"]
                .as_object()
                .ok_or_else(|| HostError::format("answers must be an object"))?
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect();
            Ok(RuntimeResponse::UserInput {
                request_id,
                answers,
            })
        }
        "elicitation" if kind == RequestKind::McpElicitationApproval => {
            let action: ElicitationAction = serde_json::from_value(response["action"].clone())
                .map_err(|_| HostError::format("action must be accept, decline or cancel"))?;
            Ok(RuntimeResponse::Elicitation {
                request_id,
                action,
                content: response
                    .get("content")
                    .filter(|value| !value.is_null())
                    .cloned(),
            })
        }
        "native"
            if matches!(
                kind,
                RequestKind::DynamicToolCall
                    | RequestKind::AuthTokensRefresh
                    | RequestKind::Unknown
            ) =>
        {
            Ok(RuntimeResponse::Native {
                request_id,
                result: response.get("result").cloned().unwrap_or(Value::Null),
            })
        }
        response_type => Err(unsupported(format!(
            "A {response_type:?} response does not answer a {} request.",
            row.kind
        ))),
    }
}
