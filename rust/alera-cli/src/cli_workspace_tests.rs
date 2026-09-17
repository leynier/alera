use super::*;

use crate::cli::{IdArgs, WorkspaceSectionAction, WorkspaceSectionCommand};

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
fn workspace_section_commands_parse_names_ids_and_json_list() {
    let list = Cli::try_parse_from(["alera", "workspace", "--json", "section", "list"]).unwrap();
    match list.command {
        Command::Workspace(WorkspaceCommand {
            output,
            action: WorkspaceAction::Section(WorkspaceSectionCommand { action }),
            ..
        }) => {
            assert!(output.json);
            assert!(matches!(action, WorkspaceSectionAction::List));
        }
        other => panic!("expected workspace section list, got {other:?}"),
    }

    let create = Cli::try_parse_from([
        "alera",
        "workspace",
        "section",
        "create",
        "--name",
        "Alera",
        "--workspace-id",
        "workspace-1",
    ])
    .unwrap();
    match create.command {
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Section(WorkspaceSectionCommand { action }),
            ..
        }) => match action {
            WorkspaceSectionAction::Create(args) => {
                assert_eq!(args.name, "Alera");
                assert_eq!(args.workspace_id, "workspace-1");
            }
            other => panic!("expected create, got {other:?}"),
        },
        other => panic!("expected workspace section, got {other:?}"),
    }

    let set_by_name = Cli::try_parse_from([
        "alera",
        "workspace",
        "section",
        "set",
        "--workspace-id",
        "workspace-1",
        "--section",
        "Alera",
    ])
    .unwrap();
    match set_by_name.command {
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Section(WorkspaceSectionCommand { action }),
            ..
        }) => match action {
            WorkspaceSectionAction::Set(args) => {
                assert_eq!(args.workspace_id, "workspace-1");
                assert_eq!(args.section.as_deref(), Some("Alera"));
                assert!(args.section_id.is_none());
            }
            other => panic!("expected set, got {other:?}"),
        },
        other => panic!("expected workspace section, got {other:?}"),
    }

    let clear = Cli::try_parse_from([
        "alera",
        "workspace",
        "section",
        "clear",
        "--workspace-id",
        "workspace-1",
    ])
    .unwrap();
    assert!(matches!(
        clear.command,
        Command::Workspace(WorkspaceCommand {
            action: WorkspaceAction::Section(WorkspaceSectionCommand {
                action: WorkspaceSectionAction::Clear(args),
            }),
            ..
        }) if args.workspace_id == "workspace-1"
    ));

    assert!(Cli::try_parse_from([
        "alera",
        "workspace",
        "section",
        "set",
        "--workspace-id",
        "workspace-1",
        "--section",
        "Alera",
        "--section-id",
        "sec-1",
    ])
    .is_err());
    assert!(Cli::try_parse_from([
        "alera",
        "workspace",
        "add",
        "--project-id",
        "project",
        "--section",
        "Alera",
        "--section-id",
        "sec-1",
    ])
    .is_err());
}
