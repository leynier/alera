use super::*;
use crate::terminal_host::{client::ClientHandle, session::Session};
use alera_core::runtime::{RuntimeStore, SshTarget, WorkspaceTabRecord};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};
use tokio::sync::mpsc;

struct Remote {
    store: RuntimeStore,
    fail: bool,
    calls: Arc<Mutex<Vec<String>>>,
}
impl RemoteHostExecutor for Remote {
    async fn probe_windows(&self, _: &SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(&self, _: &SshTarget, _: bool, script: &str) -> Result<String> {
        let mut operation = self
            .store
            .pending_terminal_lifecycle_for_session("session")
            .await?
            .unwrap();
        assert!(script.contains("project control-owner-terminal --request-base64"));
        self.calls.lock().unwrap().push(operation.id.clone());
        if self.fail {
            anyhow::bail!("injected uncertain SSH response");
        }
        operation.workspace.host_id = LOCAL_HOST_ID.into();
        operation.session_generation = 1000;
        operation.closure_verified = true;
        Ok(json!({"operation":operation,"processClosureVerified":true}).to_string())
    }
}

#[tokio::test]
async fn home_retry_preserves_pending_identity_and_detach_never_dispatches() {
    for verb in ["terminate", "terminal.restart", "tab.remove"] {
        let root = tempfile::tempdir().unwrap();
        let (control, _responses) = mpsc::unbounded_channel();
        let (terminal, _output) = mpsc::channel(16);
        let client =
            super::super::actor_test_harness::local_client(ClientHandle::new(control, terminal));
        let mut actor = super::super::actor_test_harness::test_actor(
            &root,
            HashMap::from([(1, client)]),
            HashMap::new(),
        )
        .await;
        let folder = root.path().join("project");
        std::fs::create_dir(&folder).unwrap();
        let project = crate::project_management::register_project(
            &actor.runtime_store,
            folder.to_str().unwrap(),
            None,
        )
        .await
        .unwrap();
        let mut workspace = actor
            .runtime_store
            .list_workspaces(&project.project.id)
            .await
            .unwrap()
            .remove(0);
        workspace.id = "remote".into();
        workspace.instance_id = "remote-instance".into();
        workspace.host_id = "ssh".into();
        actor
            .runtime_store
            .register_project_checkout(&workspace.project_id, "ssh", &workspace.path)
            .await
            .unwrap();
        actor
            .runtime_store
            .insert_workspace(workspace.clone())
            .await
            .unwrap();
        let target: SshTarget = serde_json::from_value(json!({"id":"ssh","alias":"Test","host":"test.invalid","port":22,"username":"test","authKind":"agent","createdAt":chrono::Utc::now(),"updatedAt":chrono::Utc::now(),"installDir":"/test/sidecar","bootstrapStatus":"installed"})).unwrap();
        actor.runtime_store.upsert_ssh_target(target).await.unwrap();
        let now = chrono::Utc::now();
        actor
            .runtime_store
            .insert_workspace_tab(WorkspaceTabRecord {
                id: "tab".into(),
                workspace_id: workspace.id.clone(),
                kind: "terminal".into(),
                title: "Terminal".into(),
                created_at: now,
                updated_at: now,
                payload: json!({"terminalSessionId":"session"}),
            })
            .await
            .unwrap();
        let mut session = Session::driver_test_stub("session", 80, 24);
        session.workspace_id = workspace.id.clone();
        session.tab_id = "tab".into();
        let generation = session.instance_id();
        actor.sessions.insert("session".into(), session);
        actor.sessions.insert(
            "neighbor".into(),
            Session::driver_test_stub("neighbor", 80, 24),
        );
        let (inbox, mut commands) = mpsc::unbounded_channel();
        actor.inbox = inbox;
        let calls = Arc::new(Mutex::new(Vec::new()));
        let remote = |fail| Remote {
            store: actor.runtime_store.clone(),
            fail,
            calls: calls.clone(),
        };
        let detach_remote = remote(false);
        let failed_remote = remote(true);
        let success_remote = remote(false);
        let repeat_remote = remote(false);
        // Missing launch deliberately fails the local restart before spawning; SSH process behavior has separate acceptance.
        let payload = json!({"operationId":uuid::Uuid::new_v4().to_string(),"id":"tab","sessionId":"session","tabId":"tab","workspaceId":workspace.id,"workingDirectory":workspace.path});
        assert!(!actor
            .start_remote_terminal_lifecycle_with_executor(1, 1, "detach", &payload, detach_remote)
            .await
            .unwrap());
        assert!(calls.lock().unwrap().is_empty());
        actor
            .start_remote_terminal_lifecycle_with_executor(1, 2, verb, &payload, failed_remote)
            .await
            .unwrap();
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            &command,
            ServerCommand::RemoteTerminalLifecycleFinished { result: Err(_), .. }
        ));
        actor.handle(command).await;
        let pending = actor
            .runtime_store
            .pending_terminal_lifecycle_for_session("session")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(pending.session_generation, generation);
        assert!(actor.sessions.contains_key("session"));
        assert!(actor
            .runtime_store
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .is_some());
        actor
            .start_remote_terminal_lifecycle_with_executor(1, 3, verb, &payload, success_remote)
            .await
            .unwrap();
        let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            &command,
            ServerCommand::RemoteTerminalLifecycleFinished { result: Ok(_), .. }
        ));
        actor.handle(command).await;
        assert_eq!(
            *calls.lock().unwrap(),
            vec![pending.id.clone(), pending.id.clone()]
        );
        assert!(actor
            .runtime_store
            .pending_terminal_lifecycle_for_session("session")
            .await
            .unwrap()
            .is_none());
        if verb == "terminal.restart" {
            assert!(actor.sessions.contains_key("session"));
            actor
                .start_remote_terminal_lifecycle_with_executor(1, 4, verb, &payload, repeat_remote)
                .await
                .unwrap();
            let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
                .await
                .unwrap()
                .unwrap();
            actor.handle(command).await;
            assert_eq!(calls.lock().unwrap().len(), 2);
            let mut replacement = Session::driver_test_stub("session", 100, 30);
            replacement.workspace_id = workspace.id.clone();
            replacement.tab_id = "tab".into();
            let replacement_generation = replacement.instance_id();
            actor.sessions.insert("session".into(), replacement);
            let remote = Remote {
                store: actor.runtime_store.clone(),
                fail: false,
                calls: calls.clone(),
            };
            actor
                .start_remote_terminal_lifecycle_with_executor(1, 5, verb, &payload, remote)
                .await
                .unwrap();
            let command = tokio::time::timeout(std::time::Duration::from_secs(3), commands.recv())
                .await
                .unwrap()
                .unwrap();
            actor.handle(command).await;
            assert_eq!(
                actor.sessions["session"].instance_id(),
                replacement_generation
            );
            assert!(actor.sessions["session"].clients.contains(&1));
            assert_eq!(calls.lock().unwrap().len(), 2);
        } else {
            assert!(!actor.sessions.contains_key("session"));
            assert!(actor
                .runtime_store
                .find_workspace_tab("tab")
                .await
                .unwrap()
                .is_none());
        }
        assert!(actor.sessions.contains_key("neighbor"));
        assert_eq!(actor.managed_workspace_jobs, 0);
    }
}
