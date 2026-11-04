//! Owner-scoped `chatOrchestration.*` verbs (scheduled tasks and chat pull
//! requests) for a chat that lives on a satellite: the hub forwards them to
//! the host that owns the chat, which stores and runs them.

use serde_json::{json, Value};

use super::agent_chat_runtime::CallerCtx;
use super::chat_orchestration::{ChatOrchestrationService, OrchestrationCaller};
use super::chat_orchestration_remote::{decode, text};
use crate::terminal_host::host_error::{HostError, HostResult};

/// The internal chat operation that runs an owner-scoped
/// `chatOrchestration.*` verb on the satellite that owns the chat.
pub(crate) const OWNER_ORCHESTRATION: &str = "orchestration";

/// Refuses an owner-scoped verb before it reaches a satellite that does not
/// advertise it, so an older satellite answers clearly instead of
/// "Unknown internal chat operation".
pub(crate) fn require_owner_orchestration_capability(
    payload: &Value,
    capabilities: &[String],
) -> HostResult<()> {
    if payload["operation"] != OWNER_ORCHESTRATION {
        return Ok(());
    }
    let verb = payload["verb"].as_str().unwrap_or_default();
    match super::chat_orchestration::owner_scoped_capability(verb) {
        Some((capability, _)) if capabilities.iter().any(|offered| offered == capability) => Ok(()),
        _ => Err(super::chat_orchestration::unsupported_on_host(verb)),
    }
}

/// Satellite side of [OWNER_ORCHESTRATION]: only the hub link sends it, and
/// only for owner-scoped verbs. The hub already checked what its ledger
/// knows, so the verb runs here as the person the hub names.
pub(crate) async fn handle_owner_orchestration(
    service: Option<ChatOrchestrationService>,
    payload: &Value,
) -> HostResult<Value> {
    let verb = text(payload, "verb")?;
    if !super::chat_orchestration::is_owner_scoped_verb(&verb) {
        return Err(HostError::conflict(
            "chat_scope_denied",
            "The remote chat verb is not allowed.",
            json!({}),
        ));
    }
    let service = service.ok_or_else(|| super::chat_orchestration::unsupported_on_host(&verb))?;
    let caller: CallerCtx = decode(payload, "caller")?;
    let request = payload.get("payload").cloned().unwrap_or_else(|| json!({}));
    service
        .handle(&verb, &request, &OrchestrationCaller::human(caller))
        .await
}
