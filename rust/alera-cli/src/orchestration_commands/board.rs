//! Read-only views of the run board: `board`, `run-snapshot`, and
//! `task-inspect`, over the host's paginated board reads.

use serde_json::{json, Map, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    OrchestrationBoardArgs, OrchestrationRunSnapshotArgs, OrchestrationTaskInspectArgs,
};
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_BOARD_CAPABILITY;

use super::{request_with_capability, usage_error};

pub(super) async fn board(
    runtime: &RuntimeDirArgs,
    args: OrchestrationBoardArgs,
    json: bool,
) -> i32 {
    let cursor = match parse_cursor(args.cursor.as_deref()) {
        Ok(cursor) => cursor,
        Err(message) => return usage_error(&message),
    };
    let mut payload = Map::new();
    insert(&mut payload, "project_id", args.project_id);
    insert(&mut payload, "workspace_id", args.workspace);
    insert(&mut payload, "search", args.search);
    insert(&mut payload, "bucket", args.bucket);
    insert(&mut payload, "cursor", cursor);
    insert(&mut payload, "limit", args.limit);
    read(runtime, "orchestration.boardSnapshot", payload, json).await
}

pub(super) async fn run_snapshot(
    runtime: &RuntimeDirArgs,
    args: OrchestrationRunSnapshotArgs,
    json: bool,
) -> i32 {
    let mut payload = Map::new();
    payload.insert("run_id".into(), json!(args.run));
    insert(&mut payload, "after_task_id", args.after_task);
    insert(&mut payload, "revision", args.revision);
    insert(&mut payload, "limit", args.limit);
    read(runtime, "orchestration.runSnapshot", payload, json).await
}

pub(super) async fn task_inspect(
    runtime: &RuntimeDirArgs,
    args: OrchestrationTaskInspectArgs,
    json: bool,
) -> i32 {
    let cursor = match parse_cursor(args.cursor.as_deref()) {
        Ok(cursor) => cursor,
        Err(message) => return usage_error(&message),
    };
    let mut payload = Map::new();
    payload.insert("run_id".into(), json!(args.run));
    payload.insert("task_id".into(), json!(args.task));
    insert(&mut payload, "cursor", cursor);
    insert(&mut payload, "limit", args.limit);
    read(runtime, "orchestration.taskInspection", payload, json).await
}

async fn read(
    runtime: &RuntimeDirArgs,
    verb: &str,
    payload: Map<String, Value>,
    json: bool,
) -> i32 {
    request_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_BOARD_CAPABILITY,
        verb,
        Value::Object(payload),
        json,
        None,
    )
    .await
}

fn insert<T: Into<Value>>(payload: &mut Map<String, Value>, key: &str, value: Option<T>) {
    if let Some(value) = value {
        payload.insert(key.to_string(), value.into());
    }
}

/// A page cursor is the JSON object a previous page returned.
fn parse_cursor(raw: Option<&str>) -> Result<Option<Value>, String> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    match serde_json::from_str::<Value>(raw) {
        Ok(cursor @ Value::Object(_)) => Ok(Some(cursor)),
        _ => Err("--cursor must be the JSON object a previous page returned.".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::parse_cursor;

    #[test]
    fn cursors_must_be_json_objects() {
        assert_eq!(parse_cursor(None), Ok(None));
        let cursor = parse_cursor(Some(r#"{"id":"run_1","created_at":"t","revision":3}"#)).unwrap();
        assert_eq!(cursor.unwrap()["revision"], 3);
        assert!(parse_cursor(Some("run_1")).is_err());
        assert!(parse_cursor(Some("[1]")).is_err());
    }
}
