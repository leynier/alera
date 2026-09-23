use std::time::Duration;

use crate::terminal_host::session::windows_process_job::WindowsProcessJob;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::{AiAssistProcessOwner, WorkspaceProcessJobPhase};

#[tokio::test]
async fn ai_assist_windows_journal_requires_verified_job_closure_after_root_exit() {
    let (root, actor) = super::super::checkout_buffer_guards_tests::fixture().await;
    let owner = AiAssistProcessOwner {
        store: actor.runtime_store.clone(),
        workspace: actor
            .runtime_store
            .find_workspace("task")
            .await
            .unwrap()
            .unwrap(),
        operation_id: "windows-closure".into(),
    };
    let mut journal = owner.begin().await.unwrap();
    let job = WindowsProcessJob::create().unwrap();
    let bootstrap = job.command_bootstrap("unused", &[]).unwrap();
    let mut command =
        alera_core::child_process::windowless_async_command(std::env::current_exe().unwrap());
    for (key, value) in bootstrap.as_std().get_envs() {
        if let Some(value) = value {
            command.env(key, value);
        }
    }
    command
        .args([
            "--exact",
            "pty_job_bootstrap::tests::job_tree_child",
            "--nocapture",
        ])
        .env("ALERA_PTY_JOB_TEST_CHILD", "exit")
        .env(
            "ALERA_PTY_JOB_TEST_PID_FILE",
            root.path().join("descendant.pid"),
        )
        .kill_on_drop(true);
    let mut child = command.spawn().unwrap();
    journal.spawned(child.id().unwrap()).await.unwrap();
    job.assign_command_and_release(&child).unwrap();
    let mut scope = WorkspaceShutdown::capture_command_job(&job).unwrap();
    assert!(tokio::time::timeout(Duration::from_secs(15), child.wait())
        .await
        .unwrap()
        .unwrap()
        .success());
    journal.root_exited().await.unwrap();
    assert!(owner
        .store
        .require_workspace_process_closure("task")
        .await
        .is_err());
    scope.fail_next_waits(1);
    assert!(journal.windows_job_closed(&mut scope).await.is_err());
    assert_eq!(journal.record.phase, WorkspaceProcessJobPhase::RootExited);
    assert!(owner
        .store
        .require_workspace_process_closure("task")
        .await
        .is_err());
    journal.windows_job_closed(&mut scope).await.unwrap();
    assert_eq!(
        journal.record.phase,
        WorkspaceProcessJobPhase::ClosureVerified
    );
    owner
        .store
        .require_workspace_process_closure("task")
        .await
        .unwrap();
}
