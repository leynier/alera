use clap::Parser;

use crate::cli::{Cli, Command};
use crate::cli_orchestration::{OrchestrationAction, OrchestrationCommand, TaskAction};

fn parse(args: &[&str]) -> Result<Cli, clap::Error> {
    Cli::try_parse_from(["alera", "orchestration"].iter().chain(args))
}

#[test]
fn task_wait_defaults_include_every_terminal_task_state() {
    let default = parse(&["task", "wait", "--id", "task-1"]).unwrap();
    let explicit = parse(&["task", "wait", "--id", "task-1", "--for", "completed"]).unwrap();

    assert!(matches!(
        default.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::Task(TaskAction::Wait(args)),
            ..
        }) if args.targets == "completed,failed,stalled,cancelled"
    ));
    assert!(matches!(
        explicit.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::Task(TaskAction::Wait(args)),
            ..
        }) if args.targets == "completed"
    ));
}

#[test]
fn removed_verbs_no_longer_parse() {
    for verb in [
        "task-create",
        "agent-spawn",
        "board",
        "run-snapshot",
        "task-inspect",
        "run-list",
        "run-show",
        "run-stop",
        "status",
        "task-list",
        "task-show",
        "gate-resolve",
        "plan-propose",
        "dispatch-accept",
        "heartbeat",
        "worker-done",
        "worker-help",
        "inbox",
        "recipes",
    ] {
        assert!(
            parse(&[verb, "--help"])
                .is_err_and(|error| { error.kind() != clap::error::ErrorKind::DisplayHelp }),
            "{verb} still parses"
        );
    }
}

#[test]
fn delegate_folds_the_task_options() {
    parse(&[
        "delegate",
        "--profile",
        "Worker",
        "--spec",
        "Fix",
        "--terminal",
        "t-1",
        "--run",
        "run-1",
        "--stage",
        "build",
        "--depends-on",
        "a,b",
    ])
    .unwrap();
    assert!(parse(&[
        "delegate",
        "--profile",
        "Worker",
        "--spec",
        "Fix",
        "--terminal",
        "t-1",
        "--new-workspace",
    ])
    .is_err());
    assert!(parse(&["delegate", "--profile", "W", "--spec", "x", "--branch", "b"]).is_err());
}

#[test]
fn run_retry_needs_exactly_one_target() {
    assert!(parse(&["run", "retry", "--run", "r"]).is_err());
    assert!(parse(&[
        "run",
        "retry",
        "--run",
        "r",
        "--task",
        "t",
        "--cancellation"
    ])
    .is_err());
    parse(&["run", "retry", "--run", "r", "--integration", "t"]).unwrap();
}

#[test]
fn completion_takes_only_the_summary_as_required() {
    parse(&["complete", "--summary", "done"]).unwrap();
    parse(&[
        "complete",
        "--summary",
        "x",
        "--kind",
        "failure",
        "--files",
        "a,b",
    ])
    .unwrap();
    assert!(parse(&["complete", "--summary", "x", "--completion-kind", "failure"]).is_err());
}
