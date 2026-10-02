use std::collections::HashMap;

use serde_json::Value;

use super::super::actor_test_harness::test_actor;
use crate::terminal_host::control_file;
use crate::terminal_host::protocol::TerminalHostConfig;

#[tokio::test]
async fn repeated_history_retries_schedule_one_notification_per_session() {
    use super::super::{ServerCommand, ServerInbox, CHECKPOINT_DELAY};
    use crate::terminal_host::session::Session;
    use std::time::Duration;
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([(
            "session".to_string(),
            Session::driver_test_stub("session", 80, 24),
        )]),
    )
    .await;
    let (inbox, mut receiver) = ServerInbox::channel();
    actor.inbox = inbox;
    for generation in 0..100 {
        actor.spawn_durable_output_batch_timer("session".to_string(), generation);
        actor.spawn_checkpoint_timer("session".to_string(), generation);
    }
    tokio::task::yield_now().await;
    tokio::time::sleep(CHECKPOINT_DELAY + Duration::from_millis(100)).await;
    let mut durable = 0;
    let mut checkpoint = 0;
    while let Ok(command) = receiver.try_recv() {
        match command {
            ServerCommand::DurableOutputBatchTick { .. } => durable += 1,
            ServerCommand::CheckpointTick { .. } => checkpoint += 1,
            _ => panic!("unexpected retry notification"),
        }
    }
    assert_eq!((durable, checkpoint), (1, 1));
}

#[tokio::test]
async fn output_resync_and_shutdown_timers_survive_control_saturation() {
    use super::super::server_command_inbox::SERVER_COMMAND_CONTROL_CAPACITY;
    use super::super::{ServerCommand, ServerInbox};
    use std::time::Duration;

    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let (inbox, mut receiver) = ServerInbox::channel();
    actor.inbox = inbox.clone();
    actor.config.empty_shutdown_delay_seconds = 0;
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .unwrap();
    }
    actor.spawn_output_batch_timer("session".to_string(), 42);
    actor.spawn_output_resync_timer("session".to_string(), 7);
    actor.schedule_shutdown_if_idle();
    tokio::task::yield_now().await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    for _ in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        assert!(matches!(
            receiver.try_recv().unwrap(),
            ServerCommand::ClientDisconnected { .. }
        ));
    }
    let received = tokio::time::timeout(Duration::from_secs(2), async {
        let mut output = false;
        let mut resync = false;
        let mut shutdown = false;
        for _ in 0..3 {
            match receiver.recv().await.unwrap() {
                ServerCommand::OutputBatchTick { generation: 42, .. } => output = true,
                ServerCommand::OutputResyncTick { client_id: 7, .. } => resync = true,
                ServerCommand::ShutdownTick { .. } => shutdown = true,
                _ => panic!("unexpected timer command"),
            }
        }
        (output, resync, shutdown)
    })
    .await
    .expect("all armed timers must resume after capacity is available");
    assert_eq!(received, (true, true, true));
}

#[tokio::test]
async fn promotion_keeps_actor_state_and_cannot_be_downgraded() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    control_file::write_control_file(&actor.control_file_path, 45678, "token", false).unwrap();
    actor.managed_workspace_jobs = 2;
    actor.shutdown_gen = 7;

    let response = actor.promote_persistent().unwrap();

    assert_eq!(response["persistent"], true);
    assert!(actor.config.persistent);
    assert_eq!(actor.managed_workspace_jobs, 2);
    assert!(actor.shutdown_gen > 7);
    let control: Value =
        serde_json::from_str(&std::fs::read_to_string(&actor.control_file_path).unwrap()).unwrap();
    assert_eq!(control["persistent"], true);

    actor.apply_config(TerminalHostConfig::default()).await;
    assert!(actor.config.persistent);
    assert_eq!(actor.managed_workspace_jobs, 2);
}
