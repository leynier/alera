use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};
use crate::runtime::{WorkspaceKind, WorkspaceTabRecord};

async fn action(store: &RuntimeStore) -> TerminalLifecycleOperation {
    action_on_host(store, "local").await
}

async fn action_on_host(store: &RuntimeStore, host: &str) -> TerminalLifecycleOperation {
    let workspace = workspace("terminal-task", host, "/repo", WorkspaceKind::Main);
    store.insert_workspace(workspace.clone()).await.unwrap();
    let now = chrono::Utc::now();
    store
        .insert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: workspace.id.clone(),
            kind: "terminal".into(),
            title: "Terminal".into(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({"terminalSessionId":"session"}),
        })
        .await
        .unwrap();
    TerminalLifecycleOperation {
        id: "operation".into(),
        workspace,
        tab_id: "tab".into(),
        session_id: "session".into(),
        session_generation: 7,
        initiator_epoch: None,
        action: TerminalLifecycleAction::Restart,
        closure_verified: false,
    }
}

#[tokio::test]
async fn never_started_close_fences_delayed_launch_and_survives_restart() {
    let (directory, store, _) = fixture().await;
    let mut operation = action(&store).await;
    operation.action = TerminalLifecycleAction::Close;
    store
        .begin_never_started_terminal_close(&operation)
        .await
        .unwrap();
    assert!(store
        .record_workspace_tab_terminal_launch(&operation.workspace.id, "tab", "session")
        .await
        .is_err());
    store
        .complete_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(
        reopened
            .begin_never_started_terminal_close(&operation)
            .await
            .unwrap()
            .closure_verified
    );
    assert!(reopened
        .record_workspace_tab_terminal_launch(&operation.workspace.id, "tab", "session")
        .await
        .is_err());
    reopened
        .record_workspace_tab_terminal_launch(
            &operation.workspace.id,
            "another-tab",
            "another-session",
        )
        .await
        .unwrap();
}

#[tokio::test]
async fn never_started_close_rejects_attempted_unknown_and_restart_operations() {
    for attempted in [false, true] {
        let (_directory, store, _) = fixture().await;
        let mut operation = action(&store).await;
        assert!(store
            .begin_never_started_terminal_close(&operation)
            .await
            .is_err());
        operation.action = TerminalLifecycleAction::Close;
        if attempted {
            store
                .record_workspace_tab_terminal_launch(&operation.workspace.id, "tab", "session")
                .await
                .unwrap();
            store
                .begin_terminal_lifecycle_operation(&operation)
                .await
                .unwrap();
        } else {
            sqlx::query("DELETE FROM terminalLaunchAttempts")
                .execute(store.pool())
                .await
                .unwrap();
        }
        assert!(store
            .begin_never_started_terminal_close(&operation)
            .await
            .is_err());
        assert!(store.find_workspace_tab("tab").await.unwrap().is_some());
    }
}

#[tokio::test]
async fn pending_closure_survives_restart_and_preserves_task_and_tab() {
    let (directory, store, _) = fixture().await;
    let operation = action(&store).await;
    store
        .begin_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .terminal_lifecycle_operation("operation")
            .await
            .unwrap(),
        Some(operation.clone())
    );
    assert!(reopened
        .require_workspace_process_closure(&operation.workspace.id)
        .await
        .is_err());
    assert!(reopened.remove_workspace_tab("tab").await.is_err());
    assert!(reopened
        .retire_verified_shared_workspace(&operation.workspace)
        .await
        .is_err());
    assert!(reopened
        .begin_workspace_process_job(
            &operation.workspace,
            "another-process",
            std::env::consts::OS,
            None
        )
        .await
        .is_err());
    let completed = reopened
        .complete_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    assert!(completed.closure_verified);
    assert_eq!(
        reopened
            .begin_terminal_lifecycle_operation(&operation)
            .await
            .unwrap(),
        completed
    );
    reopened
        .require_workspace_process_closure(&operation.workspace.id)
        .await
        .unwrap();
    reopened.remove_workspace_tab("tab").await.unwrap();
}

#[tokio::test]
async fn close_completion_removes_its_tab_atomically_and_rolls_back_on_failure() {
    let (_directory, store, _) = fixture().await;
    let mut operation = action(&store).await;
    operation.action = TerminalLifecycleAction::Close;
    store
        .begin_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    sqlx::query("CREATE TRIGGER rejectTestTabDeletion BEFORE DELETE ON workspaceTabs BEGIN SELECT RAISE(ABORT, 'injected deletion failure'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .complete_terminal_lifecycle_operation(&operation)
        .await
        .is_err());
    assert_eq!(
        store
            .terminal_lifecycle_operation(&operation.id)
            .await
            .unwrap(),
        Some(operation.clone())
    );
    assert!(store
        .find_workspace_tab(&operation.tab_id)
        .await
        .unwrap()
        .is_some());
    assert!(store
        .require_terminal_lifecycle_closed(&operation.workspace.id)
        .await
        .is_err());
    sqlx::query("DROP TRIGGER rejectTestTabDeletion")
        .execute(store.pool())
        .await
        .unwrap();
    let completed = store
        .complete_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    assert!(completed.closure_verified);
    assert!(store
        .find_workspace_tab(&operation.tab_id)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .begin_terminal_lifecycle_operation(&operation)
            .await
            .unwrap(),
        completed
    );
}

#[tokio::test]
async fn operation_identity_cannot_retarget_a_replacement_session() {
    let (_directory, store, _) = fixture().await;
    let operation = action(&store).await;
    let mut foreign = operation.clone();
    foreign.session_id = "another-session".into();
    assert!(store
        .begin_terminal_lifecycle_operation(&foreign)
        .await
        .is_err());
    assert!(store
        .terminal_lifecycle_operation("operation")
        .await
        .unwrap()
        .is_none());
    store
        .begin_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    let mut replacement = operation.clone();
    replacement.session_generation += 1;
    assert!(store
        .begin_terminal_lifecycle_operation(&replacement)
        .await
        .is_err());
    assert!(store
        .complete_terminal_lifecycle_operation(&replacement)
        .await
        .is_err());
    replacement.id = "other-operation".into();
    assert!(store
        .begin_terminal_lifecycle_operation(&replacement)
        .await
        .is_err());
    assert_eq!(
        store
            .terminal_lifecycle_operation("operation")
            .await
            .unwrap(),
        Some(operation)
    );
}

#[tokio::test]
async fn remote_intent_survives_reopen_and_requires_scoped_owner_evidence() {
    let (directory, store, _) = fixture().await;
    let operation = action_on_host(&store, "ssh-owner").await;
    assert!(store
        .begin_terminal_lifecycle_operation(&operation)
        .await
        .is_err());
    store
        .begin_remote_terminal_lifecycle_operation(&operation)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .pending_terminal_lifecycle_for_session("session")
            .await
            .unwrap(),
        Some(operation.clone())
    );
    assert!(reopened
        .complete_terminal_lifecycle_operation(&operation)
        .await
        .is_err());
    assert!(reopened.remove_workspace_tab("tab").await.is_err());
    let mut owner = operation.clone();
    owner.workspace.host_id = LOCAL_HOST_ID.into();
    owner.session_generation = 999;
    owner.closure_verified = true;
    let mut foreign = owner.clone();
    foreign.workspace.instance_id = "another-instance".into();
    assert!(reopened
        .complete_remote_terminal_lifecycle_operation(&operation, &foreign)
        .await
        .is_err());
    foreign = owner.clone();
    foreign.action = TerminalLifecycleAction::Close;
    assert!(reopened
        .complete_remote_terminal_lifecycle_operation(&operation, &foreign)
        .await
        .is_err());
    assert_eq!(
        reopened
            .pending_terminal_lifecycle_for_session("session")
            .await
            .unwrap(),
        Some(operation.clone())
    );
    let completed = reopened
        .complete_remote_terminal_lifecycle_operation(&operation, &owner)
        .await
        .unwrap();
    assert!(reopened
        .pending_terminal_lifecycle_for_session("session")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        reopened
            .terminal_lifecycle_for_generation(
                "session",
                operation.session_generation,
                None,
                operation.action
            )
            .await
            .unwrap(),
        Some(completed)
    );
    assert!(reopened
        .terminal_lifecycle_for_generation(
            "session",
            operation.session_generation + 1,
            None,
            operation.action
        )
        .await
        .unwrap()
        .is_none());
    assert!(reopened.find_workspace_tab("tab").await.unwrap().is_some());
}
