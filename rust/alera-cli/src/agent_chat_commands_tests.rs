use clap::Parser;
use serde_json::json;

use super::{extra_capabilities, prepare, require_human_scope};
use crate::agent_chat_command_contract::{
    spec, CONTROL_OPERATIONS, QUERY_OPERATIONS, SETTINGS_READ_OPERATIONS,
    SETTINGS_UPDATE_OPERATIONS,
};
use crate::agent_chat_commands_args::AgentChatRequestArgs;
use crate::cli::{Cli, Command};

fn parse(operation: &str, flags: &[&str]) -> AgentChatRequestArgs {
    let mut argv = vec!["alera", "agent-chat", operation];
    argv.extend_from_slice(flags);
    let Command::AgentChat(command) = Cli::try_parse_from(argv).unwrap().command else {
        panic!("expected agent-chat command");
    };
    command.action.into_parts().1
}

#[test]
fn every_mcp_operation_has_a_named_cli_command_and_wire_verb() {
    for operation in QUERY_OPERATIONS
        .iter()
        .chain(CONTROL_OPERATIONS)
        .chain(SETTINGS_READ_OPERATIONS)
        .chain(SETTINGS_UPDATE_OPERATIONS)
    {
        let args = parse(operation, &[]);
        assert!(args.payload.is_none());
        assert!(!spec(operation).suffix.is_empty());
    }
}

#[test]
fn explicit_default_is_distinct_from_an_omitted_model() {
    let reset = prepare(
        "configure",
        parse(
            "configure",
            &["--chat-id", "c", "--reset-model", "--request-id", "retry-1"],
        ),
    )
    .unwrap();
    assert_eq!(reset["model"], json!(null));
    let omitted = prepare(
        "configure",
        parse(
            "configure",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"runtimeMode":"auto","reasoningEffort":null}"#,
            ],
        ),
    )
    .unwrap();
    assert!(omitted.get("model").is_none());
    assert!(omitted.get("reasoningEffort").unwrap().is_null());
    assert!(prepare(
        "create",
        parse("create", &["--workspace-id", "w", "--model", ""])
    )
    .is_err());
}

#[test]
fn mutable_requests_keep_retry_ids_and_send_identity() {
    let flags = [
        "--chat-id",
        "c",
        "--payload",
        r#"{"text":"hello"}"#,
        "--request-id",
        "retry-1",
    ];
    let first = prepare("send", parse("send", &flags)).unwrap();
    let retry = prepare("send", parse("send", &flags)).unwrap();
    assert_eq!(first, retry);
    assert_eq!(first["requestId"], "retry-1");
    assert_eq!(first["clientMessageId"], "retry-1");
    assert!(
        prepare("close", parse("close", &["--chat-id", "c"])).unwrap()["requestId"]
            .as_str()
            .unwrap()
            .starts_with("cli-")
    );
}

#[test]
fn queue_steering_requires_both_queue_and_exact_turn_ids() {
    assert!(prepare(
        "queue-steer",
        parse(
            "queue-steer",
            &["--chat-id", "c", "--payload", r#"{"queueId":"q"}"#]
        )
    )
    .is_err());
    let payload = prepare(
        "queue-steer",
        parse(
            "queue-steer",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"queueId":"q","turnId":"t"}"#,
            ],
        ),
    )
    .unwrap();
    assert_eq!(payload["queueId"], "q");
    assert_eq!(payload["turnId"], "t");
    assert_eq!(spec("queue-steer").capability, "agentChatQueueSteerV1");
    assert_ne!(spec("fork").capability, spec("rewind").capability);
    assert_ne!(spec("delete").capability, spec("fork").capability);
}

#[test]
fn bounded_reads_preserve_host_scope_and_cursors() {
    let page = prepare(
        "history",
        parse(
            "history",
            &[
                "--chat-id",
                "c",
                "--host-id",
                "h",
                "--payload",
                r#"{"before":"seq:10"}"#,
            ],
        ),
    )
    .unwrap();
    assert_eq!(page["limit"], 100);
    assert_eq!(page["hostId"], "h");
    assert_eq!(page["before"], "seq:10");
    assert!(prepare(
        "history",
        parse(
            "history",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"before":"seq:10","limit":501}"#
            ]
        )
    )
    .is_err());
    let payload = prepare(
        "payload",
        parse(
            "payload",
            &["--chat-id", "c", "--payload", r#"{"itemId":"i","index":2}"#],
        ),
    )
    .unwrap();
    assert_eq!(payload["index"], 2);
}

#[test]
fn settings_require_revision_and_do_not_accept_caller_identity() {
    assert!(prepare(
        "preferences-update",
        parse("preferences-update", &["--payload", r#"{"operations":[]}"#])
    )
    .is_err());
    assert!(prepare(
        "preferences-get",
        parse("preferences-get", &["--payload", r#"{"actor":"admin"}"#])
    )
    .is_err());
    let payload = prepare(
        "preferences-update",
        parse(
            "preferences-update",
            &[
                "--host-id",
                "h",
                "--payload",
                r#"{"expectedRevision":0,"operations":[{"type":"setFavorites","favorites":[]}]}"#,
            ],
        ),
    )
    .unwrap();
    assert_eq!(payload["expectedRevision"], 0);
    assert!(require_human_scope(true).is_err());
    assert!(require_human_scope(false).is_ok());
}

#[test]
fn malformed_or_inline_secret_payloads_never_echo_values() {
    let error = prepare(
        "secrets-set",
        parse(
            "secrets-set",
            &["--payload", r#"{"value":"sensitive-test-value"}"#],
        ),
    )
    .unwrap_err()
    .to_string();
    assert!(!error.contains("sensitive-test-value"));
    let error = prepare(
        "preferences-update",
        parse(
            "preferences-update",
            &["--payload", r#"{"value":"sensitive-test-value""#],
        ),
    )
    .unwrap_err()
    .to_string();
    assert_eq!(error, "payload is invalid JSON");
    assert!(prepare(
        "snapshot",
        parse(
            "snapshot",
            &["--chat-id", "c", "--payload", r#"{"chatId":"other"}"#]
        )
    )
    .is_err());
}

#[test]
fn unselected_drafts_and_effort_reset_require_additive_capabilities() {
    assert_eq!(spec("create").capability, "agentChatDeferredStartV1");
    assert_eq!(
        extra_capabilities("create", &json!({"workspaceId":"w"})),
        ["agentChatUnselectedDraftV1"]
    );
    assert!(extra_capabilities("create", &json!({"providerInstanceId":"p"})).is_empty());
    assert_eq!(
        extra_capabilities("configure", &json!({"reasoningEffort":null})),
        ["agentChatEffortV1"]
    );
}

#[test]
fn rewind_defaults_to_transcript_and_native_mode_has_an_independent_capability() {
    use crate::agent_chat_command_contract::required_capability;
    let transcript = prepare(
        "rewind",
        parse(
            "rewind",
            &["--chat-id", "c", "--payload", r#"{"turnId":"t"}"#],
        ),
    )
    .unwrap();
    assert_eq!(
        required_capability("rewind", &transcript),
        "agentChatRewindV1"
    );
    let native = prepare(
        "rewind",
        parse(
            "rewind",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"turnId":"t","mode":"native"}"#,
                "--request-id",
                "native-1",
            ],
        ),
    )
    .unwrap();
    assert_eq!(
        required_capability("rewind", &native),
        "agentChatNativeRewindV1"
    );
    assert_eq!(native["requestId"], "native-1");
    assert!(prepare(
        "rewind",
        parse(
            "rewind",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"turnId":"t","mode":"automatic"}"#
            ]
        )
    )
    .is_err());
    assert_eq!(spec("rewind-files").capability, "agentChatRewindFilesV1");
}

#[test]
fn native_history_operation_is_a_read_and_checkpoint_configuration_is_explicit() {
    let operation = prepare(
        "native-history-operation",
        parse(
            "native-history-operation",
            &["--chat-id", "c", "--payload", r#"{"operationId":"o"}"#],
        ),
    )
    .unwrap();
    assert_eq!(operation["operationId"], "o");
    assert!(operation.get("requestId").is_none());
    assert_eq!(
        spec("native-history-operation").capability,
        "agentChatNativeHistoryV1"
    );
    let checkpoints = prepare(
        "file-checkpoints-configure",
        parse(
            "file-checkpoints-configure",
            &[
                "--chat-id",
                "c",
                "--payload",
                r#"{"enabled":false}"#,
                "--request-id",
                "checkpoint-1",
            ],
        ),
    )
    .unwrap();
    assert_eq!(checkpoints["enabled"], false);
    assert_eq!(checkpoints["requestId"], "checkpoint-1");
    assert_eq!(
        spec("file-checkpoints-configure").capability,
        "agentChatFileCheckpointsV1"
    );
    assert!(prepare(
        "file-checkpoints-configure",
        parse(
            "file-checkpoints-configure",
            &["--chat-id", "c", "--payload", r#"{"enabled":"true"}"#]
        )
    )
    .is_err());
}

#[test]
fn reconciliation_requires_an_exact_action_and_keeps_operation_revision_and_retry_id() {
    for action in [
        "finishAcknowledged",
        "restartFromTranscript",
        "cancelUnstarted",
        "continueFromCurrentFiles",
    ] {
        let raw = json!({"operationId":"o","expectedRevision":3,"action":action}).to_string();
        let input = || {
            parse(
                "native-history-reconcile",
                &[
                    "--chat-id",
                    "c",
                    "--payload",
                    &raw,
                    "--request-id",
                    "reconcile-1",
                ],
            )
        };
        let first = prepare("native-history-reconcile", input()).unwrap();
        assert_eq!(first, prepare("native-history-reconcile", input()).unwrap());
        assert_eq!(first["action"], action);
        assert_eq!(first["operationId"], "o");
        assert_eq!(first["expectedRevision"], 3);
        assert_eq!(first["requestId"], "reconcile-1");
    }
    for raw in [
        r#"{"operationId":"o","action":"retry"}"#,
        r#"{"operationId":"o","action":"finishAcknowledged","expectedRevision":-1}"#,
    ] {
        assert!(prepare(
            "native-history-reconcile",
            parse(
                "native-history-reconcile",
                &["--chat-id", "c", "--payload", raw]
            )
        )
        .is_err());
    }
}
