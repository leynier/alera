use std::collections::HashSet;
use std::path::PathBuf;

use serde_json::{json, Value};

use super::{
    catalog, catalog_json, find_tool, run_tool, validate_chat_credential_file, CallOrigin,
    ToolAccess, ToolExecution,
};

fn invocation_args(tool: &str, arguments: Value) -> (Vec<String>, Option<String>) {
    let tool = find_tool(tool).expect("tool exists");
    let invocation = tool.invocation(&arguments).expect("valid arguments");
    let mut args = vec![invocation.group.to_owned()];
    args.extend(invocation.args);
    (args, invocation.stdin)
}

#[test]
fn tool_names_are_unique_short_and_snake_case() {
    let mut seen = HashSet::new();
    for tool in catalog() {
        assert!(seen.insert(tool.name), "duplicate tool {}", tool.name);
        assert!(tool.name.len() <= 64);
        assert!(tool
            .name
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte == b'_'));
        let schema = tool.schema();
        assert_eq!(schema["type"], "object");
        assert_eq!(schema["additionalProperties"], false);
        assert!(
            schema["properties"].get("runtime").is_none(),
            "runtime is reserved for the edge"
        );
        assert!(
            tool.timeout_seconds < 60,
            "hosted clients give up after a minute"
        );
        assert!(!tool.description.contains('\u{2014}'));
    }
}

#[test]
fn reads_and_executes_are_classified() {
    let read = find_tool("read_terminal").unwrap();
    let write = find_tool("write_terminal").unwrap();
    assert_eq!(read.access, ToolAccess::Read);
    assert_eq!(write.access, ToolAccess::Execute);
    assert!(
        catalog()
            .iter()
            .filter(|tool| tool.access == ToolAccess::Execute)
            .count()
            >= 8
    );
}

#[test]
fn builds_cli_arguments_with_equals_form_values() {
    let (args, stdin) = invocation_args("list_workspaces", json!({ "projectId": "--all" }));
    assert_eq!(args, ["workspace", "list", "--project-id=--all"]);
    assert!(stdin.is_none());
    let (all, _) = invocation_args("list_workspaces", json!({ "hostId": "local" }));
    assert_eq!(all, ["workspace", "list", "--host-id=local", "--all"]);
}

#[test]
fn long_text_travels_on_stdin() {
    let (args, stdin) = invocation_args(
        "write_terminal",
        json!({ "handle": "t-1", "text": "echo hi", "submit": true, "enter": true }),
    );
    assert_eq!(
        args,
        ["terminal", "write", "--handle=t-1", "--stdin", "--submit"]
    );
    assert_eq!(stdin.as_deref(), Some("echo hi"));
}

#[test]
fn profiles_are_addressed_by_id_or_name() {
    let (by_id, _) = invocation_args(
        "launch_agent",
        json!({ "workspaceId": "w", "profile": "prof_1", "prompt": "go" }),
    );
    assert!(by_id.contains(&"--profile-id=prof_1".to_owned()));
    let (by_name, _) = invocation_args(
        "launch_agent",
        json!({ "workspaceId": "w", "profile": "Codex Sol", "prompt": "go" }),
    );
    assert!(by_name.contains(&"--profile-name=Codex Sol".to_owned()));
}

#[test]
fn pull_request_details_answer_within_the_deadline_and_resume_by_retry_key() {
    let tool = find_tool("generate_pull_request_details").unwrap();
    assert!(tool.timeout_seconds <= super::MAX_WAIT_SECONDS + 8);
    let arguments = json!({ "workspaceId": "ws", "baseBranch": "main" });
    let (args, _) = invocation_args("generate_pull_request_details", arguments.clone());
    assert!(args.contains(&"--wait-seconds=45".to_owned()));
    assert!(!args.iter().any(|arg| arg.starts_with("--operation-id")));
    let mut resumed = arguments;
    resumed["clientRequestId"] = json!("cli-0001-retry");
    let (args, _) = invocation_args("generate_pull_request_details", resumed);
    assert!(args.contains(&"--operation-id=cli-0001-retry".to_owned()));
}

#[test]
fn waits_are_clamped_below_the_client_deadline() {
    let tool = find_tool("wait_for_task").unwrap();
    assert!(tool
        .invocation(&json!({ "taskId": "t", "timeoutSeconds": 500 }))
        .is_err());
    let (args, _) = invocation_args(
        "wait_for_task",
        json!({ "taskId": "t", "timeoutSeconds": 50 }),
    );
    assert!(args.contains(&"--timeout-ms=50000".to_owned()));
    assert!(args.contains(&"--for=completed,failed,stalled,cancelled".to_owned()));
}

#[test]
fn rejects_unknown_missing_and_mistyped_arguments() {
    let tool = find_tool("show_task").unwrap();
    assert!(tool.invocation(&json!({})).is_err());
    assert!(tool.invocation(&json!({ "taskId": 4 })).is_err());
    assert!(tool
        .invocation(&json!({ "taskId": "t", "extra": true }))
        .is_err());
    assert!(tool.invocation(&json!({ "taskId": "  " })).is_err());
    assert!(tool.invocation(&json!(["t"])).is_err());
    let delegate = find_tool("delegate_task").unwrap();
    assert!(delegate
        .invocation(&json!({ "profile": "p", "spec": "s", "coordinator": "t" }))
        .is_err());
    assert!(delegate
        .invocation(&json!({ "profile": "p", "spec": "s", "workspaceId": "w" }))
        .is_err());
}

#[test]
fn delegate_into_a_new_workspace_uses_the_source_workspace() {
    let (args, stdin) = invocation_args(
        "delegate_task",
        json!({ "profile": "p", "spec": "do it", "workspaceId": "w-1", "newWorkspace": true, "coordinator": "t-9" }),
    );
    assert!(args.contains(&"--from-workspace=w-1".to_owned()));
    assert!(args.contains(&"--new-workspace".to_owned()));
    assert!(args.contains(&"--from=t-9".to_owned()));
    assert!(!args.iter().any(|arg| arg == "--no-parent"));
    assert_eq!(stdin.as_deref(), Some("do it"));
}

#[tokio::test]
async fn reports_invalid_arguments_without_spawning() {
    let execution = ToolExecution {
        executable: PathBuf::from("/nonexistent/alera"),
        runtime_dir: PathBuf::from("/nonexistent"),
        chat_credential_file: None,
    };
    let tool = find_tool("show_task").unwrap();
    let result = run_tool(&execution, &tool, &json!({}), &CallOrigin::default(), None).await;
    assert!(result.is_error);
    assert!(result.text.contains("taskId"));
    let mcp = result.to_mcp();
    assert_eq!(
        mcp["structuredContent"]["error"]["code"],
        "invalid_argument"
    );
}

/// The edge serves a copy of the catalog. Set `ALERA_UPDATE_MCP_CATALOG=1` to
/// rewrite it after changing a tool.
#[test]
fn mcp_tool_catalog_matches_edge_copy() {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../edge/src/mcp/tool_catalog.json");
    // Keys are sorted explicitly: workspace builds can enable serde_json's
    // `preserve_order`, which would otherwise change the written key order.
    let expected = sorted_keys(catalog_json());
    if std::env::var_os("ALERA_UPDATE_MCP_CATALOG").is_some() {
        let mut text = serde_json::to_string_pretty(&expected).unwrap();
        text.push('\n');
        std::fs::write(&path, text).unwrap();
        return;
    }
    let actual: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_default())
        .unwrap_or_default();
    assert_eq!(
        actual, expected,
        "edge/src/mcp/tool_catalog.json is stale; run with ALERA_UPDATE_MCP_CATALOG=1"
    );
}

#[test]
fn terminal_reads_drop_the_base64_copy() {
    let tool = find_tool("read_terminal").unwrap();
    let text = super::executor::without_fields(
        r#"{"text":"hi","dataBase64":"aGk=","cursor":2}"#,
        tool.omit_fields,
    );
    let value: Value = serde_json::from_str(&text).unwrap();
    assert!(value.get("dataBase64").is_none());
    assert_eq!(value["text"], "hi");
    assert_eq!(
        super::executor::without_fields("not json", tool.omit_fields),
        "not json"
    );
}

#[test]
fn messages_name_their_sender() {
    let (args, stdin) = invocation_args(
        "send_message",
        json!({ "from": "t-1", "to": "@all", "subject": "hi", "body": "status" }),
    );
    assert!(args.contains(&"--from=t-1".to_owned()));
    assert_eq!(stdin.as_deref(), Some("status"));
    assert!(find_tool("send_message")
        .unwrap()
        .invocation(&json!({ "to": "@all", "subject": "hi" }))
        .is_err());
}

#[test]
fn chat_bound_catalog_contains_only_chat_and_workspace_discovery_tools() {
    let tools = super::catalog::chat_tools();
    assert!(tools.iter().any(|tool| tool.name == "chat_delegate"));
    assert!(tools.iter().any(|tool| tool.name == "list_projects"));
    assert!(tools.iter().any(|tool| tool.name == "list_workspaces"));
    assert!(!tools.iter().any(|tool| tool.name == "send_message"));
    assert!(tools
        .iter()
        .filter(|tool| tool.name.starts_with("chat_") && tool.access != ToolAccess::Read)
        .all(|tool| tool.client_request_flag == Some("--request-id")));
}

#[test]
fn chat_catalog_uses_the_chat_wire_verbs_and_bounded_wait() {
    let names = super::catalog::chat_tools()
        .into_iter()
        .filter(|tool| tool.name.starts_with("chat_"))
        .map(|tool| tool.name)
        .collect::<HashSet<_>>();
    let expected = [
        "chat_capabilities",
        "chat_list",
        "chat_read",
        "chat_transfers",
        "chat_delegate",
        "chat_send",
        "chat_task_status",
        "chat_task_wait",
        "chat_task_list",
        "chat_task_cancel",
        "chat_interrupt",
        "chat_background_wait",
        "chat_requests",
        "chat_respond",
        "chat_configure",
    ]
    .into_iter()
    .collect::<HashSet<_>>();
    assert_eq!(names, expected);

    let wait = super::catalog::chat_tools()
        .into_iter()
        .find(|tool| tool.name == "chat_task_wait")
        .unwrap();
    let invocation = wait
        .invocation(&json!({
            "taskIds": ["task-1"],
            "timeoutSeconds": 50,
            "until": "all",
        }))
        .unwrap();
    assert!(invocation.args.contains(&"--task-id=task-1".to_owned()));
    assert!(invocation.args.contains(&"--timeout-seconds=50".to_owned()));
    assert!(invocation.args.contains(&"--until=all".to_owned()));

    let requests = super::catalog::chat_tools()
        .into_iter()
        .find(|tool| tool.name == "chat_requests")
        .unwrap();
    let invocation = requests.invocation(&json!({ "taskId": "task-1" })).unwrap();
    assert!(invocation.args.contains(&"--task-id=task-1".to_owned()));
}

#[test]
fn background_waits_name_the_tasks_and_refuse_out_of_range_lists() {
    let tool = super::catalog::chat_tools()
        .into_iter()
        .find(|tool| tool.name == "chat_background_wait")
        .unwrap();
    assert_eq!(tool.access, ToolAccess::Execute);
    let invocation = tool
        .invocation(&json!({"taskIds": ["bash-1", "bash-2"], "clientRequestId": "wait-0001"}))
        .unwrap();
    assert_eq!(invocation.group, "chat");
    assert_eq!(invocation.args[0], "background-wait");
    assert!(invocation
        .args
        .contains(&"--task-id=bash-1,bash-2".to_owned()));
    assert!(invocation
        .args
        .contains(&"--request-id=wait-0001".to_owned()));
    assert!(!invocation.args.contains(&"--stop-waiting".to_owned()));
    let unmark = tool
        .invocation(&json!({"taskIds": ["bash-1"], "waiting": false}))
        .unwrap();
    assert!(unmark.args.contains(&"--stop-waiting".to_owned()));
    let too_many: Vec<String> = (0..21).map(|index| format!("bash-{index}")).collect();
    for task_ids in [json!([]), json!(too_many), json!([" "])] {
        assert!(tool.invocation(&json!({"taskIds": task_ids})).is_err());
    }
    // An unsupported provider is an invalid request, not a failure.
    assert_eq!(
        super::executor::error_code(
            "Invalid request: this chat's provider cannot mark background work as awaited."
        ),
        ("invalid_argument", false)
    );
}

#[test]
fn chat_delegate_mcp_request_uses_client_request_id_and_task_stdin() {
    let tool = super::catalog::chat_tools()
        .into_iter()
        .find(|tool| tool.name == "chat_delegate")
        .unwrap();
    let arguments = json!({
        "task": "inspect the child",
        "target": {"chat": {"chatId": "chat-1"}},
        "clientRequestId": "retry-01",
    });
    let invocation = tool.invocation(&arguments).unwrap();
    assert!(invocation
        .args
        .contains(&"--request-id=retry-01".to_owned()));
    assert!(invocation.args.contains(&"--task-stdin".to_owned()));
    assert_eq!(invocation.stdin.as_deref(), Some("inspect the child"));
}

#[test]
fn injected_task_acknowledgement_maps_optional_request_id_without_changing_legacy_calls() {
    let tool = super::catalog::chat_tools()
        .into_iter()
        .find(|tool| tool.name == "chat_task_status")
        .unwrap();
    let keyed = tool
        .invocation(&json!({"taskId":"t","acknowledge":true,"clientRequestId":"ack-retry-1"}))
        .unwrap();
    assert!(keyed.args.contains(&"--request-id=ack-retry-1".into()));
    let legacy = tool
        .invocation(&json!({"taskId":"t","acknowledge":true}))
        .unwrap();
    assert!(!legacy
        .args
        .iter()
        .any(|arg| arg.starts_with("--request-id=")));
    assert!(tool
        .invocation(&json!({"taskId":"t","clientRequestId":"read-only-1"}))
        .is_err());
}

#[test]
fn native_history_failures_require_observation_instead_of_automatic_retry() {
    for arguments in [
        json!({"operation":"rewind","payload":{"mode":"native"}}),
        json!({"operation":"rewind-files","payload":{}}),
        json!({"operation":"native-history-reconcile","payload":{}}),
    ] {
        let result = super::executor::guard_native_history_failure(
            "agent_chat_control",
            &arguments,
            super::ToolResult::error("request did not finish within 30 seconds"),
        );
        assert_eq!(result.structured.unwrap()["error"]["retryable"], false);
        assert!(result.text.contains("Read native-history-operation"));
    }
    let transcript = super::executor::guard_native_history_failure(
        "agent_chat_control",
        &json!({"operation":"rewind","payload":{"mode":"transcript"}}),
        super::ToolResult::error("request did not finish within 30 seconds"),
    );
    assert_eq!(transcript.structured.unwrap()["error"]["retryable"], true);
}

#[test]
fn chat_credential_file_validation_rejects_missing_and_empty_files() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("chat.token");
    assert!(validate_chat_credential_file(&path).is_err());
    std::fs::write(&path, "  secret\n").unwrap();
    assert!(validate_chat_credential_file(&path).is_ok());
    std::fs::write(&path, "\n").unwrap();
    assert!(validate_chat_credential_file(&path).is_err());
}

#[cfg(unix)]
#[tokio::test]
async fn chat_credential_path_is_forwarded_to_tool_children() {
    use std::os::unix::fs::PermissionsExt;

    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("print-chat-credential");
    std::fs::write(
        &executable,
        "#!/bin/sh\nprintf '%s' \"$ALERA_CHAT_CREDENTIAL_FILE\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
    let credential = directory.path().join("chat.token");
    std::fs::write(&credential, "secret").unwrap();
    let execution = ToolExecution {
        executable,
        runtime_dir: directory.path().to_path_buf(),
        chat_credential_file: Some(credential.clone()),
    };
    let tool = find_tool("runtime_status").unwrap();
    let result = run_tool(&execution, &tool, &json!({}), &CallOrigin::default(), None).await;
    assert!(!result.is_error, "{}", result.text);
    assert_eq!(result.text, credential.display().to_string());
}

#[test]
fn inbox_wait_timeouts_are_answers_not_failures() {
    assert!(super::executor::is_wait_timeout(
        r#"{"outcome":"timeout","cursor":3}"#
    ));
    assert!(!super::executor::is_wait_timeout(r#"{"outcome":"reply"}"#));
    assert!(!super::executor::is_wait_timeout("error: no such question"));
}

#[test]
fn mcp_task_cancellation_is_an_audited_administrative_action() {
    let (args, _) = invocation_args("cancel_task", json!({ "taskId": "t-1", "reason": "stale" }));
    assert!(args.contains(&"--force".to_owned()));
    assert!(args.contains(&"--reason=[mcp] stale".to_owned()));
}

fn sorted_keys(value: Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut entries = map.into_iter().collect::<Vec<_>>();
            entries.sort_by(|left, right| left.0.cmp(&right.0));
            Value::Object(
                entries
                    .into_iter()
                    .map(|(key, value)| (key, sorted_keys(value)))
                    .collect(),
            )
        }
        Value::Array(items) => Value::Array(items.into_iter().map(sorted_keys).collect()),
        other => other,
    }
}
