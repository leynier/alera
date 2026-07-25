use super::{NewOrchestrationTask, RuntimeStore};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

async fn ready_task(store: &RuntimeStore, id: &str) -> String {
    let task = store
        .create_orchestration_task(NewOrchestrationTask {
            spec: format!("work {id}"),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: None,
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    task.id
}

#[tokio::test]
async fn a_dispatch_records_the_profile_that_launched_it() {
    let (_dir, store) = store().await;
    let task_id = ready_task(&store, "a").await;
    let dispatch = store
        .create_orchestration_dispatch(&task_id, "term-1")
        .await
        .unwrap();
    assert_eq!(dispatch.agent_profile, None);

    store
        .set_orchestration_dispatch_profile(&dispatch.id, Some("Codex Sol"), Some("codex"))
        .await
        .unwrap();

    let stored = store
        .active_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stored.agent_profile.as_deref(), Some("Codex Sol"));
    assert_eq!(stored.agent_quota_group.as_deref(), Some("codex"));
}

#[tokio::test]
async fn attempted_profiles_are_ordered_and_deduplicated() {
    let (_dir, store) = store().await;
    let task_id = ready_task(&store, "a").await;
    assert!(store
        .orchestration_task_attempted_profiles(&task_id)
        .await
        .unwrap()
        .is_empty());

    for (index, profile) in ["Codex Sol", "Claude Big", "codex sol"].iter().enumerate() {
        let dispatch = store
            .create_orchestration_dispatch(&task_id, &format!("term-{index}"))
            .await
            .unwrap();
        store
            .set_orchestration_dispatch_profile(&dispatch.id, Some(profile), None)
            .await
            .unwrap();
        store
            .fail_orchestration_dispatch(&dispatch.id, "startup failed")
            .await
            .unwrap();
    }

    let attempted = store
        .orchestration_task_attempted_profiles(&task_id)
        .await
        .unwrap();
    // Oldest first, and a repeat under different casing is the same profile.
    assert_eq!(attempted, vec!["Codex Sol", "Claude Big"]);
}

#[tokio::test]
async fn dispatches_without_a_profile_are_not_counted_as_attempts() {
    let (_dir, store) = store().await;
    let task_id = ready_task(&store, "a").await;
    let dispatch = store
        .create_orchestration_dispatch(&task_id, "term-1")
        .await
        .unwrap();
    store
        .fail_orchestration_dispatch(&dispatch.id, "startup failed")
        .await
        .unwrap();

    assert!(store
        .orchestration_task_attempted_profiles(&task_id)
        .await
        .unwrap()
        .is_empty());
}
