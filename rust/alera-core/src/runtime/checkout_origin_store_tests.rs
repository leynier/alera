use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};

#[tokio::test]
async fn verified_legacy_origin_requires_exact_task_and_binding_and_never_replaces_an_origin() {
    let (directory, store, _) = fixture().await;
    let task = store
        .insert_workspace(workspace("legacy", "ssh", "/linked", WorkspaceKind::Linked))
        .await
        .unwrap();
    let binding = store
        .find_workspace_checkout(&task.id)
        .await
        .unwrap()
        .unwrap();
    assert!(binding.repository_path.is_none());
    let mut replacement = task.clone();
    replacement.instance_id = "other".into();
    assert!(store
        .record_verified_linked_origin(&replacement, &binding, "/legacy.git")
        .await
        .is_err());
    replacement = task.clone();
    replacement.host_id = "other-host".into();
    assert!(store
        .record_verified_linked_origin(&replacement, &binding, "/legacy.git")
        .await
        .is_err());
    let mut wrong_binding = binding.clone();
    wrong_binding.id = "another-checkout".into();
    assert!(store
        .record_verified_linked_origin(&task, &wrong_binding, "/legacy.git")
        .await
        .is_err());
    wrong_binding = binding.clone();
    wrong_binding.path = "/another-path".into();
    assert!(store
        .record_verified_linked_origin(&task, &wrong_binding, "/legacy.git")
        .await
        .is_err());
    assert!(store
        .find_workspace_checkout(&task.id)
        .await
        .unwrap()
        .unwrap()
        .repository_path
        .is_none());
    store
        .record_verified_linked_origin(&task, &binding, "/legacy.git")
        .await
        .unwrap();
    store
        .record_verified_linked_origin(&task, &binding, "/legacy.git")
        .await
        .unwrap();
    assert!(store
        .record_verified_linked_origin(&task, &binding, "/another.git")
        .await
        .is_err());
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        store.find_workspace(&task.id).await.unwrap(),
        Some(task.clone())
    );
    assert_eq!(
        store
            .find_workspace_checkout(&task.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some("/legacy.git")
    );
    assert!(store
        .find_project_checkout(&task.project_id, "ssh")
        .await
        .unwrap()
        .is_none());
}
