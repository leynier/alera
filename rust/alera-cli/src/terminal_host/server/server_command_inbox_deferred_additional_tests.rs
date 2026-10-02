use std::time::Duration;

use serde_json::json;

use crate::terminal_host::host_error::HostError;
use crate::terminal_host::server::runtime_mutations::{
    HandOnSessionRelocate, RuntimeMutationCompletion, RuntimeMutationEffect,
    RuntimeMutationFinished, RuntimeMutationOutcome,
};
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;

use super::*;

type WorkflowLaunchCommand = super::super::workflow_launch_requests::WorkflowLaunchCommand;
type WorkflowLaunchReply = super::super::workflow_launch_requests::WorkflowLaunchReply;
type ValidatedWorkflowLaunch = super::super::workflow_launch_requests::ValidatedWorkflowLaunch;
type ExecutionPass = super::super::workflow_launch_requests::execution::ExecutionPass;

fn fill_control_and_request_shutdown(inbox: &ServerInbox) {
    super::deferred_tests::fill_control_and_request_shutdown(inbox);
}

async fn next_deferred(receiver: &mut ServerInboxReceiver) -> ServerCommand {
    super::deferred_tests::next_deferred(receiver).await
}

fn oversized_message() -> String {
    super::deferred_tests::oversized_message()
}

#[tokio::test]
async fn workflow_execution_and_cancellation_completions_survive_shutdown() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    let (reply, done) = tokio::sync::oneshot::channel();
    for command in [
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::CancellationFinished(Err(
            HostError::state("cancellation failed"),
        ))),
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::ExecutionFinished(
            ExecutionPass::from_test(Some("cursor-1".to_string()), true, true, None),
        )),
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::ExecutionPrepared {
            reply,
            result: Err(HostError::state("execution preparation failed")),
        }),
    ] {
        inbox
            .send_wait(command)
            .await
            .expect("workflow completion must survive shutdown admission closure");
    }

    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::CancellationFinished(result)) => {
            assert!(result.is_err());
        }
        _ => panic!("unexpected cancellation completion"),
    }
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::ExecutionFinished(pass)) => {
            let (cursor, again, changed, _error) = pass.into_test_parts();
            assert_eq!(cursor.as_deref(), Some("cursor-1"));
            assert!(again);
            assert!(changed);
        }
        _ => panic!("unexpected execution completion"),
    }
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::ExecutionPrepared {
            reply,
            result,
        }) => {
            assert!(result.is_err());
            reply
                .send(Ok(json!({"accepted": true})))
                .expect("execution reply receiver");
        }
        _ => panic!("unexpected prepared execution completion"),
    }
    assert_eq!(done.await.unwrap().unwrap()["accepted"], true);
}

#[tokio::test]
async fn oversized_workflow_claim_preserves_cleanup_identity() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    let mut record = super::deferred_tests::launch_record("claimed-oversized");
    record.error = Some(oversized_message());
    inbox
        .send_wait(ServerCommand::WorkflowLaunch(
            WorkflowLaunchCommand::Claimed {
                reply: WorkflowLaunchReply::Client(9, 90),
                record: Box::new(record),
                token: oversized_message(),
                locks: [
                    tempfile::tempfile().expect("claim lock"),
                    tempfile::tempfile().expect("attempt lock"),
                ],
                result: Box::new(Err(HostError::state("claim failed"))),
            },
        ))
        .await
        .expect("oversized claim must become a bounded completion");
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::Claimed {
            reply: WorkflowLaunchReply::Client(client_id, request_id),
            record,
            token,
            result,
            ..
        }) => {
            assert_eq!((client_id, request_id), (9, 90));
            assert_eq!(record.id, "claimed-oversized");
            assert!(record.error.as_ref().is_none_or(|value| value.len() < 256));
            assert!(token.len() < 256);
            assert!(result.is_err());
        }
        _ => panic!("unexpected oversized claim completion"),
    }
}

#[tokio::test]
async fn oversized_spawn_validation_preserves_cleanup_identity() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    let mut record = super::deferred_tests::launch_record("spawn-oversized");
    record.error = Some(oversized_message());
    let mut frozen = super::deferred_tests::workflow_inputs();
    frozen.plan_digest = oversized_message();
    let command = ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::SpawnValidated(Box::new(
        ValidatedWorkflowLaunch::from_test(
            WorkflowLaunchReply::Client(9, 91),
            record,
            oversized_message(),
            [
                tempfile::tempfile().expect("claim lock"),
                tempfile::tempfile().expect("attempt lock"),
            ],
            frozen,
            Err(HostError::state("spawn validation failed")),
        ),
    )));
    inbox
        .send_wait(command)
        .await
        .expect("oversized spawn validation must become a bounded completion");
    match next_deferred(&mut receiver).await {
        ServerCommand::WorkflowLaunch(WorkflowLaunchCommand::SpawnValidated(validated)) => {
            let (reply, record, token, _locks, frozen, result) = (*validated).into_test_parts();
            assert!(matches!(reply, WorkflowLaunchReply::Client(9, 91)));
            assert_eq!(record.id, "spawn-oversized");
            assert!(record.error.as_ref().is_none_or(|value| value.len() < 256));
            assert!(token.len() < 256);
            assert!(frozen.plan_digest.len() < 256);
            assert!(result.is_err());
        }
        _ => panic!("unexpected oversized spawn validation completion"),
    }
}

fn oversized_runtime_mutation(client_id: u64, request_id: i64) -> ServerCommand {
    let large_id = "x".repeat(
        crate::terminal_host::server::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES / 4,
    );
    let mut shutdown = WorkspaceShutdown::default();
    shutdown.closed_tab_ids = vec!["pending-small".to_string(), large_id.clone()];
    ServerCommand::RuntimeMutationFinished(RuntimeMutationFinished {
        client_id,
        request_id,
        outcome: RuntimeMutationOutcome {
            result: Ok(RuntimeMutationCompletion {
                response: json!({"cleanup": "complete"}),
                effect: RuntimeMutationEffect::WorkspaceRemoved {
                    workspace_id: format!("workspace-result-{large_id}"),
                },
                closed_tab_ids: vec!["closed-result".to_string()],
                hand_on_relocate: Some(Box::new(HandOnSessionRelocate {
                    source_workspace_id: format!("source-{large_id}"),
                    destination_workspace_id: format!("destination-{large_id}"),
                    source_path: format!("/tmp/source-{large_id}"),
                    dest_path: format!("/tmp/destination-{large_id}"),
                })),
            }),
            completion_on_error: None,
            ended_pointer_tab_ids: vec!["pointer-small".to_string(), large_id.clone()],
            closed_session_tab_ids: vec!["closed-session".to_string(), large_id.clone()],
            committed_tab_ids: vec!["committed".to_string(), large_id.clone()],
            effect_on_error: Some(RuntimeMutationEffect::WorkspaceRelocated {
                project_id: "project".to_string(),
                workspace_id: "workspace-error".to_string(),
                source_path: large_id.clone(),
            }),
            stopped_workspace_tab_ids: vec!["stopped".to_string(), large_id.clone()],
            pending_workspace_shutdown: Some(Box::new(("pending-workspace".to_string(), shutdown))),
        },
    })
}

#[tokio::test]
async fn oversized_runtime_mutation_keeps_cleanup_metadata_with_bounded_error() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_and_request_shutdown(&inbox);
    inbox
        .send_wait(oversized_runtime_mutation(10, 101))
        .await
        .expect("oversized mutation must become a bounded completion");
    match next_deferred(&mut receiver).await {
        ServerCommand::RuntimeMutationFinished(finished) => {
            assert_eq!((finished.client_id, finished.request_id), (10, 101));
            assert!(finished.outcome.result.is_err());
            assert!(finished.outcome.ended_pointer_tab_ids.is_empty());
            assert!(finished.outcome.closed_session_tab_ids.is_empty());
            assert!(finished.outcome.committed_tab_ids.is_empty());
            assert_eq!(finished.outcome.stopped_workspace_tab_ids[0], "stopped");
            let large_id = "x".repeat(
                crate::terminal_host::server::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES
                    / 4,
            );
            assert!(finished
                .outcome
                .stopped_workspace_tab_ids
                .contains(&large_id));
            assert!(matches!(
                finished.outcome.effect_on_error.as_ref(),
                Some(RuntimeMutationEffect::WorkspaceRelocated { source_path, .. })
                    if source_path == &large_id
            ));
            let pending = finished
                .outcome
                .pending_workspace_shutdown
                .as_ref()
                .unwrap();
            assert_eq!(pending.1.closed_tab_ids[0], "pending-small");
            assert!(pending.1.closed_tab_ids.contains(&large_id));
            let completion = finished
                .outcome
                .completion_on_error
                .as_ref()
                .expect("oversized mutation keeps its cleanup completion");
            assert!(completion.closed_tab_ids.is_empty());
            assert!(matches!(
                &completion.effect,
                RuntimeMutationEffect::WorkspaceRemoved { workspace_id }
                    if workspace_id == &format!("workspace-result-{large_id}")
            ));
            let relocate = completion
                .hand_on_relocate
                .as_ref()
                .expect("oversized mutation keeps relocation ownership");
            assert_eq!(relocate.source_workspace_id, format!("source-{large_id}"));
            assert_eq!(
                relocate.destination_workspace_id,
                format!("destination-{large_id}")
            );
            assert_eq!(relocate.source_path, format!("/tmp/source-{large_id}"));
            assert_eq!(relocate.dest_path, format!("/tmp/destination-{large_id}"));
        }
        _ => panic!("unexpected runtime mutation completion"),
    }
}

#[tokio::test]
async fn oversized_runtime_metadata_uses_exclusive_completion_admission() {
    let (inbox, mut receiver) = ServerInbox::channel();
    inbox
        .send_wait(oversized_runtime_mutation(10, 101))
        .await
        .expect("the oversized essential completion must be admitted alone");
    assert_eq!(inbox.completion_counts().0, 1);

    let pending = {
        let inbox = inbox.clone();
        tokio::spawn(async move { inbox.send_wait(oversized_runtime_mutation(11, 102)).await })
    };
    tokio::time::timeout(
        Duration::from_secs(1),
        inbox.admission.async_waiter().notified(),
    )
    .await
    .expect("a second oversized completion must wait for the exclusive lane");

    match next_deferred(&mut receiver).await {
        ServerCommand::RuntimeMutationFinished(finished) => {
            assert_eq!((finished.client_id, finished.request_id), (10, 101));
            assert!(finished.outcome.result.is_err());
            assert!(finished.outcome.completion_on_error.is_some());
        }
        _ => panic!("unexpected first oversized mutation completion"),
    }
    pending
        .await
        .expect("second oversized completion sender joins")
        .expect("second oversized completion is admitted after release");
    match next_deferred(&mut receiver).await {
        ServerCommand::RuntimeMutationFinished(finished) => {
            assert_eq!((finished.client_id, finished.request_id), (11, 102));
            assert!(finished.outcome.result.is_err());
            assert!(finished.outcome.completion_on_error.is_some());
        }
        _ => panic!("unexpected second oversized mutation completion"),
    }
    assert_eq!(inbox.completion_counts(), (0, 0));
}
