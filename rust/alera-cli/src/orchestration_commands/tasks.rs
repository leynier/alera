//! `task`, `dispatch`, and `transfer-coordinator`.

use serde_json::{json, Map, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{DispatchAction, OrchestrationTransferCoordinatorArgs, TaskAction};
use crate::terminal_host::protocol::{
    RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY, RUNTIME_HOST_RUNS_CAPABILITY,
};

use super::runs::parse_cursor;
use super::worker::csv;
use super::{
    insert_opt, request, request_with_capability, terminal_handle_env, usage_error,
    WAIT_CLIENT_GRACE_MS,
};

pub(super) async fn task(runtime: &RuntimeDirArgs, action: TaskAction, json_output: bool) -> i32 {
    match action {
        TaskAction::Show(args) => match args.run {
            None => {
                request(
                    runtime,
                    "orchestration.taskShow",
                    json!({ "id": args.id }),
                    json_output,
                    None,
                )
                .await
            }
            Some(run) => {
                let cursor = match parse_cursor(args.cursor.as_deref()) {
                    Ok(cursor) => cursor,
                    Err(message) => return usage_error(&message),
                };
                let mut payload = Map::new();
                payload.insert("runId".into(), json!(run));
                payload.insert("taskId".into(), json!(args.id));
                insert_opt(&mut payload, "cursor", cursor);
                insert_opt(&mut payload, "limit", args.limit);
                request_with_capability(
                    runtime,
                    RUNTIME_HOST_RUNS_CAPABILITY,
                    "runs.task",
                    Value::Object(payload),
                    json_output,
                    None,
                )
                .await
            }
        },
        TaskAction::Wait(args) => {
            request_with_capability(
                runtime,
                RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
                "orchestration.taskWait",
                json!({
                    "task": args.id,
                    "targets": csv(&args.targets),
                    "timeoutMs": args.timeout_ms,
                }),
                json_output,
                Some(args.timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
            )
            .await
        }
        TaskAction::Cancel(args) => {
            request(
                runtime,
                "orchestration.taskCancel",
                json!({
                    "id": args.id,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
        TaskAction::Recover(args) => {
            request(
                runtime,
                "orchestration.taskRecover",
                json!({
                    "id": args.id,
                    "status": args.status,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
    }
}

pub(super) async fn dispatch(
    runtime: &RuntimeDirArgs,
    action: DispatchAction,
    json_output: bool,
) -> i32 {
    let (verb, payload) = match action {
        DispatchAction::Show(args) => ("orchestration.dispatchShow", json!({ "task": args.task })),
        DispatchAction::Interrupt(args) => (
            "orchestration.dispatchInterrupt",
            json!({
                "id": args.id,
                "reason": args.reason,
                "actor": terminal_handle_env(),
                "force": args.force,
            }),
        ),
    };
    request(runtime, verb, payload, json_output, None).await
}

pub(super) async fn transfer_coordinator(
    runtime: &RuntimeDirArgs,
    args: OrchestrationTransferCoordinatorArgs,
    json_output: bool,
) -> i32 {
    request(
        runtime,
        "orchestration.transferCoordinator",
        json!({
            "task": args.task,
            "run": args.run,
            "to": args.to,
            "reason": args.reason,
            "force": args.force,
            "actor": terminal_handle_env(),
        }),
        json_output,
        None,
    )
    .await
}
