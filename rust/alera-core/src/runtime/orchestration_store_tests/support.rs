use super::*;

pub(super) async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

pub(super) fn message(
    from: &str,
    to: &str,
    message_type: OrchestrationMessageType,
) -> NewOrchestrationMessage {
    NewOrchestrationMessage {
        from_handle: from.to_string(),
        to_handle: to.to_string(),
        subject: "subject".to_string(),
        body: "body".to_string(),
        message_type,
        priority: OrchestrationMessagePriority::Normal,
        thread_id: None,
        payload: None,
        run_id: None,
        workspace_id: Some("workspace_1".to_string()),
        task_id: None,
        dispatch_id: None,
        expires_at: None,
    }
}

pub(super) fn task(spec: &str, deps: Vec<String>) -> NewOrchestrationTask {
    NewOrchestrationTask {
        spec: spec.to_string(),
        task_title: None,
        display_name: None,
        deps,
        parent_id: None,
        created_by_terminal_handle: None,
        run_id: None,
        workspace_id: "workspace_1".to_string(),
        coordinator_handle: "coord".to_string(),
        result_schema: None,
    }
}
