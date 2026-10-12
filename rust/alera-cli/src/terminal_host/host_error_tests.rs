use anyhow::Context;

use super::*;
use crate::ssh_remote_command::RemoteCommandBudget;

#[test]
fn plain_errors_keep_their_context_chain_as_state() {
    let error = anyhow::anyhow!("permission denied").context("Could not inspect the checkout");
    let host_error = HostError::from_anyhow(&error);
    assert!(matches!(host_error, HostError::State(_)));
    assert_eq!(
        host_error.wire_message(),
        "Could not inspect the checkout: permission denied"
    );
}

#[test]
fn a_failed_remote_command_becomes_a_conflict_with_its_output() {
    let error = anyhow::Error::from(RemoteCommandError::Exit {
        program: "ssh".into(),
        code: Some(128),
        summary: "fatal: not a git repository".into(),
        stderr_tail: "fatal: not a git repository\n".into(),
        stdout_tail: "partial\n".into(),
    })
    .context("Could not create the worktree");
    let host_error = HostError::from_anyhow(&error);
    let response = host_error.wire_response(7);
    assert_eq!(response["errorCode"], "remoteCommandFailed");
    assert_eq!(
        response["error"],
        "Could not create the worktree: ssh failed: fatal: not a git repository"
    );
    assert_eq!(response["errorDetails"]["exitCode"], 128);
    assert_eq!(
        response["errorDetails"]["stderr"],
        "fatal: not a git repository\n"
    );
    assert_eq!(response["errorDetails"]["stdout"], "partial\n");
}

#[test]
fn a_timed_out_remote_command_is_a_conflict_without_an_exit_code() {
    let error: anyhow::Result<()> = Err(RemoteCommandError::Timeout {
        budget: RemoteCommandBudget::Command,
        program: "ssh".into(),
    }
    .into());
    let error = error.context("SSH branch inspection failed").unwrap_err();
    let response = HostError::from_anyhow(&error).wire_response(1);
    assert_eq!(response["errorCode"], "remoteCommandFailed");
    assert!(response["errorDetails"]["exitCode"].is_null());
    assert_eq!(response["errorDetails"]["timedOut"], true);
    assert_eq!(response["errorDetails"]["timeoutSeconds"], 60);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("within its command (60s) budget"));
}
