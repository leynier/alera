use super::*;

#[tokio::test]
async fn home_recovery_distinguishes_pending_owner_completion_and_home_commit() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    let initial = store
        .list_remote_workspace_relocation_recovery(&source, 20)
        .await
        .unwrap();
    assert_eq!(initial.len(), 1);
    assert_eq!(initial[0].intent.id, pending.id);
    assert!(!initial[0].home_committed);
    assert!(initial[0].owner_receipt.is_none());
    let receipt = owner_receipt(&pending);
    store
        .record_remote_workspace_relocation_receipt(&pending.id, &receipt)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let received = reopened
        .list_remote_workspace_relocation_recovery(&source, 20)
        .await
        .unwrap();
    assert!(!received[0].home_committed);
    assert_eq!(received[0].owner_receipt.as_ref().unwrap().id, pending.id);
    reopened
        .commit_remote_workspace_relocation(&pending.id)
        .await
        .unwrap();
    assert!(
        reopened
            .list_remote_workspace_relocation_recovery(&source, 20)
            .await
            .unwrap()[0]
            .home_committed
    );
    for field in ["instance", "project", "host"] {
        let mut different = source.clone();
        match field {
            "instance" => different.instance_id = "replacement".into(),
            "project" => different.project_id = "different".into(),
            _ => different.host_id = "another-host".into(),
        }
        assert!(reopened
            .list_remote_workspace_relocation_recovery(&different, 20)
            .await
            .unwrap()
            .is_empty());
    }
}

#[tokio::test]
async fn remote_setup_configuration_survives_reopen_and_rejects_changed_retry() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let id = uuid::Uuid::new_v4().to_string();
    let mut config = crate::runtime::ProjectConfig::default();
    config.new_workspace.prompt_append = "original configuration".into();
    store
        .begin_remote_workspace_relocation_with_config(
            &id,
            &source,
            intent(&source),
            None,
            Some(config.clone()),
        )
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    assert_eq!(
        reopened
            .find_remote_workspace_relocation_intent(&id)
            .await
            .unwrap()
            .unwrap()
            .setup_config,
        Some(config.clone())
    );
    reopened
        .begin_remote_workspace_relocation_with_config(
            &id,
            &source,
            intent(&source),
            None,
            Some(config.clone()),
        )
        .await
        .unwrap();
    config.new_workspace.prompt_append = "changed configuration".into();
    assert!(reopened
        .begin_remote_workspace_relocation_with_config(
            &id,
            &source,
            intent(&source),
            None,
            Some(config),
        )
        .await
        .is_err());
}
