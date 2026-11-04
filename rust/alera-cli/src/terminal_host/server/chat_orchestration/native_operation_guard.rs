use alera_core::runtime::ChatOrchestrationStoreError;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::runtime::ChatOrchestrationRuntime;

pub(super) async fn require_unfrozen_admission(
    runtime: &dyn ChatOrchestrationRuntime,
    parent_chat_id: Option<&str>,
    destination_chat_id: Option<&str>,
) -> HostResult<()> {
    for chat_id in [parent_chat_id, destination_chat_id].into_iter().flatten() {
        require_unfrozen_chat(&runtime.snapshot(chat_id).await?)?;
    }
    Ok(())
}

pub(super) fn require_unfrozen_chat(snapshot: &Value) -> HostResult<()> {
    let Some(operation) = snapshot
        .get("pendingNativeOperation")
        .filter(|value| !value.is_null())
    else {
        return Ok(());
    };
    Err(native_operation_error(operation["state"] == "uncertain"))
}

fn native_operation_error(uncertain: bool) -> HostError {
    HostError::conflict(
        if uncertain {
            "nativeOperationUncertain"
        } else {
            "nativeOperationPending"
        },
        "Reconcile the pending native operation before creating linked tasks.",
        json!({}),
    )
}

pub(super) fn task_creation_error(error: anyhow::Error) -> HostError {
    if matches!(error.downcast_ref::<ChatOrchestrationStoreError>(),
        Some(ChatOrchestrationStoreError::Conflict(message)) if message == "native operation pending; reconcile it before creating linked tasks")
    {
        return native_operation_error(false);
    }
    HostError::state(error.to_string())
}
