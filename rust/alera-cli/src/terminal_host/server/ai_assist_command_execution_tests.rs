use super::*;
use std::collections::HashMap;

fn plan(
    binary: &str,
    arguments: Vec<String>,
    stdin_payload: Option<String>,
) -> AiAssistCommandPlan {
    AiAssistCommandPlan {
        binary: binary.into(),
        arguments,
        stdin_payload,
        label: "Fixture".into(),
        environment: HashMap::new(),
        temporary_directory: None,
    }
}

#[tokio::test]
async fn canceled_request_does_not_attempt_to_spawn() {
    let (cancel, receiver) = oneshot::channel();
    cancel.send(()).unwrap();
    let directory = tempfile::tempdir().unwrap();
    let command_directory = directory.path().join("command");
    std::fs::create_dir(&command_directory).unwrap();
    let mut command = plan("missing-fixture-executable", vec![], None);
    command.temporary_directory = Some(command_directory.clone());
    let error = run_command(command, ".", 30, receiver).await.unwrap_err();
    assert!(!command_directory.exists());
    assert!(error.to_string().contains("canceled"), "{error}");
}

#[tokio::test]
async fn output_is_bounded_while_reading() {
    assert_eq!(read_bounded(&b"valid"[..]).await.unwrap(), b"valid");
    let oversized = vec![b'a'; MAX_OUTPUT_BYTES + 1];
    assert!(read_bounded(oversized.as_slice()).await.is_err());
}

#[cfg(unix)]
#[tokio::test]
async fn deadline_covers_stdin_backpressure() {
    let (_cancel, receiver) = oneshot::channel();
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        run_command(
            plan(
                "/bin/sleep",
                vec!["30".into()],
                Some("x".repeat(8 * 1024 * 1024)),
            ),
            ".",
            1,
            receiver,
        ),
    )
    .await
    .expect("stdin must not bypass the deadline");
    let error = result.unwrap_err();
    assert!(error.to_string().contains("timed out"), "{error}");
}

#[cfg(unix)]
#[tokio::test]
async fn drains_output_before_agent_reads_its_input() {
    let (_cancel, receiver) = oneshot::channel();
    let script = "head -c 131072 /dev/zero; cat >/dev/null";
    let output = run_command(
        plan(
            "/bin/sh",
            vec!["-c".into(), script.into()],
            Some("x".repeat(1024 * 1024)),
        ),
        ".",
        10,
        receiver,
    )
    .await
    .unwrap();
    assert_eq!(output.len(), 131072);
}

#[cfg(unix)]
#[tokio::test]
async fn excessive_process_output_is_rejected_without_waiting_for_exit() {
    let (_cancel, receiver) = oneshot::channel();
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        run_command(
            plan(
                "/bin/sh",
                vec!["-c".into(), "exec head -c 2097152 /dev/zero".into()],
                None,
            ),
            ".",
            30,
            receiver,
        ),
    )
    .await
    .expect("output limit must interrupt the process exchange");
    let error = result.unwrap_err();
    assert!(error.to_string().contains("too much output"), "{error}");
}

#[cfg(unix)]
async fn workspace_owner() -> (tempfile::TempDir, AiAssistProcessOwner) {
    let (directory, actor) = super::super::checkout_buffer_guards_tests::fixture().await;
    let workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    (
        directory,
        AiAssistProcessOwner {
            store: actor.runtime_store.clone(),
            workspace,
            operation_id: "speech-fixture".into(),
        },
    )
}

#[cfg(unix)]
#[tokio::test]
async fn workspace_command_verifies_closure_and_releases_retirement_after_restart() {
    use alera_core::runtime::{RuntimeStore, WorkspaceProcessJobPhase};
    let (directory, owner) = workspace_owner().await;
    let store = owner.store.clone();
    let (cancel, receiver) = oneshot::channel();
    drop(cancel);
    let output = run_workspace_command(
        plan("/bin/sh", vec!["-c".into(), "printf ready".into()], None),
        owner,
        10,
        receiver,
    )
    .await;
    // A dropped sender means cancellation. This first request must not spawn.
    assert!(output.unwrap_err().to_string().contains("canceled"));
    assert!(store
        .workspace_process_jobs("task")
        .await
        .unwrap()
        .is_empty());
    let owner = AiAssistProcessOwner {
        store: store.clone(),
        workspace: store.find_workspace("task").await.unwrap().unwrap(),
        operation_id: "speech-fixture".into(),
    };
    let (_cancel, receiver) = oneshot::channel();
    assert_eq!(
        run_workspace_command(
            plan("/bin/sh", vec!["-c".into(), "printf ready".into()], None),
            owner,
            10,
            receiver,
        )
        .await
        .unwrap(),
        "ready"
    );
    let records = store.workspace_process_jobs("task").await.unwrap();
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].operation_id, "speech-fixture");
    assert_eq!(records[0].phase, WorkspaceProcessJobPhase::ClosureVerified);
    assert!(records[0].pid.is_some());
    assert!(store
        .workspace_process_jobs("sibling")
        .await
        .unwrap()
        .is_empty());
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    reopened
        .require_workspace_process_closure("task")
        .await
        .unwrap();
    assert_eq!(
        reopened.workspace_process_jobs("task").await.unwrap().len(),
        1
    );
}

#[cfg(unix)]
#[tokio::test]
async fn failed_workspace_spawn_is_persisted() {
    use alera_core::runtime::WorkspaceProcessJobPhase;
    let (_directory, owner) = workspace_owner().await;
    let store = owner.store.clone();
    let (_cancel, receiver) = oneshot::channel();
    assert!(run_workspace_command(
        plan("missing-fixture-executable", vec![], None),
        owner,
        10,
        receiver
    )
    .await
    .is_err());
    let records = store.workspace_process_jobs("task").await.unwrap();
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].phase, WorkspaceProcessJobPhase::SpawnFailed);
    assert!(records[0].pid.is_none());
}

#[cfg(unix)]
#[tokio::test]
async fn stale_workspace_identity_prevents_the_command_side_effect() {
    let (directory, mut owner) = workspace_owner().await;
    let store = owner.store.clone();
    owner.workspace.instance_id = "stale-instance".into();
    let (_cancel, receiver) = oneshot::channel();
    let error = run_workspace_command(
        plan(
            "/bin/sh",
            vec!["-c".into(), "printf unsafe > forbidden".into()],
            None,
        ),
        owner,
        10,
        receiver,
    )
    .await
    .unwrap_err();
    assert!(
        error.to_string().contains("identity or location changed"),
        "{error}"
    );
    assert!(!directory.path().join("forbidden").exists());
    assert!(store
        .workspace_process_jobs("task")
        .await
        .unwrap()
        .is_empty());
}

#[cfg(unix)]
#[tokio::test]
async fn workspace_cancellation_verifies_closure_without_erasing_ownership() {
    use crate::process_identity::{
        ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe,
    };
    use alera_core::runtime::WorkspaceProcessJobPhase;
    let (_directory, owner) = workspace_owner().await;
    let store = owner.store.clone();
    let (cancel, receiver) = oneshot::channel();
    let execution = tokio::spawn(run_workspace_command(
        plan("/bin/sleep", vec!["30".into()], None),
        owner,
        30,
        receiver,
    ));
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if store
                .workspace_process_jobs("task")
                .await
                .unwrap()
                .iter()
                .any(|job| job.phase == WorkspaceProcessJobPhase::Spawned)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("fixture must record the launched root");
    cancel.send(()).unwrap();
    let error = execution.await.unwrap().unwrap_err();
    assert!(error.to_string().contains("canceled"), "{error}");
    let records = store.workspace_process_jobs("task").await.unwrap();
    assert_eq!(records.len(), 1);
    let record = &records[0];
    assert_eq!(record.phase, WorkspaceProcessJobPhase::ClosureVerified);
    store
        .require_workspace_process_closure("task")
        .await
        .unwrap();
    let pid = record.pid.unwrap();
    let marker = record
        .start_marker
        .expect("the sleeping root must have a start marker");
    match SystemProcessIdentityProbe.lookup(pid) {
        ProcessLookup::Exited => {}
        ProcessLookup::Live(identity) => assert_ne!(identity.start_marker, marker),
        ProcessLookup::Unknown(error) => panic!("cannot verify fixture cleanup: {error}"),
    }
}

#[cfg(unix)]
#[tokio::test]
async fn workspace_command_closes_an_orphaned_session_child_and_preserves_a_neighbor() {
    use crate::process_identity::{
        ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe,
    };
    let (directory, owner) = workspace_owner().await;
    let mut neighbor = alera_core::child_process::windowless_async_command("/bin/sleep")
        .arg("30")
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let (_cancel, receiver) = oneshot::channel();
    let result = run_workspace_command(
        plan(
            "/bin/sh",
            vec![
                "-c".into(),
                "sleep 30 & printf '%s' \"$!\" > child.pid; printf ready".into(),
            ],
            None,
        ),
        owner,
        15,
        receiver,
    )
    .await;
    let neighbor_running = neighbor.try_wait().unwrap().is_none();
    neighbor.kill().await.unwrap();
    assert_eq!(result.unwrap(), "ready");
    assert!(
        neighbor_running,
        "a different process must survive scope cleanup"
    );
    let pid: u32 = std::fs::read_to_string(directory.path().join("child.pid"))
        .unwrap()
        .parse()
        .unwrap();
    assert!(
        matches!(
            SystemProcessIdentityProbe.lookup(pid),
            ProcessLookup::Exited
        ),
        "the orphaned session child must no longer run"
    );
}
