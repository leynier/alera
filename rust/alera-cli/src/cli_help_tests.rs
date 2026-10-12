use clap::Parser;

use crate::cli::Cli;

fn clap_help(args: &[&str]) -> String {
    let mut argv = Vec::with_capacity(args.len() + 2);
    argv.push("alera");
    argv.extend_from_slice(args);
    argv.push("--help");
    Cli::try_parse_from(argv)
        .expect_err("help should exit before parsing a command")
        .to_string()
}

#[test]
fn ssh_target_help_states_bootstrap_installs_the_runtime_only() {
    let help = clap_help(&["ssh-target"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("installs the alera runtime only"),
        "ssh-target help should state bootstrap installs the runtime only: {help}"
    );
    assert!(
        lower.contains("does not create remote workspaces"),
        "ssh-target help should say it does not create remote workspaces: {help}"
    );
    assert!(
        help.contains("update"),
        "ssh-target help should list update: {help}"
    );
    assert!(
        !lower.contains("sidecar"),
        "ssh-target help should speak of the Alera runtime: {help}"
    );
}

#[test]
fn ssh_target_bootstrap_help_states_no_remote_worktree() {
    let help = clap_help(&["ssh-target", "bootstrap"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("alera runtime"),
        "bootstrap help should mention the Alera runtime: {help}"
    );
    assert!(
        lower.contains("does not create a remote git worktree"),
        "bootstrap help should deny remote worktree create: {help}"
    );
}

#[test]
fn ssh_target_runtime_update_commands_parse() {
    use crate::cli::{Command, SshTargetAction};
    let action = |args: &[&str]| {
        let mut argv = vec!["alera", "ssh-target"];
        argv.extend_from_slice(args);
        match Cli::try_parse_from(argv).map(|cli| cli.command) {
            Ok(Command::SshTarget(command)) => Ok(command.action),
            Ok(other) => panic!("unexpected command {other:?}"),
            Err(error) => Err(error),
        }
    };
    match action(&["update-runtime", "--id", "lab", "--force"]).unwrap() {
        SshTargetAction::UpdateRuntime(args) => assert!(args.id == "lab" && args.force),
        other => panic!("unexpected action {other:?}"),
    }
    match action(&["restart-runtime", "--id", "lab"]).unwrap() {
        SshTargetAction::RestartRuntime(args) => assert!(args.id == "lab" && !args.force),
        other => panic!("unexpected action {other:?}"),
    }
    match action(&["bootstrap", "--id", "lab", "--restart-runtime", "--force"]).unwrap() {
        SshTargetAction::Bootstrap(args) => assert!(args.restart_runtime && args.force),
        other => panic!("unexpected action {other:?}"),
    }
    assert!(
        action(&["bootstrap", "--id", "lab", "--force"]).is_err(),
        "--force only means something with --restart-runtime"
    );
}

#[test]
fn workspace_add_help_documents_host_id_for_remote_hosts() {
    for command in [
        &["workspace", "add"][..],
        &["workspace", "start"][..],
        &["workspace", "prompt-start", "run"][..],
    ] {
        let help = clap_help(command);
        assert!(
            help.contains("--host-id"),
            "{command:?} help should document --host-id: {help}"
        );
        assert!(
            help.contains("ssh-target list") && help.contains("primary host"),
            "{command:?} help should name host ids and the primary host default: {help}"
        );
    }
    let list = clap_help(&["workspace", "list"]);
    assert!(
        list.contains("origin"),
        "workspace list should document the origin host: {list}"
    );
}

#[test]
fn retired_and_internal_commands_stay_out_of_help() {
    let top = clap_help(&[]);
    assert!(
        !top.contains("runtime-proxy"),
        "runtime-proxy is started by the app: {top}"
    );
    let project = clap_help(&["project"]);
    for hidden in ["register-checkout", "register-owner-workspace"] {
        assert!(
            !project.contains(hidden),
            "project help should not list {hidden}: {project}"
        );
    }
    assert!(
        Cli::try_parse_from([
            "alera",
            "project",
            "register-owner-workspace",
            "--state-dir",
            "/tmp/state",
            "--metadata-base64",
            "e30=",
        ])
        .is_err(),
        "register-owner-workspace was removed"
    );
    assert!(
        Cli::try_parse_from([
            "alera",
            "project",
            "register-checkout",
            "--project-id",
            "p",
            "--host-id",
            "h",
            "--path",
            "/srv/p",
            "--clone-url",
            "git@example.test:o/p.git",
        ])
        .is_ok(),
        "register-checkout stays as a hidden alias of hosts add"
    );
}

#[test]
fn workspace_register_help_states_host_id_is_metadata_only() {
    let help = clap_help(&["workspace", "register"]);
    let lower = help.to_lowercase();
    assert!(
        help.contains("--host-id"),
        "workspace register help should document --host-id: {help}"
    );
    assert!(
        lower.contains("metadata only"),
        "workspace register help should say --host-id is metadata only: {help}"
    );
    assert!(
        lower.contains("does not create") && lower.contains("remote"),
        "workspace register help should deny remote worktree create: {help}"
    );
}

#[test]
fn issue_commands_document_their_providers_and_workspace_default() {
    let add = clap_help(&["workspace", "add"]);
    assert!(
        add.contains("--issue"),
        "workspace add should document --issue: {add}"
    );
    let start = clap_help(&["workspace", "start"]);
    assert!(
        start.contains("--issue"),
        "workspace start should document --issue: {start}"
    );
    let issue = clap_help(&["workspace", "issue"]);
    for verb in ["show", "link", "unlink"] {
        assert!(
            issue.contains(verb),
            "workspace issue should list {verb}: {issue}"
        );
    }
    let link = clap_help(&["workspace", "issue", "link"]);
    assert!(
        link.contains("ALERA_WORKSPACE_ID"),
        "link should default the workspace: {link}"
    );
    let show = clap_help(&["issue", "show"]);
    assert!(
        show.contains("gh") && show.contains("glab") && show.contains("az boards")
            || clap_help(&["issue"]).contains("az boards")
    );
}

#[test]
fn workspace_pr_watch_help_documents_start_stop_and_defaults() {
    let help = clap_help(&["workspace", "pr-watch"]);
    for verb in ["show", "start", "stop"] {
        assert!(
            help.contains(verb),
            "workspace pr-watch should list {verb}: {help}"
        );
    }
    let start = clap_help(&["workspace", "pr-watch", "start"]);
    assert!(
        start.contains("ALERA_WORKSPACE_ID"),
        "start should default the workspace: {start}"
    );
    assert!(
        start.contains("ALERA_TERMINAL_HANDLE"),
        "start should default the terminal handle: {start}"
    );
    assert!(
        start.contains("--merge"),
        "start should document --merge: {start}"
    );
    assert!(
        start.contains("--no-checks")
            && start.contains("--no-comments")
            && start.contains("--no-conflicts"),
        "start should document scope flags: {start}"
    );
}

#[test]
fn workspace_section_commands_are_documented() {
    let workspace = clap_help(&["workspace"]);
    assert!(
        workspace.contains("section"),
        "workspace help should list section: {workspace}"
    );
    let section = clap_help(&["workspace", "section"]);
    for verb in ["list", "create", "set", "clear", "remove"] {
        assert!(
            section.contains(verb),
            "workspace section should list {verb}: {section}"
        );
    }
    let create = clap_help(&["workspace", "section", "create"]);
    assert!(
        create.contains("--name") && create.contains("--workspace-id"),
        "section create should document name and workspace: {create}"
    );
    let set = clap_help(&["workspace", "section", "set"]);
    assert!(
        set.contains("--section") && set.contains("--section-id") && set.contains("--workspace-id"),
        "section set should document name, id, and workspace: {set}"
    );
    let add = clap_help(&["workspace", "add"]);
    assert!(
        add.contains("--section") && add.contains("--section-id"),
        "workspace add should document optional section flags: {add}"
    );
    let start = clap_help(&["workspace", "start"]);
    assert!(
        start.contains("--section") && start.contains("--section-id"),
        "workspace start should document optional section flags: {start}"
    );
}

#[test]
fn voice_help_documents_home_and_speak() {
    let help = clap_help(&["voice"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("speak"),
        "voice help should document speak: {help}"
    );
    assert!(
        lower.contains("ensure"),
        "voice help should document ensure: {help}"
    );
    assert!(
        lower.contains("status"),
        "voice help should document status: {help}"
    );
}

#[test]
fn orchestration_help_lists_the_reduced_command_set() {
    let help = clap_help(&["orchestration"]);
    for verb in [
        "delegate",
        "run",
        "plan",
        "gate",
        "context",
        "complete",
        "escalate",
        "ask",
        "reply",
        "send",
        "check",
        "messages",
        "task",
        "transfer-coordinator",
        "dispatch",
        "terminal",
        "agent-profiles",
        "current",
        "reset",
        "recipe",
    ] {
        assert!(
            help.lines()
                .any(|line| line.trim_start().starts_with(&format!("{verb} "))),
            "orchestration help should list {verb}: {help}"
        );
    }
    for removed in [
        "task-create",
        "agent-spawn",
        "board",
        "run-snapshot",
        "task-inspect",
        "run-list",
        "dispatch-accept",
        "heartbeat",
        "worker-help",
    ] {
        assert!(
            !help.contains(removed),
            "orchestration help still lists {removed}: {help}"
        );
    }
    let run = clap_help(&["orchestration", "run"]);
    for verb in [
        "new",
        "list",
        "show",
        "timeline",
        "cancel",
        "pause",
        "resume",
        "replan",
        "retry",
        "resources",
        "integrations",
        "cleanup",
    ] {
        assert!(run.contains(verb), "run help should list {verb}: {run}");
    }
    let cleanup = clap_help(&["orchestration", "run", "cleanup"]);
    for verb in ["preview", "apply", "status", "list", "retry", "abandon"] {
        assert!(
            cleanup.contains(verb),
            "cleanup help should list {verb}: {cleanup}"
        );
    }
    let new = clap_help(&["orchestration", "run", "new"]);
    for flag in ["--isolation", "--template", "--approval", "--profile"] {
        assert!(new.contains(flag), "run new should document {flag}: {new}");
    }
    let delegate = clap_help(&["orchestration", "delegate"]);
    for flag in [
        "--terminal",
        "--stage",
        "--depends-on",
        "--contract",
        "--contract-inputs",
        "--run",
        "--new-workspace",
    ] {
        assert!(
            delegate.contains(flag),
            "delegate should document {flag}: {delegate}"
        );
    }
}

#[test]
fn ask_commands_document_delivery() {
    let ask = clap_help(&["orchestration", "ask"]);
    assert!(ask.contains("--delivery") && ask.contains("--no-wait"));
    let send = clap_help(&["orchestration", "send"]);
    assert!(send.contains("--delivery"));
    let inbox = clap_help(&["inbox", "ask"]);
    assert!(inbox.contains("--deliver"));
}
