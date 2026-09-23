use clap::Parser;

use crate::cli::{Cli, Command};
use crate::cli_orchestration::{OrchestrationAction, OrchestrationCommand};

#[test]
fn task_wait_defaults_include_every_terminal_task_state() {
    let default =
        Cli::try_parse_from(["alera", "orchestration", "task-wait", "--task", "task-1"]).unwrap();
    let explicit = Cli::try_parse_from([
        "alera",
        "orchestration",
        "task-wait",
        "--task",
        "task-1",
        "--for",
        "completed",
    ])
    .unwrap();

    assert!(matches!(
        default.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::TaskWait(args),
            ..
        }) if args.targets == "completed,failed,stalled,cancelled"
    ));
    assert!(matches!(
        explicit.command,
        Command::Orchestration(OrchestrationCommand {
            action: OrchestrationAction::TaskWait(args),
            ..
        }) if args.targets == "completed"
    ));
}
