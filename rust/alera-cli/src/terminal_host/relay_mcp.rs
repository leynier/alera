//! MCP tool calls that arrive over the runtime's relay link.
//!
//! The relay Durable Object sends `mcp.call` frames under the reserved client
//! id `~mcp`. Each call carries a grant the cloud signed for this runtime, this
//! account, and this tool; nothing runs until that grant verifies, so a relay
//! that forwards frames on its own cannot drive the runtime.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::{mpsc, oneshot, watch, Semaphore};
use tokio_tungstenite::tungstenite::Message;

use super::relay_runtime_auth::{CallGrantClaims, GrantVerifier};
use super::relay_wire;
use crate::mcp_settings::McpAccess;
use crate::mcp_tools::{find_tool, run_tool, CallOrigin, ToolAccess, ToolExecution, ToolResult};

pub(super) const MCP_CLIENT_ID: &str = "~mcp";
const MAX_CONCURRENT_CALLS: usize = 4;
/// Matches the relay's own frame cap, so a call the edge accepted is never
/// dropped here without an answer.
const MAX_CALL_FRAME_BYTES: usize = 1024 * 1024;
const MAX_RESULT_FRAME_BYTES: usize = 1024 * 1024 - 1024;

type ConsumedCalls = Arc<Mutex<HashMap<String, i64>>>;

/// Call ids used by this runtime process. The relay link is rebuilt whenever
/// settings change, so the record outlives each link: a grant replayed after a
/// restart, while still unexpired, must not run again.
static CONSUMED_CALLS: std::sync::LazyLock<ConsumedCalls> =
    std::sync::LazyLock::new(ConsumedCalls::default);

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum Incoming {
    #[serde(rename = "mcp.call")]
    Call {
        id: String,
        grant: String,
        tool: String,
        #[serde(default)]
        arguments: Value,
    },
    #[serde(rename = "mcp.cancel")]
    Cancel { id: String },
}

#[derive(Clone)]
pub(super) struct McpLink {
    access: McpAccess,
    execution: ToolExecution,
    verifier: GrantVerifier,
    permits: Arc<Semaphore>,
    calls: Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>,
    /// Call ids already used, until their grant expires.
    seen: ConsumedCalls,
}

pub(super) struct CallContext<'a> {
    pub(super) account_id: &'a str,
    pub(super) runtime_id: &'a str,
    pub(super) control: &'a mpsc::Sender<Message>,
    /// Ends with the socket the call arrived on. Its caller has already been
    /// told the runtime went offline, so queued and running calls stop then.
    pub(super) connection_closed: &'a watch::Receiver<()>,
}

impl McpLink {
    pub(super) fn new(
        access: McpAccess,
        execution: ToolExecution,
        verifier: GrantVerifier,
    ) -> Self {
        Self {
            access,
            execution,
            verifier,
            permits: Arc::new(Semaphore::new(MAX_CONCURRENT_CALLS)),
            calls: Arc::default(),
            seen: CONSUMED_CALLS.clone(),
        }
    }

    pub(super) fn handle_frame(&self, payload: &[u8], context: CallContext<'_>) {
        let message = if payload.len() > MAX_CALL_FRAME_BYTES {
            None
        } else {
            serde_json::from_slice::<Incoming>(payload).ok()
        };
        let Some(message) = message else {
            // Answer anything that names a call, so the caller fails now
            // instead of waiting out the tool timeout.
            if let Some(id) = readable_call_id(payload) {
                let control = context.control.clone();
                let outcome = Err((
                    "invalid_call",
                    "The runtime could not read this call.".to_owned(),
                ));
                if let Ok(frame) = result_frame(&id, outcome) {
                    tokio::spawn(async move {
                        let _ = control.send(Message::Binary(frame.into())).await;
                    });
                }
            }
            return;
        };
        match message {
            Incoming::Cancel { id } => {
                if let Some(cancel) = self
                    .calls
                    .lock()
                    .ok()
                    .and_then(|mut calls| calls.remove(&id))
                {
                    let _ = cancel.send(());
                }
            }
            Incoming::Call {
                id,
                grant,
                tool,
                arguments,
            } => {
                let (cancel, cancelled) = oneshot::channel();
                if let Ok(mut calls) = self.calls.lock() {
                    calls.insert(id.clone(), cancel);
                }
                let link = self.clone();
                let account_id = context.account_id.to_owned();
                let runtime_id = context.runtime_id.to_owned();
                let control = context.control.clone();
                let mut closed = context.connection_closed.clone();
                tokio::spawn(async move {
                    let call = link.run_call(
                        &id,
                        &grant,
                        &tool,
                        &arguments,
                        &account_id,
                        &runtime_id,
                        cancelled,
                    );
                    // Dropping the call future kills its child process.
                    let outcome = tokio::select! {
                        outcome = call => outcome,
                        _ = closed.changed() => Err((
                            "runtime_unavailable",
                            "The runtime's connection closed.".to_owned(),
                        )),
                    };
                    let finished = link
                        .calls
                        .lock()
                        .ok()
                        .and_then(|mut calls| calls.remove(&id))
                        .is_some();
                    if finished {
                        if let Ok(frame) = result_frame(&id, outcome) {
                            let _ = control.send(Message::Binary(frame.into())).await;
                        }
                    }
                });
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    async fn run_call(
        &self,
        id: &str,
        grant: &str,
        tool_name: &str,
        arguments: &Value,
        account_id: &str,
        runtime_id: &str,
        mut cancelled: oneshot::Receiver<()>,
    ) -> Result<ToolResult, (&'static str, String)> {
        let cancelled_error = || ("cancelled", "The call was cancelled.".to_owned());
        // A call can be cancelled while it waits for verification or a free
        // slot; it must never start its command after that.
        let permit = tokio::select! {
            biased;
            _ = &mut cancelled => return Err(cancelled_error()),
            prepared = self.prepare(id, grant, tool_name, account_id, runtime_id) => prepared?,
        };
        let (tool, _permit, origin) = permit;
        if cancelled.try_recv().is_ok() {
            return Err(cancelled_error());
        }
        tracing::info!(
            tool = tool_name,
            client = origin.client_name.as_deref().unwrap_or_default(),
            "running MCP tool"
        );
        Ok(run_tool(&self.execution, &tool, arguments, &origin, Some(cancelled)).await)
    }

    async fn prepare(
        &self,
        id: &str,
        grant: &str,
        tool_name: &str,
        account_id: &str,
        runtime_id: &str,
    ) -> Result<
        (
            crate::mcp_tools::ToolSpec,
            tokio::sync::SemaphorePermit<'_>,
            CallOrigin,
        ),
        (&'static str, String),
    > {
        let claims = self
            .verifier
            .verify_call(grant)
            .await
            .map_err(|error| ("call_grant_invalid", error.to_string()))?;
        self.authorize(&claims, id, tool_name, account_id, runtime_id)?;
        let tool = find_tool(tool_name).ok_or_else(|| {
            (
                "tool_unavailable",
                format!("This runtime does not provide {tool_name}. Update Alera on it."),
            )
        })?;
        let granted = ToolAccess::from_grant(&claims.access).unwrap_or(ToolAccess::Read);
        if tool.access > granted {
            return Err((
                "access_denied",
                format!("The call grant only allows {} tools.", granted.as_str()),
            ));
        }
        if !self.access.allows(tool.access) {
            let (code, message) = if tool.access == ToolAccess::Admin {
                (
                    "runtime_not_admin",
                    "MCP Control on this runtime does not allow administrative tools.",
                )
            } else {
                (
                    "runtime_read_only",
                    "MCP Control on this runtime only allows reading.",
                )
            };
            return Err((code, message.into()));
        }
        let permit = self.permits.acquire().await.map_err(|_| {
            (
                "runtime_unavailable",
                "The runtime is shutting down.".to_owned(),
            )
        })?;
        let origin = CallOrigin::remote(
            &claims.client_id,
            &claims.client_name,
            &claims.grant_id,
            &claims.jti,
        );
        Ok((tool, permit, origin))
    }

    fn authorize(
        &self,
        claims: &CallGrantClaims,
        id: &str,
        tool: &str,
        account_id: &str,
        runtime_id: &str,
    ) -> Result<(), (&'static str, String)> {
        let denied = |message: &str| Err(("call_grant_invalid", message.to_owned()));
        if claims.runtime_id != runtime_id || claims.account_id != account_id {
            return denied("The call grant is for another runtime.");
        }
        if claims.jti != id || claims.tool != tool {
            return denied("The call grant does not match this call.");
        }
        let now = chrono::Utc::now().timestamp();
        let Ok(mut seen) = self.seen.lock() else {
            return denied("The call could not be recorded.");
        };
        seen.retain(|_, expires| *expires > now);
        if seen.insert(claims.jti.clone(), claims.exp).is_some() {
            return denied("The call grant was already used.");
        }
        Ok(())
    }
}

fn readable_call_id(payload: &[u8]) -> Option<String> {
    #[derive(Deserialize)]
    struct CallId {
        #[serde(rename = "type")]
        kind: String,
        id: String,
    }
    serde_json::from_slice::<CallId>(payload)
        .ok()
        .filter(|call| call.kind == "mcp.call" && !call.id.is_empty() && call.id.len() <= 256)
        .map(|call| call.id)
}

fn result_frame(
    id: &str,
    outcome: Result<ToolResult, (&'static str, String)>,
) -> anyhow::Result<Vec<u8>> {
    let message = match outcome {
        Ok(result) => json!({ "type": "mcp.result", "id": id, "result": result.to_mcp() }),
        Err((code, message)) => json!({
            "type": "mcp.result",
            "id": id,
            "error": { "code": code, "message": message },
        }),
    };
    let mut payload = serde_json::to_vec(&message)?;
    if payload.len() > MAX_RESULT_FRAME_BYTES {
        payload = serde_json::to_vec(&json!({
            "type": "mcp.result",
            "id": id,
            "result": ToolResult::error("The tool output was too large to return.").to_mcp(),
        }))?;
    }
    relay_wire::wrap(MCP_CLIENT_ID, &payload)
}

#[cfg(test)]
#[path = "relay_mcp_tests.rs"]
mod tests;
