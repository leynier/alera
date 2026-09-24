use super::*;
use alera_core::runtime::SshTarget;
use serde_json::json;
use std::sync::Arc;
use tokio::sync::{mpsc, Notify};

struct WaitingOwner {
    entered: Arc<Notify>,
    release: Arc<Notify>,
}
impl crate::ssh_remote::RemoteHostExecutor for WaitingOwner {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        self.entered.notify_one();
        self.release.notified().await;
        None
    }
    async fn run(&self, _: &SshTarget, _: bool, _: &str) -> anyhow::Result<String> {
        panic!("An unreachable owner must not receive commands");
    }
}

#[tokio::test]
async fn recovery_wait_does_not_block_requests_and_disconnected_clients_get_no_response() {
    for disconnect in [false, true] {
        let (_root, mut actor) =
            crate::terminal_host::server::checkout_buffer_guards_tests::fixture().await;
        let (control_tx, mut control_rx) = mpsc::unbounded_channel();
        let (terminal_tx, _) = mpsc::channel(1);
        actor.clients.get_mut(&1).unwrap().handle =
            crate::terminal_host::client::ClientHandle::new(control_tx, terminal_tx);
        let (inbox, mut commands) = mpsc::unbounded_channel();
        actor.inbox = inbox;
        let mut workspace = actor
            .runtime_store
            .find_workspace("task")
            .await
            .unwrap()
            .unwrap();
        workspace.id = "remote".into();
        workspace.instance_id = "remote-instance".into();
        workspace.host_id = "ssh".into();
        workspace.path = "/remote/project".into();
        actor
            .runtime_store
            .register_project_checkout(&workspace.project_id, "ssh", &workspace.path)
            .await
            .unwrap();
        actor
            .runtime_store
            .insert_workspace(workspace)
            .await
            .unwrap();
        let now = chrono::Utc::now();
        actor.runtime_store.upsert_ssh_target(serde_json::from_value(json!({"id":"ssh","alias":"Fixture","host":"test.invalid","port":22,"username":"fixture","authKind":"agent","createdAt":now,"updatedAt":now,"installDir":"/owner/sidecar","bootstrapStatus":"installed"})).unwrap()).await.unwrap();
        let entered = Arc::new(Notify::new());
        let release = Arc::new(Notify::new());
        actor.start_remote_relocation_recovery(
            1,
            10,
            "remote".into(),
            20,
            WaitingOwner {
                entered: entered.clone(),
                release: release.clone(),
            },
        );
        tokio::time::timeout(std::time::Duration::from_secs(2), entered.notified())
            .await
            .unwrap();
        assert_eq!(actor.managed_workspace_jobs, 1);
        tokio::time::timeout(
            std::time::Duration::from_secs(2),
            actor.handle_line(
                1,
                json!({"id":11,"type":"workspace.listAll","payload":{}}).to_string(),
            ),
        )
        .await
        .unwrap();
        let response = control_rx.recv().await.unwrap().as_json().unwrap();
        assert_eq!(response["id"], 11);
        assert_eq!(response["ok"], true);
        if disconnect {
            actor.clients.remove(&1);
        }
        release.notify_one();
        let completed = tokio::time::timeout(std::time::Duration::from_secs(2), commands.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            completed,
            ServerCommand::RemoteRecoveryFinished { .. }
        ));
        actor.handle(completed).await;
        assert_eq!(actor.managed_workspace_jobs, 0);
        if disconnect {
            assert!(control_rx.try_recv().is_err());
        } else {
            let response = control_rx.recv().await.unwrap().as_json().unwrap();
            assert_eq!(response["id"], 10);
            assert_eq!(response["ok"], true);
            assert!(response["payload"]["owner"].is_null());
            assert!(response["payload"]["ownerError"].is_string());
        }
    }
}

#[tokio::test]
async fn recovery_request_requires_identity_authentication_and_new_model_support() {
    let (_root, mut actor) =
        crate::terminal_host::server::checkout_buffer_guards_tests::fixture().await;
    let verb = "workspace.sshRelocationRecovery";
    assert!(crate::terminal_host::server::mobile_gateway_surface::mobile_request_allowed(verb));
    assert!(actor
        .try_start_deferred_request(99, 1, verb, &json!({"id":"task"}))
        .await
        .is_err());
    actor
        .clients
        .get_mut(&1)
        .unwrap()
        .shared_checkout_workspaces = false;
    assert!(actor
        .try_start_deferred_request(1, 1, verb, &json!({"id":"task"}))
        .await
        .is_err());
    actor
        .clients
        .get_mut(&1)
        .unwrap()
        .shared_checkout_workspaces = true;
    assert!(actor
        .try_start_deferred_request(1, 1, verb, &json!({}))
        .await
        .is_err());
    assert!(actor
        .try_start_deferred_request(1, 1, verb, &json!({"id":"task","limit":"all"}))
        .await
        .is_err());
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(recovery_limit(&json!({"limit":1000})).unwrap(), 100);
    assert_eq!(recovery_limit(&json!({"limit":0})).unwrap(), 1);
}
