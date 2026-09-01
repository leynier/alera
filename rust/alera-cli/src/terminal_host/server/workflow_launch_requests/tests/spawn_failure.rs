use super::*;
use crate::terminal_host::server::runtime_mutations::RuntimeMutationRequest;
use serde_json::Value;

async fn actor_with_client(
    fixture: &Fixture,
) -> (
    tempfile::TempDir,
    ServerActor,
    tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) {
    let dir = tempfile::tempdir().unwrap();
    let (client, responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(client))]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    (dir, actor, responses)
}

fn json_frames(
    responses: &mut tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) -> Vec<Value> {
    std::iter::from_fn(|| responses.try_recv().ok())
        .filter_map(|frame| frame.as_json())
        .collect()
}

#[tokio::test]
async fn workflow_launch_spawn_failure_broadcasts_the_retained_tab() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    let (_dir, mut actor, mut responses) = actor_with_client(&fixture).await;
    let (inbox, _commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.start_runtime_mutation_after_codex_cleanup(
        1,
        99,
        RuntimeMutationRequest::RemoveTab {
            tab_id: "unrelated".into(),
        },
        None,
    );

    actor
        .handle_workflow_launch_claimed(1, 1, record.clone(), token, locks, Ok(frozen))
        .await;

    assert!(json_frames(&mut responses).iter().any(|frame| {
        frame["event"] == "workspaceTabsChanged"
            && frame["payload"]["workspaceId"] == input.workspace_id
    }));
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&input.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&record.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::StartupFailed
    );
}

#[tokio::test]
async fn workflow_launch_failure_before_tab_insert_does_not_broadcast_tabs() {
    let fixture = Fixture::new("").await;
    let (_input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let mut frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    frozen.profile.agent_type = "unsupported-workflow-agent".into();
    let (_dir, mut actor, mut responses) = actor_with_client(&fixture).await;

    actor
        .handle_workflow_launch_claimed(1, 1, record.clone(), token, locks, Ok(frozen))
        .await;

    assert!(!json_frames(&mut responses)
        .iter()
        .any(|frame| frame["event"] == "workspaceTabsChanged"));
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_none());
}
