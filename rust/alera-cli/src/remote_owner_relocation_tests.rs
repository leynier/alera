use super::*;

async fn fixture() -> (tempfile::TempDir, Value) {
    let root = tempfile::tempdir().unwrap();
    let folder = root.path().join("folder");
    std::fs::create_dir(&folder).unwrap();
    let store = RuntimeStore::open(&root.path().join("source"))
        .await
        .unwrap();
    let registered =
        crate::project_management::register_project(&store, folder.to_str().unwrap(), None)
            .await
            .unwrap();
    let workspace = registered.initial_workspace.unwrap();
    let value = json!({
        "workspace":workspace,
        "relocationId":uuid::Uuid::new_v4(),
        "intent":{
            "workspaceId":workspace.id,"toProjectCheckout":false,
            "destinationPath":root.path().join("linked"),"branch":"topic",
            "replacementBranch":null,"moveChanges":false,"sharedImpactConfirmed":true,
        },
    });
    (root, value)
}

fn args(root: &std::path::Path, value: &Value) -> RemoteOwnerRelocationArgs {
    RemoteOwnerRelocationArgs {
        state_dir: root.join("missing-owner"),
        prepare_only: false,
        enroll_never_started_base64: None,
        request_base64: base64::engine::general_purpose::STANDARD
            .encode(serde_json::to_vec(value).unwrap()),
    }
}

#[tokio::test]
async fn invalid_identity_or_scope_never_opens_owner_state() {
    let (root, value) = fixture().await;
    for (path, replacement) in [
        ("/intent/sharedImpactConfirmed", json!(false)),
        ("/workspace/hostId", json!("ssh")),
        ("/intent/workspaceId", json!("other")),
        ("/relocationId", json!("invalid")),
        ("/intent/destinationPath", Value::Null),
        ("/intent/replacementBranch", json!("replacement")),
        ("/intent/toProjectCheckout", json!(true)),
    ] {
        let mut invalid = value.clone();
        *invalid.pointer_mut(path).unwrap() = replacement;
        assert!(run(args(root.path(), &invalid)).await.is_err(), "{path}");
        assert!(!root.path().join("missing-owner").exists());
    }
}

#[tokio::test]
async fn unavailable_owner_does_not_start_a_replacement_or_create_state() {
    let (root, value) = fixture().await;
    let error = run(args(root.path(), &value)).await.unwrap_err();
    assert!(
        error.to_string().contains("owner runtime is unavailable"),
        "{error}"
    );
    assert!(!root.path().join("missing-owner").exists());
}

#[tokio::test]
async fn owner_location_includes_instance_project_host_and_storage_kind() {
    let (_root, value) = fixture().await;
    let workspace: Workspace = serde_json::from_value(value["workspace"].clone()).unwrap();
    assert!(same_location(&workspace, &workspace));
    for field in ["instanceId", "projectId", "hostId", "path"] {
        let mut changed = value["workspace"].clone();
        changed[field] = json!("other");
        let changed = serde_json::from_value(changed).unwrap();
        assert!(!same_location(&workspace, &changed), "{field}");
    }
    let mut changed = workspace.clone();
    changed.kind = WorkspaceKind::Linked;
    assert!(!same_location(&workspace, &changed));
}

#[tokio::test]
async fn invalid_enrollment_metadata_is_rejected_before_creating_owner_state() {
    let (root, value) = fixture().await;
    let mut request = args(root.path(), &value);
    request.enroll_never_started_base64 =
        Some(base64::engine::general_purpose::STANDARD.encode(b"{}"));
    assert!(run(request).await.is_err());
    assert!(!root.path().join("missing-owner").exists());
}
