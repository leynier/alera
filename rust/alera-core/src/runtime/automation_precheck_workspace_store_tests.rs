use super::*;
use crate::runtime::checkout_store_tests::workspace;
use crate::runtime::LOCAL_HOST_ID;
use crate::runtime::{AutomationPrecheckWorkspace, OwnerAutomationPrecheckOutcome, WorkspaceKind};

#[tokio::test]
async fn workspace_precheck_captures_exclusive_identity_and_retains_it_after_restart() {
    let (directory, store, mut definition, run) = prepared_for_host("ssh").await;
    let task = workspace("linked", "ssh", "/linked", WorkspaceKind::Linked);
    store
        .insert_workspace_with_repository(task.clone(), "/legacy.git")
        .await
        .unwrap();
    let neighbor = workspace("neighbor", "ssh", "/repo", WorkspaceKind::Main);
    store.insert_workspace(neighbor).await.unwrap();
    definition.target = AutomationTarget::FreshTab {
        workspace_id: task.id.clone(),
        agent_profile_id: "profile".into(),
    };
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let scope = AutomationPrecheckWorkspace {
        workspace_id: task.id.clone(),
        instance_id: task.instance_id,
        kind: WorkspaceKind::Linked,
        repository_path: Some("/legacy.git".into()),
    };
    assert_eq!(intent.workspace, Some(scope.clone()));
    assert_eq!(
        intent.remote_owner_request().unwrap().workspace,
        Some(scope)
    );
    assert!(store
        .require_workspace_process_closure("linked")
        .await
        .is_err());
    assert!(store
        .require_workspace_process_closure("neighbor")
        .await
        .is_ok());
    for statement in [
        "DELETE FROM workspaces WHERE id = 'linked'",
        "UPDATE workspaces SET instanceId = 'replacement' WHERE id = 'linked'",
        "UPDATE workspaces SET path = '/moved' WHERE id = 'linked'",
        "DELETE FROM workspaceCheckoutBindings WHERE workspaceId = 'linked'",
        "UPDATE workspaceCheckoutBindings SET checkoutId = 'another' WHERE workspaceId = 'linked'",
        "DELETE FROM repositoryCheckouts WHERE path = '/linked'",
        "UPDATE repositoryCheckouts SET repositoryPath = '/repo' WHERE path = '/linked'",
    ] {
        assert!(
            sqlx::query(statement).execute(store.pool()).await.is_err(),
            "{statement}"
        );
    }
    sqlx::query("UPDATE workspaces SET name = 'Renamed' WHERE id = 'linked'")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("DELETE FROM workspaces WHERE id = 'neighbor'")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .automation_precheck_processes(&run.id)
            .await
            .unwrap(),
        vec![intent.clone()]
    );
    assert!(sqlx::query("DELETE FROM workspaces WHERE id = 'linked'")
        .execute(reopened.pool())
        .await
        .is_err());
    reopened
        .record_automation_precheck_phase(&intent, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .unwrap();
    sqlx::query("DELETE FROM workspaces WHERE id = 'linked'")
        .execute(reopened.pool())
        .await
        .unwrap();
    assert_eq!(
        reopened
            .find_project_checkout("project", "ssh")
            .await
            .unwrap()
            .unwrap()
            .path,
        "/repo"
    );
}

#[tokio::test]
async fn owner_linked_precheck_rechecks_origin_and_preserves_pending_and_claimed_scope() {
    let (directory, store, project) = crate::runtime::checkout_store_tests::fixture().await;
    store
        .register_project_checkout(&project.id, LOCAL_HOST_ID, &project.repo_path)
        .await
        .unwrap();
    let task = workspace("linked", LOCAL_HOST_ID, "/linked", WorkspaceKind::Linked);
    store
        .insert_workspace_with_repository(task.clone(), "/legacy.git")
        .await
        .unwrap();
    let mut alias_project = project.clone();
    alias_project.id = "other-project".into();
    store.upsert_project(alias_project).await.unwrap();
    let mut alias = workspace(
        "physical-alias",
        LOCAL_HOST_ID,
        "/linked",
        WorkspaceKind::Linked,
    );
    alias.project_id = "other-project".into();
    store
        .insert_workspace_with_repository(alias, "/legacy.git")
        .await
        .unwrap();
    store
        .insert_workspace_with_repository(
            workspace("different-host", "ssh", "/linked", WorkspaceKind::Linked),
            "/legacy.git",
        )
        .await
        .unwrap();
    let request = crate::runtime::OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        origin_id: "home".into(),
        run_id: "run".into(),
        project_id: project.id.clone(),
        path: task.path.clone(),
        workspace: Some(AutomationPrecheckWorkspace {
            workspace_id: task.id.clone(),
            instance_id: task.instance_id.clone(),
            kind: WorkspaceKind::Linked,
            repository_path: Some("/legacy.git".into()),
        }),
        precheck: AutomationPrecheck {
            command: "fixture-only".into(),
            timeout_seconds: 10,
        },
    };
    for invalid in [
        AutomationPrecheckWorkspace {
            instance_id: "another-instance".into(),
            ..request.workspace.clone().unwrap()
        },
        AutomationPrecheckWorkspace {
            repository_path: Some("/repo".into()),
            ..request.workspace.clone().unwrap()
        },
        AutomationPrecheckWorkspace {
            repository_path: None,
            ..request.workspace.clone().unwrap()
        },
        AutomationPrecheckWorkspace {
            kind: WorkspaceKind::Main,
            ..request.workspace.clone().unwrap()
        },
    ] {
        let changed = crate::runtime::OwnerAutomationPrecheckRequest {
            workspace: Some(invalid),
            ..request.clone()
        };
        assert!(store
            .register_owner_automation_precheck(&changed)
            .await
            .is_err());
    }
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert!(store
        .require_workspace_process_closure("linked")
        .await
        .is_err());
    assert!(store
        .require_workspace_process_closure("neighbor")
        .await
        .is_ok());
    assert!(store
        .require_workspace_process_closure("physical-alias")
        .await
        .is_err());
    assert!(store
        .require_workspace_process_closure("different-host")
        .await
        .is_ok());
    for statement in [
        "DELETE FROM workspaces WHERE id = 'linked'",
        "UPDATE workspaces SET instanceId = 'other' WHERE id = 'linked'",
        "DELETE FROM workspaceCheckoutBindings WHERE workspaceId = 'linked'",
        "UPDATE repositoryCheckouts SET repositoryPath = '/repo' WHERE path = '/linked'",
    ] {
        assert!(
            sqlx::query(statement).execute(store.pool()).await.is_err(),
            "{statement}"
        );
    }
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let intent = store
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(intent.workspace, request.workspace);
    assert!(store
        .require_workspace_process_closure("physical-alias")
        .await
        .is_err());
    assert!(store
        .require_workspace_process_closure("linked")
        .await
        .is_err());
    store
        .cancel_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert!(sqlx::query("DELETE FROM workspaces WHERE id = 'linked'")
        .execute(store.pool())
        .await
        .is_err());
    store
        .record_automation_precheck_phase(&intent, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .unwrap();
    store
        .finish_owner_automation_precheck(&request, &OwnerAutomationPrecheckOutcome::Cancelled)
        .await
        .unwrap();
    assert!(store
        .require_workspace_process_closure("linked")
        .await
        .is_ok());
    assert!(store
        .require_workspace_process_closure("physical-alias")
        .await
        .is_ok());
    sqlx::query("DELETE FROM workspaces WHERE id = 'linked'")
        .execute(store.pool())
        .await
        .unwrap();
    assert_eq!(
        store
            .find_project_checkout(&project.id, LOCAL_HOST_ID)
            .await
            .unwrap()
            .unwrap()
            .path,
        "/repo"
    );
}

#[tokio::test]
async fn project_precheck_legacy_json_does_not_gain_workspace_fields() {
    let (_directory, store, definition, run) = prepared_for_host("ssh").await;
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let json = serde_json::to_value(&intent).unwrap();
    assert!(json.get("workspace").is_none());
    let restored: crate::runtime::AutomationPrecheckProcess = serde_json::from_value(json).unwrap();
    assert_eq!(restored, intent);
    let request = restored.remote_owner_request().unwrap();
    assert!(serde_json::to_value(request)
        .unwrap()
        .get("workspace")
        .is_none());
}
