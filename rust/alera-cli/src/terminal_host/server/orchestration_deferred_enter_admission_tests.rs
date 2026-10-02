use std::collections::HashMap;
use std::sync::mpsc::TryRecvError;
use std::time::Duration;

use crate::terminal_host::server::ServerCommand;
use crate::terminal_host::session::{PtyEvent, PtyWriteCompletion, Session};

use super::actor_test_harness::test_actor;
use super::server_command_inbox::{
    ServerInbox, SERVER_COMMAND_CONTROL_CAPACITY, SERVER_COMMAND_WORK_CAPACITY,
};

#[tokio::test]
async fn scheduled_deferred_enter_survives_control_and_work_admission_closure() {
    let root = tempfile::tempdir().unwrap();
    let mut session = Session::driver_test_stub("session", 80, 24);
    let session_instance_id = session.instance_id();
    let input = session.attach_test_input();
    let mut actor = test_actor(
        &root,
        HashMap::new(),
        HashMap::from([("session".to_string(), session)]),
    )
    .await;
    actor
        .orchestration_delivery_in_flight
        .insert("session".into());

    let (inbox, mut receiver) = ServerInbox::channel();
    actor.inbox = inbox.clone();
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control admission should fill");
    }
    for _ in 0..SERVER_COMMAND_WORK_CAPACITY {
        let (handled, _completed) = std::sync::mpsc::sync_channel(1);
        inbox
            .send(ServerCommand::Pty {
                session_id: "admission-fill".into(),
                event: PtyEvent::Output(vec![0]),
                handled,
            })
            .expect("work admission should fill");
    }
    inbox.close();

    actor.schedule_orchestration_enter(
        "session".into(),
        session_instance_id,
        vec!["message-1".into()],
        true,
    );

    let deferred = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let command = receiver
                .recv()
                .await
                .expect("the deferred enter must remain deliverable");
            if matches!(command, ServerCommand::OrchestrationDeferredEnter { .. }) {
                break command;
            }
        }
    })
    .await
    .expect("a scheduled deferred enter must outlive admission closure");
    let ServerCommand::OrchestrationDeferredEnter {
        session_id,
        session_instance_id: actual_instance_id,
        message_ids,
        force_submit,
    } = deferred
    else {
        unreachable!();
    };
    assert_eq!(session_id, "session");
    assert_eq!(actual_instance_id, session_instance_id);
    assert_eq!(message_ids, ["message-1"]);
    assert!(force_submit);

    actor
        .handle(ServerCommand::OrchestrationDeferredEnter {
            session_id: session_id.clone(),
            session_instance_id: actual_instance_id,
            message_ids: message_ids.clone(),
            force_submit,
        })
        .await;
    let queued = input
        .recv_timeout(Duration::from_secs(1))
        .expect("the actor must queue the deferred enter to the terminal writer");
    assert!(!queued.bytes.is_empty());
    assert!(queued.deferred_bytes.is_none());
    assert!(actor.orchestration_delivery_in_flight.contains("session"));

    actor
        .handle_pty_event(
            session_id,
            PtyEvent::InputWritten {
                completion: PtyWriteCompletion::OrchestrationEnter {
                    session_instance_id: actual_instance_id,
                    message_ids,
                },
                error: None,
            },
        )
        .await;
    assert!(!actor.orchestration_delivery_in_flight.contains("session"));

    assert!(matches!(input.try_recv(), Err(TryRecvError::Empty)));
}
