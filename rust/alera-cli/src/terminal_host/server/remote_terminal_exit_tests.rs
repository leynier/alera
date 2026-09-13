use std::collections::HashMap;

use alera_core::runtime::WorkspaceTabRecord;
use serde_json::json;

use super::super::actor_test_harness::test_actor;
use crate::terminal_host::session::Session;

#[tokio::test]
async fn ssh_exit_preserves_terminal_identity_while_local_exit_retires_it() {
    for host in ["local", "ssh"] {
        let directory = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;
        let folder = directory.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        let project = crate::project_management::register_project(
            &actor.runtime_store,
            folder.to_str().unwrap(),
            None,
        )
        .await
        .unwrap()
        .project;
        let mut workspace = actor
            .runtime_store
            .list_workspaces(&project.id)
            .await
            .unwrap()
            .remove(0);
        workspace.host_id = host.into();
        actor
            .runtime_store
            .upsert_workspace(workspace.clone())
            .await
            .unwrap();
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
        session.workspace_id = workspace.id;
        session.tab_id = "tab".into();
        actor.sessions.insert("session".into(), session);
        actor.handle_session_exit("session".into(), 1).await;
        let tab = actor.runtime_store.find_workspace_tab("tab").await.unwrap();
        assert_eq!(tab.is_some(), host == "ssh");
        if let Some(tab) = tab {
            assert_eq!(tab.payload["terminalSessionId"], "session");
            assert!(!actor.sessions["session"].running());
        }
    }
}
