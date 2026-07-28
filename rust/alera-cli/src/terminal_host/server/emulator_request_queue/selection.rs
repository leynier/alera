use serde_json::Value;

use super::{QueuedEmulatorRequest, QueuedOperation};

pub(super) fn emulator_operation(request: &QueuedEmulatorRequest) -> Option<(&str, &Value)> {
    match &request.operation {
        QueuedOperation::Emulator {
            request_type,
            payload,
        } => Some((request_type, payload)),
        QueuedOperation::RuntimeMutation(_)
        | QueuedOperation::ParkAll
        | QueuedOperation::ReleaseClients { .. }
        | QueuedOperation::CancelPointer { .. } => None,
    }
}

pub(super) fn can_bypass_active_pointer(request: &QueuedEmulatorRequest) -> bool {
    matches!(
        &request.operation,
        QueuedOperation::RuntimeMutation(_)
            | QueuedOperation::ParkAll
            | QueuedOperation::ReleaseClients { .. }
            | QueuedOperation::CancelPointer { .. }
    )
}

pub(super) fn is_runtime_mutation(request: &QueuedEmulatorRequest) -> bool {
    matches!(&request.operation, QueuedOperation::RuntimeMutation(_))
}

pub(super) fn requires_live_client(request: &QueuedEmulatorRequest) -> bool {
    matches!(
        &request.operation,
        QueuedOperation::Emulator { .. } | QueuedOperation::RuntimeMutation(_)
    )
}

pub(super) fn is_pointer_move(request: &QueuedEmulatorRequest) -> bool {
    emulator_operation(request)
        .and_then(|(request_type, payload)| pointer_kind(request_type, payload))
        == Some("move")
}

pub(super) fn is_pointer_end(request: &QueuedEmulatorRequest) -> bool {
    emulator_operation(request)
        .and_then(|(request_type, payload)| pointer_kind(request_type, payload))
        == Some("end")
}

pub(super) fn pointer_kind<'a>(request_type: &str, payload: &'a Value) -> Option<&'a str> {
    (request_type == "emulator.pointer")
        .then(|| payload.get("type").and_then(Value::as_str))
        .flatten()
}

pub(super) fn is_interactive(request: &QueuedEmulatorRequest) -> bool {
    if is_pointer_end(request) {
        return false;
    }
    let Some((request_type, payload)) = emulator_operation(request) else {
        return false;
    };
    payload.get("interactive").and_then(Value::as_bool) == Some(true)
        && matches!(
            request_type,
            "emulator.pointer" | "emulator.type" | "emulator.key"
        )
}

pub(super) fn same_tab(first: &QueuedEmulatorRequest, second: &QueuedEmulatorRequest) -> bool {
    let (Some((_, first)), Some((_, second))) =
        (emulator_operation(first), emulator_operation(second))
    else {
        return false;
    };
    let first = first.get("tabId").and_then(Value::as_str);
    let second = second.get("tabId").and_then(Value::as_str);
    first.is_some() && first == second
}
