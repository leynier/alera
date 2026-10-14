use clap::Parser;
use serde_json::{json, Value};

use super::{deadline_ms, prepare, ChatHumanArgs};
use crate::chat_orchestration_commands_args::ChatAction;
use crate::chat_orchestration_request::extra_capabilities;
use crate::chat_task_command_contract::{EFFORT_CAPABILITY, PERSON_PARENT_CAPABILITY};
use crate::chat_task_payload_validation::validate;
use crate::cli::{Cli, Command};
use crate::orchestration_commands::WAIT_CLIENT_GRACE_MS;

fn args(operation: &str, payload: &Value) -> ChatHumanArgs {
    let text = payload.to_string();
    let Command::Chat(command) =
        Cli::try_parse_from(["alera", "chat", "human", operation, "--payload", &text])
            .unwrap()
            .command
    else {
        panic!("chat");
    };
    let ChatAction::Human(args) = command.action else {
        panic!("human");
    };
    args
}

#[test]
fn human_parent_binding_does_not_fabricate_sender_or_credentials() {
    let mut input = args(
        "delegate",
        &json!({"task":"inspect","parentChatId":"parent","target":{"workspace":{"workspaceId":"w"}}}),
    );
    input.input.request_id = Some("retry-1".into());
    let payload = prepare(input).unwrap();
    assert_eq!(payload["parentChatId"], "parent");
    assert_eq!(payload["requestId"], "retry-1");
    assert!(payload.get("actor").is_none());
    assert!(payload.get("scope").is_none());
    assert!(payload.get("senderChatId").is_none());
    assert_eq!(
        extra_capabilities("delegate", &payload),
        [PERSON_PARENT_CAPABILITY]
    );
    assert!(crate::agent_chat_commands::require_human_scope(true).is_err());
    assert!(validate(
        "delegate",
        &json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"actor":"desktop"})
    )
    .is_err());
}

#[test]
fn effort_is_only_a_verified_nested_delegation_option() {
    let payload = json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"agent":{"providerInstanceId":"p","options":{"reasoningEffort":"high"}}});
    assert!(validate("delegate", &payload).is_ok());
    assert_eq!(
        extra_capabilities("delegate", &payload),
        [EFFORT_CAPABILITY]
    );
    for payload in [
        json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"reasoningEffort":"high"}),
        json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"agent":{"reasoningEffort":"high"}}),
        json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"agent":{"options":{"runtimeMode":"full-access"}}}),
        json!({"task":"inspect","target":{"chat":{"chatId":"c"}},"agent":{"options":{"reasoningEffort":3}}}),
    ] {
        assert!(validate("delegate", &payload).is_err());
    }
    assert_eq!(
        extra_capabilities("configure", &json!({"chatId":"c","reasoningEffort":null})),
        [EFFORT_CAPABILITY]
    );
    assert!(extra_capabilities("configure", &json!({"chatId":"c","model":null})).is_empty());
}

#[test]
fn human_reads_have_bounded_defaults_and_cannot_acknowledge() {
    let read = prepare(args("read", &json!({"chatId":"c"}))).unwrap();
    assert_eq!(read["limit"], 100);
    assert!(read.get("requestId").is_none());
    let tasks = prepare(args("task-list", &json!({"cursor":0,"parentChatId":"p"}))).unwrap();
    assert_eq!(tasks["limit"], 100);
    assert_eq!(tasks["parentChatId"], "p");
    assert!(extra_capabilities("tasks.list", &tasks).is_empty());
    assert!(validate("task", &json!({"taskId":"t","acknowledge":true})).is_err());
    assert!(validate("read", &json!({"chatId":"c","limit":201})).is_err());
    assert!(validate("task-list", &json!({"cursor":-1})).is_err());
    assert!(validate("requests", &json!({})).is_err());
}

#[test]
fn wait_and_delegate_wait_keep_the_cli_deadline_within_the_bound() {
    let wait = prepare(args("wait", &json!({"taskIds":["t"]}))).unwrap();
    assert_eq!(wait["waitSeconds"], 50);
    assert_eq!(
        deadline_ms("wait", &wait),
        Some(50_000 + WAIT_CLIENT_GRACE_MS)
    );
    let delegate = prepare(args("delegate", &json!({"task":"inspect","mode":"wait","waitSeconds":2,"target":{"workspace":{"workspaceId":"w"}}}))).unwrap();
    assert_eq!(
        deadline_ms("delegate", &delegate),
        Some(2000 + WAIT_CLIENT_GRACE_MS)
    );
    assert!(validate("wait", &json!({"taskIds":[]})).is_err());
    assert!(validate("wait", &json!({"taskIds":["t"],"waitSeconds":51})).is_err());
}

#[test]
fn mutable_requests_keep_stable_ids_and_configuration_resets() {
    let configure = json!({"chatId":"c","model":null,"reasoningEffort":null,"requestId":"retry-1"});
    let first = prepare(args("configure", &configure)).unwrap();
    assert_eq!(first, prepare(args("configure", &configure)).unwrap());
    assert!(first["model"].is_null());
    assert!(first["reasoningEffort"].is_null());
    let acknowledge = prepare(args(
        "acknowledge",
        &json!({"taskId":"t","requestId":"ack-1"}),
    ))
    .unwrap();
    assert_eq!(acknowledge["acknowledge"], true);
    assert_eq!(acknowledge["requestId"], "ack-1");
    assert!(prepare(args("task", &json!({"taskId":"t","requestId":"read-1"}))).is_err());
}

#[test]
fn targets_and_invalid_input_do_not_echo_supplied_values() {
    assert!(validate(
        "delegate",
        &json!({"task":"inspect","target":{"chat":{"chatId":"c"},"workspace":{"workspaceId":"w"}}})
    )
    .is_err());
    assert!(validate("delegate", &json!({"task":"inspect","target":{"newWorkspace":{"projectId":"p","hostId":"local","mode":"worktree"}}})).is_err());
    assert!(validate("delegate", &json!({"task":"inspect","target":{"newWorkspace":{"projectId":"p","hostId":"local","mode":"worktree","branch":"review"}}})).is_ok());
    let error = validate(
        "send",
        &json!({"chatId":"c","message":"hello","credentials":"sensitive-test-value"}),
    )
    .unwrap_err()
    .to_string();
    assert!(!error.contains("sensitive-test-value"));
    assert!(validate("send", &json!({"chatId":"c","message":"x".repeat(65_537)})).is_err());
}
