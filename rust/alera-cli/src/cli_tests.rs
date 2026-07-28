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

#[test]
fn browser_open_and_capture_commands_parse_page_contracts() {
    use crate::cli::{BrowserAction, BrowserCommand};

    let open = Cli::try_parse_from([
        "alera",
        "browser",
        "open",
        "--workspace-id",
        "workspace-1",
        "--url",
        "https://example.com",
        "--profile-id",
        "work",
    ])
    .unwrap();
    assert!(matches!(
        open.command,
        Command::Browser(BrowserCommand {
            action: BrowserAction::Open(args),
            ..
        }) if args.workspace_id == "workspace-1"
            && args.url == "https://example.com"
            && args.profile_id == "work"
    ));

    let capture = Cli::try_parse_from([
        "alera",
        "browser",
        "full-screenshot",
        "--page-id",
        "page-1",
        "--output",
        "capture.png",
    ])
    .unwrap();
    assert!(matches!(
        capture.command,
        Command::Browser(BrowserCommand {
            action: BrowserAction::FullScreenshot(args),
            ..
        }) if args.page.page_id == "page-1"
            && args.output.as_deref() == Some("capture.png")
    ));
}

#[test]
fn browser_search_engine_rejects_arbitrary_templates() {
    assert!(Cli::try_parse_from([
        "alera",
        "browser",
        "settings",
        "set",
        "--search-engine",
        "https://example.com/?q={query}",
    ])
    .is_err());
}

#[test]
fn browser_profile_mutation_requires_the_in_app_coordinator() {
    for action in ["upsert", "remove"] {
        assert!(Cli::try_parse_from(["alera", "browser", "profiles", action]).is_err());
    }
}
