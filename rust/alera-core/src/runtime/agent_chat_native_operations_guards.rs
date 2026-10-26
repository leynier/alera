use anyhow::Result;
use serde_json::Value;
use sqlx::SqliteConnection;

use super::store::active_operation_in;
use super::validation::invalid;
use super::view::agent_chat_native_operation_public_summary;
use crate::runtime::{AgentChatDelta, AgentChatSessionStatus, AgentChatSnapshot};

/// Publishing safe state/capability summaries is allowed while destructive
/// mutation is frozen. User input and provider changes remain prohibited.
pub(in crate::runtime) async fn require_native_operation_safe_commit_in(
    connection: &mut SqliteConnection,
    chat_id: &str,
    stored: &AgentChatSnapshot,
    snapshot: &AgentChatSnapshot,
    delta: &AgentChatDelta,
) -> Result<()> {
    let Some(operation) = active_operation_in(connection, chat_id).await? else {
        return Ok(());
    };
    if delta.items.as_ref().is_some_and(|items| !items.is_empty())
        || delta.turns.as_ref().is_some_and(|turns| !turns.is_empty())
        || delta
            .removed_item_ids
            .as_ref()
            .is_some_and(|ids| !ids.is_empty())
        || !delta.text_appends.is_empty()
        || snapshot.provider != stored.provider
        || snapshot.provider_instance_id != stored.provider_instance_id
        || snapshot.title != stored.title
        || snapshot.usage != stored.usage
        || snapshot.recovery != stored.recovery
        || snapshot.pending_requests != stored.pending_requests
    {
        return Err(invalid(
            "native operation pending; transcript and selection changes are frozen",
        ));
    }
    let mut old = stored.session.clone();
    let mut new = snapshot.session.clone();
    if !matches!(
        new.status,
        AgentChatSessionStatus::Ready
            | AgentChatSessionStatus::Stopped
            | AgentChatSessionStatus::Error
    ) {
        return Err(invalid(
            "native operation pending; a new provider session cannot start",
        ));
    }
    old.capabilities = Value::Null;
    new.capabilities = Value::Null;
    old.status = AgentChatSessionStatus::Stopped;
    new.status = AgentChatSessionStatus::Stopped;
    old.extra.remove("errorMessage");
    new.extra.remove("errorMessage");
    if old != new {
        return Err(invalid(
            "native operation pending; session configuration is frozen",
        ));
    }
    let keys: std::collections::BTreeSet<_> =
        stored.extra.keys().chain(snapshot.extra.keys()).collect();
    for key in keys {
        if stored.extra.get(key) != snapshot.extra.get(key)
            && (key != "pendingNativeOperation"
                || snapshot.extra.get(key)
                    != Some(&agent_chat_native_operation_public_summary(&operation)))
        {
            return Err(invalid(
                "native operation pending; only its safe summary can change",
            ));
        }
    }
    Ok(())
}
