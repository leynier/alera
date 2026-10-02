use std::time::Duration;

use super::super::super::server_command_inbox::ServerInboxSendError;
use super::super::TerminalPulseSchedule;
use super::*;
use crate::terminal_host::server::ServerInbox;

fn fill_control_lane(inbox: &ServerInbox) {
    let mut id = 0;
    while inbox.send(ServerCommand::ClientDisconnected { id }).is_ok() {
        id += 1;
    }
    assert_eq!(
        inbox.send(ServerCommand::ClientDisconnected { id }),
        Err(ServerInboxSendError::Full)
    );
}

fn fill_completion_lane(inbox: &ServerInbox) {
    let mut id = 0;
    while inbox
        .send(ServerCommand::ResourceSampleReady {
            snapshot: serde_json::json!({ "id": id }),
        })
        .is_ok()
    {
        id += 1;
    }
    assert_eq!(
        inbox.send(ServerCommand::ResourceSampleReady {
            snapshot: serde_json::json!({ "id": id }),
        }),
        Err(ServerInboxSendError::Full)
    );
}

#[tokio::test]
async fn delayed_pulse_waits_for_inbox_capacity_instead_of_being_lost() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_lane(&inbox);
    fill_completion_lane(&inbox);

    let task = {
        let inbox = inbox.clone();
        tokio::spawn(async move {
            spawn_terminal_pulse_due(
                inbox,
                TerminalPulseSchedule {
                    session_id: "session-1".to_string(),
                    session_instance_id: 7,
                    generation: 11,
                    delay: Duration::from_millis(1),
                },
            );
        })
    };
    task.await.unwrap();
    tokio::task::yield_now().await;

    // Both admission lanes are full, so the delayed send must still be
    // waiting instead of silently dropping the pulse.
    let first = tokio::time::timeout(Duration::from_millis(50), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    let second = receiver.recv().await.unwrap();
    assert!(!matches!(first, ServerCommand::TerminalPulseDue { .. }));
    assert!(!matches!(second, ServerCommand::TerminalPulseDue { .. }));

    let due = tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if let ServerCommand::TerminalPulseDue {
                session_id,
                session_instance_id,
                generation,
            } = receiver.recv().await.unwrap()
            {
                break (session_id, session_instance_id, generation);
            }
        }
    })
    .await
    .expect("the delayed pulse remains queued until admission is available");
    assert_eq!(due, ("session-1".to_string(), 7, 11));
}
