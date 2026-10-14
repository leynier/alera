use clap::Parser;
use serde_json::{json, Value};

use super::tools;
use crate::agent_chat_command_contract::{
    CONTROL_OPERATIONS, QUERY_OPERATIONS, SETTINGS_READ_OPERATIONS, SETTINGS_UPDATE_OPERATIONS,
};
use crate::cli::Cli;
use crate::mcp_tools::{find_chat_tool, ToolAccess};

#[test]
fn all_agent_chat_operations_build_parseable_named_cli_commands() {
    let groups = [
        QUERY_OPERATIONS,
        CONTROL_OPERATIONS,
        SETTINGS_READ_OPERATIONS,
        SETTINGS_UPDATE_OPERATIONS,
    ];
    for (tool, operations) in tools().iter().zip(groups) {
        for operation in operations {
            let body = match *operation {
                "rewind" | "rewind-files" => json!({"chatId":"c","turnId":"t"}),
                "file-checkpoints-configure" => json!({"chatId":"c","enabled":false}),
                "native-history-operation" => json!({"chatId":"c"}),
                "native-history-reconcile" => {
                    json!({"chatId":"c","operationId":"o","action":"finishAcknowledged"})
                }
                _ => json!({}),
            };
            let invocation = tool
                .invocation(&json!({"operation": operation, "payload": body}))
                .unwrap();
            assert_eq!(invocation.group, "agent-chat");
            assert_eq!(invocation.args[0], *operation);
            let mut argv = vec!["alera".to_owned(), invocation.group.to_owned()];
            argv.extend(invocation.args);
            assert!(Cli::try_parse_from(argv).is_ok());
            assert_eq!(
                serde_json::from_str::<Value>(invocation.stdin.as_deref().unwrap()).unwrap(),
                body
            );
        }
    }
}

#[test]
fn settings_stay_admin_only_and_absent_from_bound_chat_catalog() {
    for tool in tools() {
        assert!(find_chat_tool(tool.name).is_none());
        if tool.name.starts_with("agent_chat_settings_") {
            assert_eq!(tool.access, ToolAccess::Admin);
        }
    }
}

#[test]
fn secret_values_travel_on_stdin_with_a_separate_retry_flag() {
    let tool = tools()
        .into_iter()
        .find(|tool| tool.name == "agent_chat_settings_update")
        .unwrap();
    let arguments = json!({
        "operation": "secrets-set", "clientRequestId": "retry-01",
        "payload": {"expectedRevision": 2, "providerInstanceId": "p", "name": "TOKEN", "value": "sensitive-test-value"},
    });
    let invocation = tool.invocation(&arguments).unwrap();
    assert!(!invocation
        .args
        .iter()
        .any(|arg| arg.contains("sensitive-test-value")));
    assert!(invocation.args.contains(&"--request-id=retry-01".into()));
    assert_eq!(
        invocation
            .args
            .iter()
            .filter(|arg| arg.starts_with("--request-id="))
            .count(),
        1
    );
    let payload: Value = serde_json::from_str(invocation.stdin.as_deref().unwrap()).unwrap();
    assert_eq!(payload["value"], "sensitive-test-value");
    assert!(payload.get("requestId").is_none());
    assert!(payload.get("clientRequestId").is_none());
    for invalid_id in ["retry-1", "        "] {
        let mut invalid = arguments.clone();
        invalid["clientRequestId"] = json!(invalid_id);
        assert!(tool.invocation(&invalid).is_err());
    }
    assert!(tool
        .invocation(&json!({"operation":"secrets-set","payload":{"scope":"admin"}}))
        .is_err());
    assert!(tool
        .invocation(&json!({"operation":"secrets-set","payload":{"requestId":"duplicate"}}))
        .is_err());
}

#[test]
fn operation_access_enums_prevent_settings_through_control_or_query() {
    let query = tools().remove(0);
    assert!(query
        .invocation(&json!({"operation":"secrets-set", "payload":{}}))
        .is_err());
    let control = tools().remove(1);
    assert!(control
        .invocation(&json!({"operation":"preferences-update", "payload":{}}))
        .is_err());
}

#[test]
fn native_history_schema_and_invocations_preserve_exact_modes_actions_and_ids() {
    let control = tools().remove(1);
    let invocation = control.invocation(&json!({"operation":"rewind","payload":{"chatId":"c","turnId":"t","mode":"native"},"clientRequestId":"native-retry-1"})).unwrap();
    assert!(invocation
        .args
        .contains(&"--request-id=native-retry-1".into()));
    let body: Value = serde_json::from_str(invocation.stdin.as_deref().unwrap()).unwrap();
    assert_eq!(body["mode"], "native");
    assert!(control.invocation(&json!({"operation":"native-history-reconcile","payload":{"chatId":"c","operationId":"o","action":"retryNative"}})).is_err());
    assert!(control
        .invocation(
            &json!({"operation":"file-checkpoints-configure","payload":{"chatId":"c","enabled":1}})
        )
        .is_err());
    let alternatives = control.schema()["oneOf"].as_array().unwrap().clone();
    let rewind = alternatives
        .iter()
        .find(|value| value["properties"]["operation"]["enum"][0] == "rewind")
        .unwrap();
    assert_eq!(
        rewind["properties"]["payload"]["properties"]["mode"]["default"],
        "transcript"
    );
    assert_eq!(
        rewind["properties"]["payload"]["additionalProperties"],
        false
    );
    let query = tools().remove(0);
    assert!(query.invocation(&json!({"operation":"native-history-operation","payload":{"chatId":"c","operationId":"o"}})).is_ok());
    assert!(query
        .invocation(&json!({"operation":"native-history-reconcile","payload":{}}))
        .is_err());
}
