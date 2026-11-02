//! Runtime requests the host opens itself, with no native provider request
//! behind them: `secret_input` from `chatOrchestration.requestSecret`. Only
//! the host resolves them, and their answer never passes through this actor,
//! its history or its snapshots.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;

use super::commands::{conflict, CallerCtx};
use super::ids::{new_id, now};
use super::session::ChatSession;
use super::wire::ChatRequest;

/// `ChatRequest.answer_by` of a request only the host resolves.
pub(crate) const ANSWER_BY_HOST: &str = "host";

/// The request kind `chatOrchestration.requestSecret` opens.
pub(crate) const SECRET_INPUT_KIND: &str = "secret_input";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct RuntimeRequestInput {
    pub kind: String,
    pub title: String,
    pub detail: Option<String>,
    /// The masked question the card shows.
    pub question: Value,
}

impl ChatSession {
    /// Opens a host-owned request on the running turn, so it expires with it.
    pub(super) fn open_runtime_request(&mut self, input: RuntimeRequestInput) -> HostResult<Value> {
        let Some(turn_id) = self.header.session.active_turn_id.clone() else {
            return Err(conflict(
                "noActiveTurn",
                "A request can only be opened while the agent is working.",
            ));
        };
        let request = ChatRequest {
            request_id: new_id("request"),
            kind: input.kind,
            turn_id: Some(turn_id),
            item_id: None,
            created_at: now(),
            title: Some(input.title),
            detail: input.detail,
            command: None,
            cwd: None,
            path: None,
            questions: vec![input.question],
            decisions: Vec::new(),
            elicitation: None,
            expires_at: None,
            supports_feedback: false,
            full_access_override: None,
            answer_by: Some(ANSWER_BY_HOST.into()),
            masked: true,
        };
        self.record_request_history(&request, "pending", None, None);
        let request_id = request.request_id.clone();
        self.header.pending_requests.push(request);
        self.set_status("waiting");
        self.pending.session();
        Ok(json!({"runtimeRequestId": request_id}))
    }

    /// Settles a host-owned request as `resolved`, `declined` or `cancelled`.
    /// The history keeps only the outcome, never an answer.
    pub(super) fn resolve_runtime_request(
        &mut self,
        runtime_request_id: &str,
        outcome: &str,
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        let Some(index) = self.header.pending_requests.iter().position(|request| {
            request.request_id == runtime_request_id
                && request.answer_by.as_deref() == Some(ANSWER_BY_HOST)
        }) else {
            return Err(conflict(
                "request_resolved",
                "This request was already answered or has expired.",
            ));
        };
        let row = self.header.pending_requests.remove(index);
        self.record_request_history(
            &row,
            outcome,
            Some(&json!({"type": "secret", "outcome": outcome})),
            Some(&ctx.actor),
        );
        self.refresh_waiting_status();
        self.pending.session();
        Ok(json!({"resolved": true}))
    }

    /// Whether a host-owned request is still pending.
    pub(super) fn runtime_request_state(&self, runtime_request_id: &str) -> Value {
        let pending = self.header.pending_requests.iter().any(|request| {
            request.request_id == runtime_request_id
                && request.answer_by.as_deref() == Some(ANSWER_BY_HOST)
        });
        json!({"pending": pending})
    }
}
