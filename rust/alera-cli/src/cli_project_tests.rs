use clap::Parser;

use crate::cli::{Cli, Command};

#[test]
fn project_removal_requires_explicit_automation_cancellation_flag() {
    for approved in [false, true] {
        let mut arguments = vec!["alera", "project", "remove", "--id", "project"];
        if approved {
            arguments.push("--pause-automations-and-cancel-runs");
        }
        let parsed = Cli::try_parse_from(arguments).unwrap();
        let Command::Project(command) = parsed.command else {
            panic!("project command expected");
        };
        let crate::cli::ProjectAction::Remove(args) = command.action else {
            panic!("remove action expected");
        };
        assert_eq!(args.pause_automations_and_cancel_runs, approved);
    }
}
