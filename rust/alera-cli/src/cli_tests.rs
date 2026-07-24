use clap::Parser;

use crate::cli::{Cli, Command, IdArgs, WorkspaceAction, WorkspaceCommand};
use crate::cli_orchestration::{OrchestrationAction, OrchestrationCommand};

#[test]
fn workspace_pin_commands_parse_workspace_ids() {
    let pin = Cli::try_parse_from(["alera", "workspace", "pin", "--id", "workspace-1"]).unwrap();
    let unpin =
        Cli::try_parse_from(["alera", "workspace", "unpin", "--id", "workspace-2"]).unwrap();

    assert!(matches!(
        pin.command,
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Pin(IdArgs { id }),
            ..
        }) if id == "workspace-1"
    ));
    assert!(matches!(
        unpin.command,
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Unpin(IdArgs { id }),
            ..
        }) if id == "workspace-2"
    ));
}

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
