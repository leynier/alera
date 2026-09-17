use clap::Parser;

use crate::cli::{Cli, Command, WorkspaceAction, WorkspaceCommand};

#[test]
fn issue_commands_parse_urls_and_workspace_targets() {
    use crate::cli::{IssueAction, WorkspaceIssueAction};

    let show = Cli::try_parse_from([
        "alera",
        "issue",
        "--json",
        "show",
        "https://github.com/leynier/alera/issues/758",
    ])
    .unwrap();
    let Command::Issue(command) = show.command else {
        panic!("expected issue command");
    };
    assert!(command.output.json);
    let IssueAction::Show(args) = command.action;
    assert_eq!(args.url, "https://github.com/leynier/alera/issues/758");

    let link = Cli::try_parse_from([
        "alera",
        "workspace",
        "issue",
        "link",
        "--workspace-id",
        "w1",
        "https://gitlab.com/a/b/-/issues/3",
    ])
    .unwrap();
    let Command::Workspace(WorkspaceCommand {
        action: WorkspaceAction::Issue(issue),
        ..
    }) = link.command
    else {
        panic!("expected workspace issue command");
    };
    let WorkspaceIssueAction::Link(args) = issue.action else {
        panic!("expected link");
    };
    assert_eq!(args.target.workspace_id.as_deref(), Some("w1"));
    assert_eq!(args.url, "https://gitlab.com/a/b/-/issues/3");

    let add = Cli::try_parse_from([
        "alera",
        "workspace",
        "add",
        "--project-id",
        "p",
        "--worktree",
        "--branch",
        "b",
        "--issue",
        "https://dev.azure.com/o/p/_workitems/edit/1",
    ])
    .unwrap();
    let Command::Workspace(WorkspaceCommand {
        action: WorkspaceAction::Add(args),
        ..
    }) = add.command
    else {
        panic!("expected workspace add");
    };
    assert_eq!(
        args.issue.as_deref(),
        Some("https://dev.azure.com/o/p/_workitems/edit/1")
    );
    assert!(Cli::try_parse_from(["alera", "workspace", "issue", "link"]).is_err());
}
