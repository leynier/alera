use std::time::Duration;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;
use crate::terminal_host::session::Session;

use super::checkout_buffer_guards_tests::fixture as checkout_fixture;
use super::runtime_mutations::{
    RuntimeMutationCompletion, RuntimeMutationEffect, RuntimeMutationFinished,
    RuntimeMutationOutcome,
};
use super::{ClientState, ServerCommand, ServerInbox};

#[tokio::test]
async fn oversized_ok_mutation_preserves_commit_cleanup_and_reports_an_error() {
    let (_root, mut actor) = checkout_fixture().await;
    let (client_handle, mut responses) = ClientHandle::test_channels();
    actor
        .clients
        .insert(1, ClientState::local(client_handle, true));

    let mut sibling_session = Session::driver_test_stub("sibling-session", 80, 24);
    sibling_session.workspace_id = "sibling".into();
    sibling_session.tab_id = "sibling-editor".into();
    actor
        .sessions
        .insert("sibling-session".into(), sibling_session);

    let now = Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "stopped-tab".into(),
            workspace_id: "task".into(),
            kind: "terminal".into(),
            title: "Stopped".into(),
            created_at: now,
            updated_at: now,
            payload: json!({}),
        })
        .await
        .unwrap();

    let acquired = actor
        .checkout_buffer_guard_request(
            1,
            "workspace.bufferGuard.acquire",
            &json!({"id":"task","operation":"removeShared"}),
        )
        .await
        .unwrap();
    let guard_id = acquired["guardId"].as_str().unwrap().to_owned();
    for client_id in [1, 2] {
        actor
            .acknowledge_buffer_guard(client_id, &json!({"guardId":guard_id,"blockers":[]}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(
            1,
            77,
            "task",
            "removeShared",
            &json!({"bufferGuardId":guard_id}),
        )
        .unwrap();
    actor.start_checkout_buffer_guard(&proof).await.unwrap();

    let oversized_response =
        "x".repeat(super::server_command_inbox::SERVER_COMMAND_COMPLETION_BYTES + 4096);
    let command = ServerCommand::RuntimeMutationFinished(RuntimeMutationFinished {
        client_id: 1,
        request_id: 77,
        outcome: RuntimeMutationOutcome {
            result: Ok(RuntimeMutationCompletion {
                response: json!({"result": oversized_response}),
                effect: RuntimeMutationEffect::TabRemoved {
                    tab_id: "sibling-editor".into(),
                    workspace_id: Some("sibling".into()),
                },
                closed_tab_ids: vec!["stopped-tab".into()],
                hand_on_relocate: None,
            }),
            completion_on_error: None,
            ended_pointer_tab_ids: vec!["ended-pointer".into()],
            closed_session_tab_ids: vec!["sibling-editor".into()],
            committed_tab_ids: vec!["committed-tab".into()],
            effect_on_error: None,
            stopped_workspace_tab_ids: vec!["stopped-tab".into()],
            pending_workspace_shutdown: Some(Box::new((
                "task".into(),
                WorkspaceShutdown::default(),
            ))),
        },
    });
    let (inbox, mut commands) = ServerInbox::channel();
    inbox.send_wait(command).await.unwrap();
    let bounded = commands.recv().await.unwrap();
    let ServerCommand::RuntimeMutationFinished(finished) = &bounded else {
        panic!("runtime mutation completion must stay on the completion lane");
    };
    assert!(finished.outcome.result.is_err());
    assert!(finished.outcome.completion_on_error.is_some());

    actor.handle(bounded).await;

    let release = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let frame = responses
                .recv()
                .await
                .expect("the guard release is delivered");
            let Some(value) = frame.as_json() else {
                continue;
            };
            if value["event"] == "checkoutBuffersReleased" {
                break value;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(release["payload"]["guardId"], guard_id);
    assert_eq!(release["payload"]["retired"], true);

    let response = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let frame = responses
                .recv()
                .await
                .expect("the client response is delivered");
            let Some(value) = frame.as_json() else {
                continue;
            };
            if value["id"] == 77 {
                break value;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(response["ok"], false);
    assert_eq!(response["id"], 77);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("Runtime mutation response exceeds"));
    assert!(!actor.sessions.contains_key("sibling-session"));
    assert!(actor
        .runtime_store
        .find_workspace_tab("stopped-tab")
        .await
        .unwrap()
        .is_none());
    assert!(actor
        .mutation_queue
        .pending_workspace_shutdowns
        .contains_key("task"));
    assert!(actor.checkout_buffer_guards.is_empty());
}
