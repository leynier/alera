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
fn ssh_target_help_states_bootstrap_is_sidecar_only() {
    let help = clap_help(&["ssh-target"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("sidecar only"),
        "ssh-target help should state bootstrap is sidecar only: {help}"
    );
    assert!(
        lower.contains("does not create remote workspaces"),
        "ssh-target help should say it does not create remote workspaces: {help}"
    );
}

#[test]
fn ssh_target_bootstrap_help_states_no_remote_worktree() {
    let help = clap_help(&["ssh-target", "bootstrap"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("sidecar"),
        "bootstrap help should mention the sidecar: {help}"
    );
    assert!(
        lower.contains("does not create a remote git worktree"),
        "bootstrap help should deny remote worktree create: {help}"
    );
}

#[test]
fn workspace_add_help_documents_host_id_for_ssh_targets() {
    let help = clap_help(&["workspace", "add"]);
    let lower = help.to_lowercase();
    assert!(
        help.contains("--host-id"),
        "workspace add help should document --host-id: {help}"
    );
    assert!(
        lower.contains("ssh") || lower.contains("bootstrapped"),
        "workspace add help should mention SSH targeting: {help}"
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
