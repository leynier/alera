use clap::Parser;
use serde_json::json;

use super::{
    parse_target, read_json_source, request_id, validate_response, CHAT_ORCHESTRATION_CAPABILITY,
};
use crate::chat_orchestration_commands_args::ChatAction;
use crate::cli::{Cli, Command};

#[test]
fn chat_group_parses_the_full_action_surface() {
    let cases: &[&[&str]] = &[
        &["alera", "chat", "capabilities"],
        &["alera", "chat", "list"],
        &["alera", "chat", "read", "--chat-id", "chat-1"],
        &[
            "alera",
            "chat",
            "delegate",
            "--task",
            "inspect",
            "--target",
            "{\"chat\":{\"chatId\":\"chat-2\"}}",
        ],
        &[
            "alera",
            "chat",
            "send",
            "--chat-id",
            "chat-2",
            "--message",
            "hello",
        ],
        &["alera", "chat", "task", "--task-id", "task-1"],
        &["alera", "chat", "task-list"],
        &[
            "alera",
            "chat",
            "wait",
            "--task-id",
            "task-1",
            "--task-id",
            "task-2",
        ],
        &["alera", "chat", "cancel", "--task-id", "task-1"],
        &["alera", "chat", "interrupt", "--chat-id", "chat-2"],
        &["alera", "chat", "requests", "--chat-id", "chat-2"],
        &[
            "alera",
            "chat",
            "respond",
            "--chat-id",
            "chat-2",
            "--runtime-request-id",
            "request-1",
            "--response",
            "{\"type\":\"approval\",\"decision\":\"accept\"}",
        ],
        &[
            "alera",
            "chat",
            "configure",
            "--chat-id",
            "chat-2",
            "--model",
            "model-1",
        ],
    ];
    for args in cases {
        let command = Cli::try_parse_from(*args).unwrap().command;
        assert!(matches!(command, Command::Chat(_)));
    }
}

#[test]
fn target_requires_one_valid_strategy() {
    assert!(parse_target(r#"{"chat":{"chatId":"chat-1"}}"#).is_ok());
    assert!(parse_target(r#"{"workspace":{"workspaceId":"workspace-1"}}"#).is_ok());
    assert!(parse_target(
        r#"{"newWorkspace":{"projectId":"project-1","hostId":"host-1","mode":"worktree"}}"#
    )
    .is_ok());
    assert!(
        parse_target(r#"{"chat":{"chatId":"chat-1"},"workspace":{"workspaceId":"w"}}"#).is_err()
    );
    assert!(parse_target(r#"{"chat":{"chatId":""}}"#).is_err());
    assert!(
        parse_target(r#"{"newWorkspace":{"projectId":"p","hostId":"h","mode":"other"}}"#).is_err()
    );
}

#[test]
fn response_validation_keeps_native_and_runtime_shapes_explicit() {
    assert!(validate_response(&json!({"type":"approval","decision":"accept"})).is_ok());
    assert!(validate_response(&json!({"type":"userInput","answers":{}})).is_ok());
    assert!(validate_response(&json!({"type":"elicitation","action":"cancel"})).is_ok());
    assert!(validate_response(&json!({"type":"native","result":{"ok":true}})).is_ok());
    assert!(validate_response(&json!({"type":"approval","decision":"allow"})).is_err());
    assert!(validate_response(&json!({"type":"userInput","answers":[]})).is_err());
    assert!(validate_response(&json!({"type":"unknown"})).is_err());
}

#[test]
fn request_ids_are_stable_when_given_and_generated_when_omitted() {
    assert_eq!(request_id(Some("retry-1".into())).unwrap(), "retry-1");
    assert!(request_id(Some(" ".into())).is_err());
    assert!(request_id(None).unwrap().starts_with("cli-"));
}

#[test]
fn json_response_source_preserves_the_decoded_value() {
    let value = read_json_source(
        Some(r#"{"type":"approval","decision":"decline"}"#.into()),
        None,
        false,
        "response",
    )
    .unwrap();
    assert_eq!(value["type"], "approval");
    assert!(read_json_source(Some("[]".into()), None, false, "response").is_ok());
    assert_eq!(CHAT_ORCHESTRATION_CAPABILITY, "chatOrchestrationV1");
}

#[test]
fn chat_action_names_are_not_terminal_orchestration_actions() {
    let command = Cli::try_parse_from(["alera", "chat", "task-list"])
        .unwrap()
        .command;
    let Command::Chat(command) = command else {
        panic!("expected chat command");
    };
    assert!(matches!(command.action, ChatAction::TaskList(_)));
}

#[test]
fn configure_omits_unselected_model_and_preserves_explicit_resets() {
    for (flags, model_reset, effort_reset) in [
        (vec!["--runtime-mode", "auto"], false, false),
        (vec!["--reset-model"], true, false),
        (vec!["--reset-reasoning-effort"], false, true),
    ] {
        let mut argv = vec!["alera", "chat", "configure", "--chat-id", "c"];
        argv.extend(flags);
        let Command::Chat(command) = Cli::try_parse_from(argv).unwrap().command else {
            panic!("chat");
        };
        let ChatAction::Configure(args) = command.action else {
            panic!("configure");
        };
        let payload = super::configure_payload(args).unwrap();
        assert_eq!(payload.get("model").is_some(), model_reset);
        assert_eq!(payload.get("reasoningEffort").is_some(), effort_reset);
        if model_reset {
            assert!(payload["model"].is_null());
        }
        if effort_reset {
            assert!(payload["reasoningEffort"].is_null());
        }
    }
    assert!(Cli::try_parse_from([
        "alera",
        "chat",
        "configure",
        "--chat-id",
        "c",
        "--model",
        "m",
        "--reset-model"
    ])
    .is_err());
}

#[test]
fn default_delegation_omits_agent_and_explicit_human_parent_is_preserved() {
    for parent in [None, Some("parent-chat")] {
        let mut argv = vec![
            "alera",
            "chat",
            "delegate",
            "--task",
            "inspect",
            "--target",
            r#"{"workspace":{"workspaceId":"w"}}"#,
        ];
        if let Some(parent) = parent {
            argv.extend(["--parent-chat-id", parent]);
        }
        let Command::Chat(command) = Cli::try_parse_from(argv).unwrap().command else {
            panic!("chat");
        };
        let ChatAction::Delegate(args) = command.action else {
            panic!("delegate");
        };
        let payload = super::delegate_payload(*args).unwrap();
        assert!(payload.get("agent").is_none());
        assert_eq!(
            payload
                .get("parentChatId")
                .and_then(serde_json::Value::as_str),
            parent
        );
        assert!(payload.get("actor").is_none());
    }
}

#[test]
fn acknowledgement_preserves_explicit_retry_ids_and_legacy_omission() {
    for request_id in [None, Some("ack-retry-1")] {
        let mut argv = vec!["alera", "chat", "task", "--task-id", "t", "--acknowledge"];
        if let Some(id) = request_id {
            argv.extend(["--request-id", id]);
        }
        let Command::Chat(command) = Cli::try_parse_from(argv).unwrap().command else {
            panic!("chat");
        };
        let ChatAction::Task(args) = command.action else {
            panic!("task");
        };
        let payload = super::task_payload(args).unwrap();
        assert_eq!(payload["acknowledge"], true);
        assert_eq!(
            payload.get("requestId").and_then(serde_json::Value::as_str),
            request_id
        );
    }
    assert!(Cli::try_parse_from([
        "alera",
        "chat",
        "task",
        "--task-id",
        "t",
        "--request-id",
        "read-1"
    ])
    .is_err());
}
