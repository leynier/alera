use super::*;

#[tokio::test]
async fn pending_relocation_blocks_new_processes_on_its_checkout_and_preserves_launch_evidence() {
    let (root, store, mut project) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let neighbor = remote(&store, "neighbor", "ssh").await;
    let foreign = remote(&store, "foreign", "other-ssh").await;
    project.id = "other-project".into();
    store.upsert_project(project.clone()).await.unwrap();
    store
        .register_project_checkout(&project.id, "ssh", &source.path)
        .await
        .unwrap();
    let mut alias = workspace("alias", "ssh", &source.path, WorkspaceKind::Main);
    alias.project_id = project.id;
    store.insert_workspace(alias.clone()).await.unwrap();
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    for workspace in [&source, &neighbor, &alias] {
        assert_eq!(
            reopened
                .pending_workspace_checkout_relocation(&workspace.id)
                .await
                .unwrap()
                .as_deref(),
            Some(pending.id.as_str())
        );
        assert!(reopened
            .record_workspace_terminal_launch(&workspace.id)
            .await
            .is_err());
        assert_eq!(
            reopened
                .workspace_terminal_launch_attempted(&workspace.id, &workspace.instance_id)
                .await
                .unwrap(),
            Some(false)
        );
        assert!(reopened
            .begin_workspace_process_job(workspace, "operation", "linux", None)
            .await
            .is_err());
    }
    assert!(reopened
        .pending_workspace_checkout_relocation(&foreign.id)
        .await
        .unwrap()
        .is_none());
    reopened
        .record_workspace_terminal_launch(&foreign.id)
        .await
        .unwrap();
    reopened
        .record_remote_workspace_relocation_receipt(&pending.id, &owner_receipt(&pending))
        .await
        .unwrap();
    reopened
        .commit_remote_workspace_relocation(&pending.id)
        .await
        .unwrap();
    reopened
        .record_workspace_terminal_launch(&neighbor.id)
        .await
        .unwrap();
    reopened
        .begin_workspace_process_job(&neighbor, "operation", "linux", None)
        .await
        .unwrap();
}
