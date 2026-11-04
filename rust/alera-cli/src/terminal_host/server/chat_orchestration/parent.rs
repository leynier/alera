use serde_json::json;

use super::authorization::{authorize_target_chat, OrchestrationCaller};
use super::runtime::ChatOrchestrationRuntime;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn task_parent_chat_id(
    caller: &OrchestrationCaller,
    requested: Option<&str>,
) -> HostResult<Option<String>> {
    if let Some(bound) = &caller.bound {
        if requested.is_some_and(|parent| parent != bound.chat_id) {
            return Err(HostError::conflict(
                "not_in_lineage",
                "The parent chat must be the authenticated caller chat.",
                json!({}),
            ));
        }
        return Ok(Some(bound.chat_id.clone()));
    }
    if requested.is_some()
        && !matches!(caller.ctx.scope.as_str(), "desktop" | "cli")
        && !caller.ctx.scope.starts_with("mobile:")
    {
        return Err(HostError::conflict(
            "chat_scope_denied",
            "Only an authenticated person may select a parent chat.",
            json!({}),
        ));
    }
    Ok(requested.map(ToOwned::to_owned))
}

pub(super) async fn authorize_parent_chat(
    caller: &OrchestrationCaller,
    runtime: &dyn ChatOrchestrationRuntime,
    requested: Option<&str>,
) -> HostResult<()> {
    if let Some(parent) = task_parent_chat_id(caller, requested)? {
        authorize_target_chat(caller, runtime, &parent).await?;
    }
    Ok(())
}
