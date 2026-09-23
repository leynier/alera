use super::*;
use alera_core::runtime::{RelocationSetupReceipt, SshTarget, WorktreeSetupReport};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, Notify};

#[derive(Clone)]
struct Owner {
    started: Arc<Notify>,
    release: Arc<Notify>,
    response: Value,
}
impl crate::ssh_remote::RemoteHostExecutor for Owner {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(&self, _: &SshTarget, _: bool, script: &str) -> anyhow::Result<String> {
        let mut response = self.response.clone();
        if script.contains("--action run") {
            self.started.notify_one();
            self.release.notified().await;
        } else {
            assert!(script.contains("--action cancel"));
            response["action"] = json!("cancel");
            response["setup"]["report"] = Value::Null;
            response["result"] = json!({"cancellationRequested":true,"processesClosed":false});
        }
        Ok(response.to_string())
    }
}

#[tokio::test]
async fn ssh_setup_cancellation_reaches_owner_before_running_setup_finishes() {
    let (root, store, pending, prepared, completed) =
        crate::remote_workspace_relocation::tests::fixture().await;
    store
        .record_remote_workspace_relocation_preparation(
            &pending.id,
            &serde_json::from_value(prepared["relocation"].clone()).unwrap(),
        )
        .await
        .unwrap();
    let (control_tx, mut control_rx) = mpsc::unbounded_channel();
    let (terminal_tx, _) = mpsc::channel(1);
    let client = crate::terminal_host::server::actor_test_harness::local_client(
        crate::terminal_host::client::ClientHandle::new(control_tx, terminal_tx),
    );
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &root,
        HashMap::from([(1, client)]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = store;
    let (inbox, mut commands) = mpsc::unbounded_channel();
    actor.inbox = inbox;
    let attempt = uuid::Uuid::new_v4().to_string();
    let setup = RelocationSetupReceipt {
        relocation_id: pending.id.clone(),
        config: Default::default(),
        attempt_id: Some(attempt.clone()),
        report: Some(WorktreeSetupReport::empty()),
    };
    let remote = Owner {
        started: Arc::new(Notify::new()),
        release: Arc::new(Notify::new()),
        response: json!({"version":1,"workspace":completed["workspace"],"relocationId":pending.id,"action":"run","setup":setup,"result":{"steps":[]}}),
    };
    let request = |action, attempt_id| SetupRequest {
        workspace_id: pending.source.id.clone(),
        relocation_id: pending.id.clone(),
        attempt_id,
        action,
    };
    actor.start_remote_setup_control(1, 10, request(OwnerSetupAction::Run, None), remote.clone());
    tokio::time::timeout(std::time::Duration::from_secs(2), remote.started.notified())
        .await
        .unwrap();
    actor.start_remote_setup_control(
        1,
        11,
        request(OwnerSetupAction::Cancel, Some(attempt)),
        remote.clone(),
    );
    let cancelled = tokio::time::timeout(std::time::Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        cancelled,
        ServerCommand::RemoteSetupFinished { request_id: 11, .. }
    ));
    actor.handle(cancelled).await;
    assert_eq!(actor.managed_workspace_jobs, 1);
    let response = control_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 11);
    assert_eq!(response["payload"]["processesClosed"], false);
    remote.release.notify_one();
    let finished = tokio::time::timeout(std::time::Duration::from_secs(2), commands.recv())
        .await
        .unwrap()
        .unwrap();
    actor.handle(finished).await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    let response = control_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 10);
    assert_eq!(response["payload"], json!({"steps":[]}));
}
