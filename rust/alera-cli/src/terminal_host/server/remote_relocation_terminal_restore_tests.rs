use super::checkout_buffer_guards_tests::fixture;
use alera_core::runtime::{ProjectKind, WorkspaceRelocationIntent, WorkspaceTabRecord};
use serde_json::json;

#[tokio::test]
async fn pending_remote_relocation_preserves_terminal_tabs_and_initial_commands_on_restore() {
    let (root, mut actor) = fixture().await;
    let mut project = actor
        .runtime_store
        .find_project("project")
        .await
        .unwrap()
        .unwrap();
    project.kind = ProjectKind::GitRepository;
    actor.runtime_store.upsert_project(project).await.unwrap();
    let path = root.path().to_string_lossy().to_string();
    actor
        .runtime_store
        .register_project_checkout("project", "ssh", &path)
        .await
        .unwrap();
    for id in ["task", "sibling"] {
        let mut workspace = actor
            .runtime_store
            .find_workspace(id)
            .await
            .unwrap()
            .unwrap();
        workspace.host_id = "ssh".into();
        actor
            .runtime_store
            .upsert_workspace(workspace)
            .await
            .unwrap();
        let now = chrono::Utc::now();
        actor.runtime_store.upsert_workspace_tab(WorkspaceTabRecord {
            id: format!("{id}-terminal"), workspace_id: id.into(), kind: "terminal".into(), title: "Retained".into(),
            created_at: now, updated_at: now,
            payload: json!({"spawnOnCreate":true,"terminalSessionId":format!("{id}-session"),"initialCommand":"retained-command","initialCommandOnce":true}),
        }).await.unwrap();
    }
    let source = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    actor
        .runtime_store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            WorkspaceRelocationIntent {
                workspace_id: source.id.clone(),
                to_project_checkout: false,
                destination_path: Some(root.path().join("linked").to_string_lossy().into_owned()),
                branch: Some("topic".into()),
                replacement_branch: None,
                move_changes: false,
                shared_impact_confirmed: true,
            },
        )
        .await
        .unwrap();
    actor.reconcile_spawn_on_create_tabs().await;
    assert!(actor.sessions.is_empty());
    for id in ["task", "sibling"] {
        let tab = actor
            .runtime_store
            .find_workspace_tab(&format!("{id}-terminal"))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(tab.payload["initialCommand"], "retained-command");
        assert_eq!(tab.payload["initialCommandOnce"], true);
        let mut update = tab.clone();
        update.title = "Must not replace".into();
        assert!(actor.upsert_workspace_tab_and_spawn(update).await.is_err());
        assert_eq!(
            actor
                .runtime_store
                .find_workspace_tab(&tab.id)
                .await
                .unwrap()
                .unwrap(),
            tab
        );
    }
}
