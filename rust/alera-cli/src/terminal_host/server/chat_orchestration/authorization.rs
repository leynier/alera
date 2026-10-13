use serde_json::Value;

use super::runtime::ChatOrchestrationRuntime;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::commands::CallerCtx;

use alera_core::runtime::RuntimeStore;

use super::models::OrchestrationRequest;

const MODE_APPROVAL: u8 = 0;
const MODE_EDITS: u8 = 1;
const MODE_AUTO: u8 = 2;
const MODE_FULL: u8 = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BoundChat {
    pub chat_id: String,
    pub generation: i64,
    pub runtime_mode: String,
    pub credential_hash: String,
    pub origin_host_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct OrchestrationCaller {
    pub ctx: CallerCtx,
    pub bound: Option<BoundChat>,
}

impl OrchestrationCaller {
    pub(crate) fn human(ctx: CallerCtx) -> Self {
        Self { ctx, bound: None }
    }

    pub(crate) fn agent(ctx: CallerCtx, bound: BoundChat) -> Self {
        Self {
            ctx,
            bound: Some(bound),
        }
    }
}

pub(crate) async fn require_bound_turn(
    caller: &OrchestrationCaller,
    _store: &RuntimeStore,
    runtime: &dyn ChatOrchestrationRuntime,
) -> HostResult<OrchestrationCaller> {
    let Some(bound) = &caller.bound else {
        return Ok(caller.clone());
    };
    let snapshot = runtime
        .validate_binding(bound)
        .await
        .map_err(|_| invalid_binding())?;
    let session = snapshot.get("session").ok_or_else(|| {
        HostError::conflict(
            "caller_turn_inactive",
            "The caller chat has no session.",
            serde_json::json!({}),
        )
    })?;
    let generation = session
        .get("generation")
        .and_then(Value::as_i64)
        .unwrap_or_default();
    let active_turn = session.get("activeTurnId").and_then(Value::as_str);
    if generation != bound.generation
        || snapshot
            .get("archived")
            .and_then(Value::as_bool)
            .unwrap_or(true)
    {
        return Err(invalid_binding());
    }
    if active_turn.is_none() {
        return Err(HostError::conflict(
            "caller_turn_inactive",
            "The caller chat does not have a live turn.",
            serde_json::json!({}),
        ));
    }
    let mut current = caller.clone();
    current.bound.as_mut().expect("bound caller").runtime_mode = session
        .get("runtimeMode")
        .and_then(Value::as_str)
        .unwrap_or("approval-required")
        .to_owned();
    Ok(current)
}

fn invalid_binding() -> HostError {
    HostError::conflict(
        "chat_credential_invalid",
        "The chat credential is invalid or expired.",
        serde_json::json!({}),
    )
}

pub(super) async fn authorize_target_chat(
    caller: &OrchestrationCaller,
    runtime: &dyn ChatOrchestrationRuntime,
    chat_id: &str,
) -> HostResult<Value> {
    let snapshot = runtime.snapshot(chat_id).await?;
    if snapshot
        .get("archived")
        .and_then(Value::as_bool)
        .unwrap_or(true)
    {
        return Err(HostError::conflict(
            "chat_archived",
            "The target chat is archived.",
            serde_json::json!({}),
        ));
    }
    enforce_mode_ceiling(caller, snapshot["session"]["runtimeMode"].as_str())?;
    Ok(snapshot)
}

pub(crate) fn mode_rank(value: &str) -> Option<u8> {
    match value {
        "approval-required" => Some(MODE_APPROVAL),
        "auto-accept-edits" => Some(MODE_EDITS),
        "auto" => Some(MODE_AUTO),
        "full-access" => Some(MODE_FULL),
        _ => None,
    }
}

pub(crate) fn modes_at_or_below(mode: &str) -> Vec<&'static str> {
    let ceiling = mode_rank(mode).unwrap_or(MODE_APPROVAL);
    [
        (MODE_APPROVAL, "approval-required"),
        (MODE_EDITS, "auto-accept-edits"),
        (MODE_AUTO, "auto"),
        (MODE_FULL, "full-access"),
    ]
    .into_iter()
    .filter_map(|(rank, value)| (rank <= ceiling).then_some(value))
    .collect()
}

pub(crate) fn enforce_mode_ceiling(
    caller: &OrchestrationCaller,
    requested_mode: Option<&str>,
) -> HostResult<String> {
    let requested = requested_mode.unwrap_or_else(|| {
        caller
            .bound
            .as_ref()
            .map(|bound| bound.runtime_mode.as_str())
            .unwrap_or("approval-required")
    });
    let Some(requested_rank) = mode_rank(requested) else {
        return Err(HostError::format(format!(
            "unknown runtime mode {requested}"
        )));
    };
    if let Some(bound) = &caller.bound {
        let ceiling = mode_rank(&bound.runtime_mode).unwrap_or(MODE_APPROVAL);
        if requested_rank > ceiling {
            return Err(HostError::conflict(
                "mode_ceiling",
                "The target runtime mode exceeds the caller chat's mode ceiling.",
                serde_json::json!({"requestedRuntimeMode": requested, "callerRuntimeMode": bound.runtime_mode}),
            ));
        }
    }
    Ok(requested.to_owned())
}

pub(crate) async fn require_lineage_for_chat(
    caller: &OrchestrationCaller,
    store: &RuntimeStore,
    chat_id: &str,
) -> HostResult<()> {
    let Some(bound) = &caller.bound else {
        return Ok(());
    };
    if bound.chat_id == chat_id
        || store
            .is_chat_orchestration_descendant_chat(&bound.chat_id, chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
    {
        return Ok(());
    }
    Err(HostError::conflict(
        "not_in_lineage",
        "The bound chat may only mutate its own descendant chats.",
        serde_json::json!({}),
    ))
}

pub(crate) async fn require_lineage_for_task(
    caller: &OrchestrationCaller,
    store: &RuntimeStore,
    task_id: &str,
) -> HostResult<()> {
    let Some(bound) = &caller.bound else {
        return Ok(());
    };
    if store
        .is_chat_orchestration_task_in_lineage(&bound.chat_id, task_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
    {
        return Ok(());
    }
    Err(HostError::conflict(
        "not_in_lineage",
        "The bound chat may only mutate its own descendant tasks.",
        serde_json::json!({}),
    ))
}

pub(crate) async fn authorize_request(
    caller: &OrchestrationCaller,
    store: &RuntimeStore,
    runtime: &dyn ChatOrchestrationRuntime,
    request: &OrchestrationRequest,
) -> HostResult<OrchestrationCaller> {
    let caller = require_bound_turn(caller, store, runtime).await?;
    match request {
        OrchestrationRequest::Interrupt { chat_id, .. }
        | OrchestrationRequest::Respond { chat_id, .. }
        | OrchestrationRequest::Configure { chat_id, .. } => {
            require_lineage_for_chat(&caller, store, chat_id).await?;
            if let OrchestrationRequest::Configure { runtime_mode, .. } = request {
                let snapshot = runtime.snapshot(chat_id).await?;
                enforce_mode_ceiling(&caller, snapshot["session"]["runtimeMode"].as_str())?;
                enforce_mode_ceiling(
                    &caller,
                    runtime_mode
                        .as_deref()
                        .or_else(|| snapshot["session"]["runtimeMode"].as_str()),
                )?;
            } else {
                authorize_target_chat(&caller, runtime, chat_id).await?;
            }
        }
        OrchestrationRequest::Cancel { task_id, .. } => {
            require_lineage_for_task(&caller, store, task_id).await?;
            if caller.bound.is_some() {
                let mut tasks = store
                    .chat_orchestration_task_descendants(task_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                if let Some(task) = store
                    .chat_orchestration_task(task_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                {
                    tasks.push(task);
                }
                for task in tasks.into_iter().filter(|task| !task.status.is_terminal()) {
                    if let Some(chat_id) = task.child_chat_id {
                        let snapshot = runtime.snapshot(&chat_id).await?;
                        enforce_mode_ceiling(&caller, snapshot["session"]["runtimeMode"].as_str())?;
                    } else {
                        enforce_mode_ceiling(
                            &caller,
                            task.launch_options
                                .as_ref()
                                .and_then(|options| options["runtimeMode"].as_str()),
                        )?;
                    }
                }
            }
        }
        OrchestrationRequest::Delegate(input) => {
            enforce_mode_ceiling(&caller, input.runtime_mode.as_deref())?;
            if let super::models::ParsedTarget::Chat { chat_id } = &input.target {
                authorize_target_chat(&caller, runtime, chat_id).await?;
            }
        }
        OrchestrationRequest::Send(input) => {
            authorize_target_chat(&caller, runtime, &input.chat_id).await?;
        }
        _ => {}
    }
    Ok(caller)
}
