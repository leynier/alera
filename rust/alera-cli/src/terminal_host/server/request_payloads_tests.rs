use anyhow::Context;
use serde_json::json;

use super::*;
use crate::ssh_remote_command::RemoteCommandError;

#[test]
fn json_result_keeps_the_cause_of_a_failed_workspace_creation() {
    let created: anyhow::Result<Value> = Err(anyhow::anyhow!(
        "fatal: a branch named 'feature' already exists"
    ))
    .context("git worktree add failed");
    let error = json_result(created).unwrap_err();
    assert!(matches!(error, HostError::State(_)));
    assert_eq!(
        error.wire_message(),
        "git worktree add failed: fatal: a branch named 'feature' already exists"
    );
}

#[test]
fn json_result_types_a_failed_remote_command() {
    let result: anyhow::Result<Value> = Err(anyhow::Error::from(RemoteCommandError::Exit {
        program: "ssh".into(),
        code: Some(1),
        summary: "permission denied".into(),
        stderr_tail: "permission denied\n".into(),
        stdout_tail: String::new(),
    })
    .context("Could not inspect the remote checkout"));
    let response = json_result(result).unwrap_err().wire_response(3);
    assert_eq!(response["errorCode"], "remoteCommandFailed");
    assert_eq!(
        response["error"],
        "Could not inspect the remote checkout: ssh failed: permission denied"
    );
}

#[test]
fn json_result_passes_host_errors_through_unchanged() {
    let conflict: HostResult<Value> = Err(HostError::conflict(
        "sshTargetInUse",
        "SSH target is in use",
        json!({"workspaces": 1}),
    ));
    let response = json_result(conflict).unwrap_err().wire_response(1);
    assert_eq!(response["errorCode"], "sshTargetInUse");
    assert_eq!(response["error"], "SSH target is in use");

    let format: HostResult<Value> = Err(HostError::format("bad payload"));
    assert_eq!(
        json_result(format).unwrap_err().wire_message(),
        "FormatException: bad payload"
    );
}

#[test]
fn json_result_keeps_a_context_free_message_exact() {
    let result: anyhow::Result<()> = Err(anyhow::anyhow!(
        "A runtime mutation is in progress. Wait for it to finish and retry."
    ));
    assert_eq!(
        json_result(result).unwrap_err().wire_message(),
        "A runtime mutation is in progress. Wait for it to finish and retry."
    );
}

#[test]
fn json_result_serializes_the_success_value() {
    let result: anyhow::Result<Vec<u32>> = Ok(vec![1, 2]);
    assert_eq!(json_result(result).unwrap(), json!([1, 2]));
}
