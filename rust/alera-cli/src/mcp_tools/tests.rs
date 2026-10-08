use std::collections::HashSet;
use std::path::PathBuf;

use serde_json::{json, Value};

use super::{catalog, catalog_json, find_tool, run_tool, ToolAccess, ToolExecution};

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
        let schema = (tool.input_schema)();
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
    let (args, stdin) = invocation_args(
        "list_workspaces",
        json!({ "projectId": "--all", "all": true }),
    );
    assert_eq!(args, ["workspace", "list", "--project-id=--all", "--all"]);
    assert!(stdin.is_none());
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
    };
    let tool = find_tool("show_task").unwrap();
    let result = run_tool(&execution, &tool, &json!({}), None).await;
    assert!(result.is_error);
    assert!(result.text.contains("taskId"));
}

/// The edge serves a copy of the catalog. Set `ALERA_UPDATE_MCP_CATALOG=1` to
/// rewrite it after changing a tool.
#[test]
fn mcp_tool_catalog_matches_edge_copy() {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../edge/src/mcp/tool_catalog.json");
    let mut expected = serde_json::to_string_pretty(&catalog_json()).unwrap();
    expected.push('\n');
    if std::env::var_os("ALERA_UPDATE_MCP_CATALOG").is_some() {
        std::fs::write(&path, &expected).unwrap();
        return;
    }
    let actual = std::fs::read_to_string(&path).unwrap_or_default();
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
fn inbox_wait_timeouts_are_answers_not_failures() {
    assert!(super::executor::is_wait_timeout(
        r#"{"outcome":"timeout","cursor":3}"#
    ));
    assert!(!super::executor::is_wait_timeout(r#"{"outcome":"reply"}"#));
    assert!(!super::executor::is_wait_timeout("error: no such question"));
}
