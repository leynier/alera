use std::sync::Arc;
use std::time::Duration;

use super::super::server_command_inbox::ServerInboxSendError;
use super::*;
use crate::terminal_host::demand_driven_ticker::DemandDrivenTicker;
use crate::terminal_host::server::ServerInbox;
use tokio::sync::Notify;

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

#[tokio::test]
async fn control_pressure_keeps_sampling_until_a_tick_is_admitted() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_control_lane(&inbox);
    let attempts = Arc::new(Notify::new());
    let observed_attempts = Arc::clone(&attempts);
    let mut ticker = DemandDrivenTicker::new(Duration::from_secs(30));
    let tick_inbox = inbox.clone();
    ticker.start(Duration::from_millis(1), move || {
        observed_attempts.notify_one();
        send_resource_sample_tick(&tick_inbox)
    });

    attempts.notified().await;
    tokio::time::timeout(Duration::from_secs(1), attempts.notified())
        .await
        .expect("transient Full must leave the ticker retrying");

    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if matches!(
                receiver.recv().await,
                Some(ServerCommand::ResourceSampleTick)
            ) {
                break;
            }
        }
    })
    .await
    .expect("sampling must recover after control capacity returns");
}

#[test]
fn a_closed_inbox_stops_the_sampling_ticker() {
    let (inbox, receiver) = ServerInbox::channel();
    drop(receiver);

    assert!(!send_resource_sample_tick(&inbox));
}
