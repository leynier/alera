use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use super::requests::{optional_string_key, require_string_key};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) async fn start_project_checkout_quick_open(
    store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let project_id = require_string_key(payload, "projectId")?;
    let host_id =
        crate::ssh_remote::normalized_host_id(optional_string_key(payload, "hostId").as_deref());
    let session = crate::project_file_catalog::list(
        store,
        &project_id,
        &host_id,
        &crate::ssh_remote::LiveSshRemoteHost,
    )
    .await
    .map_err(|error| HostError::state(error.to_string()))?;
    Ok(json!({"sessionId": session.id, "indexedFileCount": session.indexed_file_count}))
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::runtime::{Project, ProjectKind};
    use alera_core::workspace_files::{
        search_workspace_quick_open_session, stop_workspace_quick_open_session,
        WorkspaceQuickOpenSession,
    };

    #[tokio::test]
    async fn empty_project_search_uses_registered_checkout_and_rejects_foreign_host_paths() {
        let directory = tempfile::tempdir().unwrap();
        let folder = directory.path().join("files");
        std::fs::create_dir(&folder).unwrap();
        std::fs::write(folder.join("hello.txt"), "test").unwrap();
        let path = folder.to_string_lossy().to_string();
        let store = RuntimeStore::open(&directory.path().join("runtime"))
            .await
            .unwrap();
        store
            .upsert_project(Project {
                id: "project".into(),
                name: "Project".into(),
                repo_path: path.clone(),
                kind: ProjectKind::Folder,
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            })
            .await
            .unwrap();
        store
            .register_project_checkout("project", "local", &path)
            .await
            .unwrap();
        let result = start_project_checkout_quick_open(&store, &json!({"projectId": "project"}))
            .await
            .unwrap();
        let session = WorkspaceQuickOpenSession {
            id: result["sessionId"].as_str().unwrap().to_string(),
            indexed_file_count: result["indexedFileCount"].as_u64().unwrap() as u32,
        };
        let matches = search_workspace_quick_open_session(session.clone(), "hello".into(), 10);
        stop_workspace_quick_open_session(session);
        assert!(matches
            .unwrap()
            .iter()
            .any(|item| item.relative_path == "hello.txt"));
        assert!(store.list_all_workspaces().await.unwrap().is_empty());
        store
            .register_project_checkout("project", "ssh", &path)
            .await
            .unwrap();
        let error = start_project_checkout_quick_open(
            &store,
            &json!({"projectId": "project", "hostId": "ssh"}),
        )
        .await
        .unwrap_err();
        assert!(error.wire_message().contains("ssh target not found: ssh"));
    }
}
