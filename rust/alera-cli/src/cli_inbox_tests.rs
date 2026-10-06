use clap::Parser;

use crate::cli::{Cli, Command};
use crate::cli_inbox::{parse_duration_ms, InboxAction};

fn parse(args: &[&str]) -> InboxAction {
    let mut argv = vec!["alera", "inbox"];
    argv.extend_from_slice(args);
    match Cli::try_parse_from(argv).unwrap().command {
        Command::Inbox(command) => command.action,
        other => panic!("unexpected command {other:?}"),
    }
}

#[test]
fn durations_accept_common_units() {
    assert_eq!(parse_duration_ms("500ms").unwrap(), 500);
    assert_eq!(parse_duration_ms("90").unwrap(), 90_000);
    assert_eq!(parse_duration_ms("30m").unwrap(), 1_800_000);
    assert_eq!(parse_duration_ms("5h").unwrap(), 18_000_000);
    assert_eq!(parse_duration_ms("7d").unwrap(), 604_800_000);
    assert!(parse_duration_ms("0s").is_err());
    assert!(parse_duration_ms("soon").is_err());
    assert!(parse_duration_ms("5w").is_err());
}

#[test]
fn ask_takes_a_workspace_and_an_agent() {
    let InboxAction::Ask(args) = parse(&[
        "ask",
        "--workspace",
        "ws-1",
        "--agent",
        "claude",
        "--body",
        "Risky?",
        "--expires-in",
        "30m",
        "--inbox",
        "ext:ci",
    ]) else {
        panic!("expected ask");
    };
    assert_eq!(args.workspace.as_deref(), Some("ws-1"));
    assert_eq!(args.agent.as_deref(), Some("claude"));
    assert_eq!(args.expires_in_ms, Some(1_800_000));
    assert_eq!(args.address.inbox.as_deref(), Some("ext:ci"));
}

#[test]
fn ask_rejects_conflicting_targets_and_bodies() {
    let argv = |args: &[&str]| {
        let mut argv = vec!["alera", "inbox", "ask"];
        argv.extend_from_slice(args);
        Cli::try_parse_from(argv)
    };
    assert!(argv(&["--to", "t", "--workspace", "w", "--body", "x"]).is_err());
    assert!(argv(&["--to", "t", "--body", "x", "--body-stdin"]).is_err());
    assert!(argv(&["--agent", "claude", "--body", "x"]).is_err());
    assert!(argv(&["--thread", "q", "--to", "t", "--body", "x"]).is_err());
}

#[test]
fn wait_and_purge_parse_their_flags() {
    let InboxAction::Wait(args) = parse(&[
        "wait",
        "--question",
        "msg_1",
        "--timeout",
        "2h",
        "--after",
        "9",
    ]) else {
        panic!("expected wait");
    };
    assert_eq!(args.question.as_deref(), Some("msg_1"));
    assert_eq!(args.timeout_ms, Some(7_200_000));
    assert_eq!(args.after, 9);
    let InboxAction::Purge(args) = parse(&["purge", "--inbox", "ext:ci", "--confirm"]) else {
        panic!("expected purge");
    };
    assert!(args.confirm);
}

#[test]
fn conversations_and_no_wait_asks_parse() {
    let InboxAction::Conversations(args) =
        parse(&["conversations", "--workspace", "ws", "--participant", "t"])
    else {
        panic!("expected conversations");
    };
    assert_eq!(args.workspace.as_deref(), Some("ws"));
    assert_eq!(args.participant.as_deref(), Some("t"));
    let InboxAction::Conversation(args) = parse(&["conversation", "--thread", "thread_1"]) else {
        panic!("expected conversation");
    };
    assert_eq!(args.thread, "thread_1");
    let ask = Cli::try_parse_from([
        "alera",
        "orchestration",
        "ask",
        "--to",
        "coord",
        "--question",
        "?",
        "--no-wait",
    ])
    .unwrap();
    let Command::Orchestration(command) = ask.command else {
        panic!("expected orchestration");
    };
    let crate::cli_orchestration::OrchestrationAction::Ask(args) = command.action else {
        panic!("expected ask");
    };
    assert!(args.no_wait);
    assert!(Cli::try_parse_from([
        "alera",
        "orchestration",
        "ask",
        "--to",
        "coord",
        "--question",
        "?",
        "--no-wait",
        "--timeout-ms",
        "10",
    ])
    .is_err());
}
