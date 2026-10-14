use clap::Parser;
use serde_json::{json, Value};

use super::tools;
use crate::chat_task_command_contract::{CONTROL_OPERATIONS, QUERY_OPERATIONS};
use crate::cli::Cli;
use crate::mcp_tools::{find_chat_tool, ToolAccess};

fn payload(operation: &str) -> Value {
    match operation {
        "read" | "interrupt" => json!({"chatId":"c"}),
        "task" | "acknowledge" | "cancel" => json!({"taskId":"t"}),
        "wait" => json!({"taskIds":["t"],"waitSeconds":50}),
        "requests" => json!({"chatId":"c"}),
        "delegate" => {
            json!({"task":"inspect","parentChatId":"p","agent":{"options":{"reasoningEffort":"high"}},"target":{"workspace":{"workspaceId":"w"}}})
        }
        "send" => json!({"chatId":"c","message":"hello","expectReply":true,"parentChatId":"p"}),
        "respond" => {
            json!({"chatId":"c","runtimeRequestId":"r","response":{"type":"approval","decision":"accept"}})
        }
        "configure" => json!({"chatId":"c","model":null,"reasoningEffort":null}),
        _ => json!({}),
    }
}

#[test]
fn each_public_operation_builds_a_human_cli_request_with_exact_body() {
    let groups = [
        QUERY_OPERATIONS,
        &["delegate"],
        &["send"],
        CONTROL_OPERATIONS,
    ];
    for (tool, operations) in tools().iter().zip(groups) {
        for operation in operations {
            let body = payload(operation);
            let invocation = tool
                .invocation(&json!({"operation":operation,"payload":body}))
                .unwrap();
            assert_eq!(invocation.group, "chat");
            assert_eq!(invocation.args[0], "human");
            assert_eq!(invocation.args[1], *operation);
            assert_eq!(
                serde_json::from_str::<Value>(invocation.stdin.as_deref().unwrap()).unwrap(),
                body
            );
            let mut argv = vec!["alera".to_owned(), "chat".to_owned()];
            argv.extend(invocation.args);
            assert!(Cli::try_parse_from(argv).is_ok());
        }
    }
}

#[test]
fn human_tools_preserve_public_read_execute_classes_and_private_catalog() {
    for (index, tool) in tools().iter().enumerate() {
        assert_eq!(
            tool.access,
            if index == 0 {
                ToolAccess::Read
            } else {
                ToolAccess::Execute
            }
        );
        assert!(find_chat_tool(tool.name).is_none());
        assert!(tool.timeout_seconds <= 58);
        if index > 0 {
            assert_eq!(tool.client_request_flag, Some("--request-id"));
        }
        let schema = tool.schema();
        assert!(schema["oneOf"].is_array());
        for alternative in schema["oneOf"].as_array().unwrap() {
            assert_eq!(
                alternative["properties"]["payload"]["additionalProperties"],
                false
            );
        }
    }
}

#[test]
fn retry_keys_and_long_text_are_separate_from_process_arguments() {
    let tool = tools().remove(1);
    let invocation = tool.invocation(&json!({"operation":"delegate","payload":payload("delegate"),"clientRequestId":"retry-task-1"})).unwrap();
    assert!(invocation
        .args
        .contains(&"--request-id=retry-task-1".into()));
    assert!(!invocation.args.iter().any(|arg| arg.contains("inspect")));
    assert!(tool.invocation(&json!({"operation":"delegate","payload":{"requestId":"wrong","task":"inspect","target":{"chat":{"chatId":"c"}}}})).is_err());
}

#[test]
fn query_cannot_mutate_and_nested_options_cannot_escalate_settings() {
    let tools = tools();
    assert!(tools[0]
        .invocation(&json!({"operation":"task","payload":{"taskId":"t","acknowledge":true}}))
        .is_err());
    assert!(tools[0]
        .invocation(&json!({"operation":"cancel","payload":{"taskId":"t"}}))
        .is_err());
    assert!(tools[1].invocation(&json!({"operation":"delegate","payload":{"task":"inspect","target":{"chat":{"chatId":"c"}},"agent":{"options":{"apiKey":"sensitive-test-value"}}}})).is_err());
    assert!(tools[3]
        .invocation(&json!({"operation":"secrets-set","payload":{}}))
        .is_err());
}

#[test]
fn public_acknowledgement_preserves_the_explicit_retry_key() {
    let tool = tools().remove(3);
    let invocation = tool.invocation(&json!({"operation":"acknowledge","payload":{"taskId":"t"},"clientRequestId":"ack-retry-1"})).unwrap();
    assert!(invocation.args.contains(&"--request-id=ack-retry-1".into()));
    assert_eq!(
        serde_json::from_str::<Value>(invocation.stdin.as_deref().unwrap()).unwrap(),
        json!({"taskId":"t"})
    );
}
