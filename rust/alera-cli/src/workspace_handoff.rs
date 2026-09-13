use anyhow::{anyhow, Result};
use serde_json::json;

use crate::cli::{RuntimeDirArgs, WorkspaceHandOffArgs, WorkspaceHandOnArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY;
use crate::workspace_context::resolve_requested_workspace_id;

pub async fn run_hand_off(
    runtime: RuntimeDirArgs,
    args: WorkspaceHandOffArgs,
    json_output: bool,
) -> i32 {
    match run_hand_off_inner(&runtime, args, json_output).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

pub async fn run_hand_on(
    runtime: RuntimeDirArgs,
    args: WorkspaceHandOnArgs,
    json_output: bool,
) -> i32 {
    match run_hand_on_inner(&runtime, args, json_output).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

async fn run_hand_off_inner(
    runtime: &RuntimeDirArgs,
    args: WorkspaceHandOffArgs,
    json_output: bool,
) -> Result<()> {
    if !args.confirm_shared_impact {
        anyhow::bail!("Pass --confirm-shared-impact to confirm the effect of Hand Off on the shared checkout.");
    }
    if args.move_changes == args.leave_changes {
        anyhow::bail!("Choose exactly one of --move-changes or --leave-changes.");
    }
    if args.reuse_existing_branch && (args.replacement_branch.is_none() || !args.move_changes) {
        anyhow::bail!(
            "Moving the current branch requires --replacement-branch and --move-changes."
        );
    }
    let id = resolve_requested_workspace_id(runtime, args.id.as_deref())
        .await?
        .ok_or_else(|| {
            anyhow!(
            "--id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        )
        })?;
    let relocation_id = args
        .relocation_id
        .unwrap_or_else(uuid::Uuid::new_v4)
        .to_string();
    let store = alera_core::runtime::RuntimeStore::open(&crate::runtime_dir(runtime)).await?;
    let workspace = store
        .find_workspace(&id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {id}"))?;
    let remote = workspace.host_id != alera_core::runtime::LOCAL_HOST_ID;
    let payload = json!({
        "id": id,
        "relocationId": relocation_id,
        "branch": args.branch,
        "name": args.name,
        "reuseExistingBranch": args.reuse_existing_branch,
        "workspaceRoot": relocation_path(args.workspace_root, remote)?,
        "path": relocation_path(args.path, remote)?,
        "moveChanges": args.move_changes,
        "replacementBranch": args.replacement_branch,
        "sharedImpactConfirmed": true,
    });
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY,
    )
    .await?;
    let value = crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard(
        &mut client,
        "handOff",
        &payload,
    )
    .await.map_err(|error| anyhow!("{error:#}. Retry the same choices with --relocation-id {relocation_id} to avoid repeating a completed relocation."))?;
    crate::print_value(&value, json_output, "workspace moved to its worktree; transferred local changes remain backed up in Git Stashes");
    Ok(())
}

fn relocation_path(value: Option<String>, remote: bool) -> Result<Option<String>> {
    if remote {
        Ok(value.and_then(|value| crate::normalized_workspace_path_value(&value)))
    } else {
        crate::host_accessible_optional_string_path(value)
    }
}

async fn run_hand_on_inner(
    runtime: &RuntimeDirArgs,
    args: WorkspaceHandOnArgs,
    json_output: bool,
) -> Result<()> {
    if !args.confirm_shared_impact {
        anyhow::bail!("Hand On changes the branch and files shared by tasks on the project folder. Pass --confirm-shared-impact to confirm; stop this task's processes before retrying.");
    }
    let id = resolve_requested_workspace_id(runtime, args.id.as_deref())
        .await?
        .ok_or_else(|| {
            anyhow!(
            "--id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        )
        })?;
    let relocation_id = args
        .relocation_id
        .unwrap_or_else(uuid::Uuid::new_v4)
        .to_string();
    let payload = json!({
        "id": id,
        "relocationId": relocation_id,
        "closeSessions": true,
        "sharedImpactConfirmed": true,
    });
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_SAFE_HANDOFF_CAPABILITY,
    )
    .await?;
    let value = crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard(
        &mut client,
        "handOn",
        &payload,
    )
    .await.map_err(|error| anyhow!("{error:#}. Retry the same choices with --relocation-id {relocation_id} to avoid repeating a completed relocation."))?;
    crate::print_value(&value, json_output, "workspace moved to the project folder; transferred local changes remain backed up in Git Stashes");
    Ok(())
}

#[cfg(test)]
mod confirmation_tests {
    use super::*;

    #[test]
    fn remote_relocation_paths_are_interpreted_only_by_the_owner() {
        for path in [
            r"C:\Worktrees\Task",
            r"\\server\share\Task",
            "/srv/worktrees/task",
            "~/worktrees/task",
            "relative/task",
        ] {
            assert_eq!(
                relocation_path(Some(path.into()), true).unwrap().as_deref(),
                Some(path)
            );
        }
        assert_eq!(
            relocation_path(Some("  /srv/task  ".into()), true)
                .unwrap()
                .as_deref(),
            Some("/srv/task")
        );
        assert!(relocation_path(Some("  ".into()), true).unwrap().is_none());
        assert!(relocation_path(None, true).unwrap().is_none());
    }

    #[test]
    fn local_relocation_paths_remain_relative_to_the_calling_directory() {
        let expected = std::env::current_dir().unwrap().join("relocation-target");
        assert_eq!(
            relocation_path(Some("relocation-target".into()), false)
                .unwrap()
                .as_deref(),
            expected.to_str()
        );
    }

    #[test]
    fn relocation_retry_ids_are_explicit_uuid_arguments_in_both_directions() {
        use clap::Parser;
        for command in ["hand-off", "hand-on"] {
            let mut args = vec![
                "alera",
                "workspace",
                command,
                "--id",
                "task",
                "--relocation-id",
            ];
            let mut invalid = args.clone();
            invalid.push("not-a-uuid");
            if command == "hand-off" {
                invalid.extend(["--branch", "topic"]);
            }
            assert!(crate::cli::Cli::try_parse_from(invalid).is_err());
            args.push("123e4567-e89b-12d3-a456-426614174000");
            if command == "hand-off" {
                args.extend(["--branch", "topic"]);
            }
            assert!(crate::cli::Cli::try_parse_from(args).is_ok());
        }
    }

    #[tokio::test]
    async fn hand_off_requires_change_scope_and_replacement_before_opening_a_runtime() {
        let root = tempfile::tempdir().unwrap();
        let runtime_path = root.path().join("unused-runtime");
        let runtime = RuntimeDirArgs {
            runtime_dir: Some(runtime_path.to_string_lossy().into_owned()),
        };
        let args = || WorkspaceHandOffArgs {
            relocation_id: None,
            id: Some("task".into()),
            branch: "topic".into(),
            name: None,
            reuse_existing_branch: false,
            workspace_root: None,
            path: None,
            move_changes: false,
            leave_changes: false,
            replacement_branch: None,
            confirm_shared_impact: true,
        };
        let error = run_hand_off_inner(&runtime, args(), true)
            .await
            .unwrap_err();
        assert!(error
            .to_string()
            .contains("--move-changes or --leave-changes"));
        let mut current_branch = args();
        current_branch.move_changes = true;
        current_branch.reuse_existing_branch = true;
        let error = run_hand_off_inner(&runtime, current_branch, true)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("--replacement-branch"));
        assert!(!runtime_path.exists());
    }

    #[tokio::test]
    async fn hand_on_requires_explicit_consent_before_opening_a_runtime() {
        let root = tempfile::tempdir().unwrap();
        let runtime_path = root.path().join("unused-runtime");
        let runtime = RuntimeDirArgs {
            runtime_dir: Some(runtime_path.to_string_lossy().into_owned()),
        };
        let error = run_hand_on_inner(
            &runtime,
            WorkspaceHandOnArgs {
                relocation_id: None,
                id: Some("task".into()),
                confirm_shared_impact: false,
            },
            true,
        )
        .await
        .unwrap_err();
        assert!(error.to_string().contains("--confirm-shared-impact"));
        assert!(!runtime_path.exists());
    }
}
