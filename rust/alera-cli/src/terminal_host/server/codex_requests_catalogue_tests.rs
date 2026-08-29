use super::super::super::codex_runtime_cleanup::{
    apply_cleanup_activity, clear_cleanup_activity, codex_tab_uses_workspace,
    stale_codex_interrupt, CodexCleanupEntry, CodexCleanupPlan,
};
use super::*;
use std::collections::HashMap;

use alera_core::runtime::{Project, ProjectKind};

use crate::terminal_host::server::actor_test_harness::test_actor;

fn tab() -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: "tab".to_string(),
        workspace_id: "workspace".to_string(),
        kind: CODEX_TAB_KIND.to_string(),
        title: "Codex Chat".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    }
}

#[test]
fn skills_list_uses_the_resumed_thread_directory() {
    let mut tab = tab();
    set_active_cwd(&mut tab, "/workspace/resumed");

    let params = codex_skills_list_params(json!({"tabId": "tab"}), &tab, "/workspace/original");

    assert_eq!(params["cwds"], json!(["/workspace/resumed"]));
    assert_eq!(params["forceReload"], false);
    assert!(params.get("tabId").is_none());
}

#[test]
fn skills_list_falls_back_to_the_tab_workspace() {
    let params = codex_skills_list_params(json!({"tabId": "tab"}), &tab(), "/workspace/original");

    assert_eq!(params["cwds"], json!(["/workspace/original"]));
}

#[test]
fn review_branches_use_the_resumed_cwd_and_live_head() {
    let root = tempfile::tempdir().unwrap();
    let workspace_path = root.path().join("workspace");
    let resumed_path = root.path().join("resumed");
    init_review_repository(&workspace_path, "original", &["main"]);
    init_review_repository(&resumed_path, "feature/live", &["main"]);
    let package_path = resumed_path.join("packages/app");
    std::fs::create_dir_all(&package_path).unwrap();
    let mut tab = tab();
    set_active_cwd(&mut tab, &package_path.to_string_lossy());

    let payload = live_codex_review_branches(&tab, &workspace_path.to_string_lossy()).unwrap();

    assert_eq!(payload["currentBranch"], "feature/live");
    assert_eq!(payload["cwd"], package_path.to_string_lossy().as_ref());
    let branches = payload["branches"].as_array().unwrap();
    assert!(branches.contains(&json!("feature/live")));
    assert!(branches.contains(&json!("main")));
    assert!(!branches.contains(&json!("original")));
}

#[test]
fn resumed_tab_uses_the_workspace_that_owns_its_active_directory() {
    let mut tab = tab();
    set_active_cwd(&mut tab, "/other-workspace/packages/app");
    let mut workspace = workspace("other", "/other-workspace");

    assert!(codex_tab_uses_workspace(&tab, &workspace));

    workspace.id = "workspace".to_string();
    workspace.path = "/workspace".to_string();
    assert!(codex_tab_uses_workspace(&tab, &workspace));
}

#[test]
fn unrelated_workspace_does_not_claim_a_resumed_tab() {
    let mut tab = tab();
    set_active_cwd(&mut tab, "/other-workspace/packages/app");

    assert!(!codex_tab_uses_workspace(
        &tab,
        &workspace("unrelated", "/unrelated"),
    ));
}

#[test]
fn stale_saved_turn_errors_do_not_block_cleanup() {
    for message in [
        "thread not found: 019fe068-2bd6-75f0-9c10-6a51da413639",
        "turn not found: turn-1",
        "turn not active",
        "no rollout found for thread id 019fe068-2bd6-75f0-9c10-6a51da413639",
    ] {
        assert!(
            stale_codex_interrupt(&HostError::state(message)),
            "{message}"
        );
    }
    assert!(!stale_codex_interrupt(&HostError::state(
        "Codex app-server input failed: broken pipe",
    )));
}

#[tokio::test]
async fn failed_active_turn_cleanup_preserves_the_tab_binding() {
    let directory = tempfile::tempdir().unwrap();
    let store = alera_core::runtime::RuntimeStore::open(directory.path())
        .await
        .unwrap();
    let mut active_tab = tab();
    set_thread_and_snapshot(
        &mut active_tab,
        "thread-active",
        json!({"activeTurnId": "turn-active"}),
    );
    store.upsert_workspace_tab(active_tab).await.unwrap();
    let cleanup = CodexCleanupPlan {
        server: None,
        fallback_cwd: Some(
            directory
                .path()
                .join("missing-workspace")
                .to_string_lossy()
                .into_owned(),
        ),
        entries: vec![CodexCleanupEntry {
            tab_id: "tab".to_string(),
            thread_id: Some("thread-active".to_string()),
            turn_id: Some("turn-active".to_string()),
            delete_thread: true,
            replacement_cwd: None,
        }],
    };

    let outcome = super::super::super::runtime_mutations::run_runtime_mutation(
        None,
        store.clone(),
        super::super::super::runtime_mutations::RuntimeMutationRequest::RemoveTab {
            tab_id: "tab".to_string(),
        },
        Some(cleanup),
    )
    .await;

    assert!(outcome.result.is_err());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_some());
}

#[tokio::test]
async fn successful_cleanup_clears_durable_activity_for_a_surviving_tab() {
    let directory = tempfile::tempdir().unwrap();
    let store = alera_core::runtime::RuntimeStore::open(directory.path())
        .await
        .unwrap();
    let mut active_tab = tab();
    set_thread_and_snapshot(
        &mut active_tab,
        "thread-active",
        json!({
            "activeTurnId": "turn-active",
            "pendingRequests": [{"id": 7}],
        }),
    );
    store.upsert_workspace_tab(active_tab).await.unwrap();
    let entry = CodexCleanupEntry {
        tab_id: "tab".to_string(),
        thread_id: Some("thread-active".to_string()),
        turn_id: Some("turn-active".to_string()),
        delete_thread: false,
        replacement_cwd: None,
    };

    assert_eq!(
        clear_cleanup_activity(&store, &entry).await.unwrap(),
        Some("tab".to_string()),
    );
    let saved = store.find_workspace_tab("tab").await.unwrap().unwrap();
    assert!(snapshot(&saved)["activeTurnId"].is_null());
    assert_eq!(snapshot(&saved)["pendingRequests"], json!([]));
}

#[tokio::test]
async fn cleanup_does_not_clear_a_replaced_turn() {
    let directory = tempfile::tempdir().unwrap();
    let store = alera_core::runtime::RuntimeStore::open(directory.path())
        .await
        .unwrap();
    let mut active_tab = tab();
    set_thread_and_snapshot(
        &mut active_tab,
        "thread-active",
        json!({"activeTurnId": "turn-new"}),
    );
    store.upsert_workspace_tab(active_tab).await.unwrap();
    let stale_entry = CodexCleanupEntry {
        tab_id: "tab".to_string(),
        thread_id: Some("thread-active".to_string()),
        turn_id: Some("turn-old".to_string()),
        delete_thread: false,
        replacement_cwd: None,
    };

    assert_eq!(
        clear_cleanup_activity(&store, &stale_entry).await.unwrap(),
        None
    );
    let saved = store.find_workspace_tab("tab").await.unwrap().unwrap();
    assert_eq!(snapshot(&saved)["activeTurnId"], "turn-new");
}

#[tokio::test]
async fn cleanup_repairs_the_active_directory_of_an_idle_surviving_tab() {
    let directory = tempfile::tempdir().unwrap();
    let store = alera_core::runtime::RuntimeStore::open(directory.path())
        .await
        .unwrap();
    let mut idle_tab = tab();
    set_active_cwd(&mut idle_tab, "/workspace-being-removed/packages/app");
    store.upsert_workspace_tab(idle_tab).await.unwrap();
    let entry = CodexCleanupEntry {
        tab_id: "tab".to_string(),
        thread_id: None,
        turn_id: None,
        delete_thread: false,
        replacement_cwd: Some("/surviving-workspace".to_string()),
    };

    assert_eq!(
        clear_cleanup_activity(&store, &entry).await.unwrap(),
        Some("tab".to_string()),
    );
    let saved = store.find_workspace_tab("tab").await.unwrap().unwrap();
    assert_eq!(active_cwd(&saved).as_deref(), Some("/surviving-workspace"));
}

#[tokio::test]
async fn workspace_cleanup_plans_idle_cross_workspace_cwd_repair() {
    let directory = tempfile::tempdir().unwrap();
    let actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".to_string(),
            name: "Project".to_string(),
            repo_path: directory.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let surviving_path = directory.path().join("surviving");
    let removed_path = directory.path().join("removed");
    actor
        .runtime_store
        .upsert_workspace(workspace("workspace", &surviving_path.to_string_lossy()))
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace("removed", &removed_path.to_string_lossy()))
        .await
        .unwrap();
    let mut idle_tab = tab();
    set_active_cwd(
        &mut idle_tab,
        &removed_path.join("packages/app").to_string_lossy(),
    );
    actor
        .runtime_store
        .upsert_workspace_tab(idle_tab)
        .await
        .unwrap();

    let plan = actor
        .plan_codex_workspace_cleanup("removed")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(plan.entries.len(), 1);
    assert_eq!(
        plan.entries[0].replacement_cwd.as_deref(),
        Some(surviving_path.to_string_lossy().as_ref())
    );

    let pending = plan.prepare().await.unwrap().into_entries();
    assert_eq!(
        apply_cleanup_activity(&actor.runtime_store, &pending)
            .await
            .unwrap(),
        vec!["tab".to_string()]
    );
    let saved = actor
        .runtime_store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        active_cwd(&saved).as_deref(),
        Some(surviving_path.to_string_lossy().as_ref())
    );
}

#[test]
fn missing_resumed_directory_falls_back_to_the_tab_workspace() {
    let root = tempfile::tempdir().unwrap();
    let workspace_path = root.path().join("workspace");
    std::fs::create_dir_all(&workspace_path).unwrap();
    let workspace = workspace("workspace", &workspace_path.to_string_lossy());
    let mut tab = tab();
    set_active_cwd(
        &mut tab,
        &root.path().join("removed-workspace").to_string_lossy(),
    );

    let (cwd, changed) =
        resumable_codex_cwd(&tab, &workspace, std::slice::from_ref(&workspace)).unwrap();

    assert_eq!(
        cwd,
        dunce::canonicalize(workspace_path)
            .unwrap()
            .to_string_lossy()
    );
    assert!(changed);
}

#[test]
fn recovery_requires_the_thread_that_failed_to_resume() {
    let mut tab = tab();
    set_thread_and_snapshot(&mut tab, "thread-current", json!({}));

    assert!(ensure_recovery_matches(&json!({"expectedThreadId": "thread-current"}), &tab,).is_ok());
    assert!(ensure_recovery_matches(&json!({}), &tab).is_ok());
    assert!(
        ensure_recovery_matches(&json!({"expectedThreadId": "thread-replaced"}), &tab,).is_err()
    );

    clear_thread_identity(&mut tab);
    assert!(ensure_recovery_matches(&json!({}), &tab).is_err());
}

#[test]
fn recovery_rejects_a_thread_with_active_work() {
    let mut tab = tab();
    set_thread_and_snapshot(
        &mut tab,
        "thread-current",
        json!({"activeTurnId": "turn-live"}),
    );

    assert!(
        ensure_recovery_matches(&json!({"expectedThreadId": "thread-current"}), &tab,).is_err()
    );
}

#[test]
fn missing_rollout_activity_cleanup_allows_recovery() {
    let mut tab = tab();
    set_thread_and_snapshot(
        &mut tab,
        "thread-current",
        json!({
            "activeTurnId": "turn-stale",
            "pendingRequests": [{"id": 1}],
            "timelineCells": [{"id": "message", "kind": "assistantMessage"}],
        }),
    );
    let (thread_id, recovery) = resolve_missing_rollout(&mut tab, "thread-current", true);

    assert!(ensure_recovery_matches(&json!({"expectedThreadId": "thread-current"}), &tab,).is_ok());
    assert_eq!(thread_id.as_deref(), Some("thread-current"));
    assert_eq!(recovery.as_ref().unwrap()["kind"], "missingRollout");
    assert!(snapshot(&tab)["activeTurnId"].is_null());
    assert_eq!(snapshot(&tab)["pendingRequests"], json!([]));
    assert_eq!(snapshot(&tab)["timelineCells"][0]["id"], "message");
}

#[test]
fn legacy_missing_rollout_clients_start_a_new_context_without_losing_history() {
    let mut tab = tab();
    set_thread_and_snapshot(
        &mut tab,
        "thread-missing",
        json!({
            "activeTurnId": "turn-stale",
            "pendingRequests": [{"id": 1}],
            "timelineCells": [{"id": "message", "kind": "assistantMessage"}],
        }),
    );

    let (thread_id, recovery) = resolve_missing_rollout(&mut tab, "thread-missing", false);

    assert_eq!(thread_id, None);
    assert_eq!(recovery, None);
    assert_eq!(tab_thread_id(&tab), None);
    assert!(snapshot(&tab)["activeTurnId"].is_null());
    assert_eq!(snapshot(&tab)["pendingRequests"], json!([]));
    let cells = snapshot(&tab)["timelineCells"].as_array().unwrap().clone();
    assert_eq!(cells[0]["id"], "message");
    assert_eq!(cells[1]["kind"], "systemNotice");
    assert_eq!(cells[1]["title"], "Context Reset");
}

fn workspace(id: &str, path: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("instance-{id}"),
        host_id: "local".to_string(),
        project_id: "project".to_string(),
        name: id.to_string(),
        branch: None,
        path: path.to_string(),
        created_at: now,
        updated_at: now,
        kind: alera_core::runtime::WorkspaceKind::Main,
        status: alera_core::runtime::WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        child_count: 0,
    }
}

fn init_review_repository(path: &std::path::Path, current: &str, others: &[&str]) {
    let repository = git2::Repository::init(path).unwrap();
    let tree_id = repository.index().unwrap().write_tree().unwrap();
    let tree = repository.find_tree(tree_id).unwrap();
    let signature = git2::Signature::now("Alera", "alera@example.invalid").unwrap();
    let reference = format!("refs/heads/{current}");
    let commit_id = repository
        .commit(
            Some(&reference),
            &signature,
            &signature,
            "initial",
            &tree,
            &[],
        )
        .unwrap();
    let commit = repository.find_commit(commit_id).unwrap();
    for branch in others {
        repository.branch(branch, &commit, false).unwrap();
    }
    repository.set_head(&reference).unwrap();
}
