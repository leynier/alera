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
fn workspace_add_help_has_no_host_id_flag_and_is_local_only() {
    let help = clap_help(&["workspace", "add"]);
    let lower = help.to_lowercase();
    assert!(
        lower.contains("local"),
        "workspace add help should say the worktree is local: {help}"
    );
    assert!(
        help.contains("There is no --host-id"),
        "workspace add help should say there is no --host-id: {help}"
    );
    assert!(
        !help.contains("--host-id <"),
        "workspace add must not expose a --host-id flag: {help}"
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
