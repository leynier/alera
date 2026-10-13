use super::requests::require_string_key;
use super::workspace_blocking::spawn_blocking_workspace;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::source_control as sc;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

type Key = (String, String, String);
struct Progress {
    line: Option<String>,
    finished: bool,
    touched: Instant,
}
type Entry = Arc<Mutex<Progress>>;
static OPERATIONS: OnceLock<Mutex<HashMap<Key, Entry>>> = OnceLock::new();

// Polling also works across the hub's request forwarding path. Each record is
// scoped to the already-authorized workspace/path and a unique operation id.
pub(super) async fn handle(
    workspace: &str,
    path: &str,
    verb: &str,
    payload: &Value,
) -> HostResult<Value> {
    let id = require_string_key(payload, "operationId")?;
    if id.is_empty() || id.len() > 128 {
        return Err(HostError::format("Invalid Git operation id"));
    }
    let key = (workspace.to_string(), path.to_string(), id);
    let operations = OPERATIONS.get_or_init(|| Mutex::new(HashMap::new()));
    let entry = {
        let mut records = operations
            .lock()
            .map_err(|_| HostError::format("Git progress lock failed"))?;
        records.retain(|_, value| {
            value
                .lock()
                .is_ok_and(|p| !p.finished || p.touched.elapsed() < Duration::from_secs(300))
        });
        if verb == "git.networkProgress" {
            let line = records
                .get(&key)
                .and_then(|entry| entry.lock().ok().and_then(|p| p.line.clone()));
            return Ok(json!({ "line": line }));
        }
        if records.contains_key(&key) {
            return Err(HostError::state("Git operation id was already used"));
        }
        if records.len() >= 128 {
            let oldest = records
                .iter()
                .filter_map(|(key, entry)| {
                    entry
                        .lock()
                        .ok()
                        .filter(|p| p.finished)
                        .map(|p| (key.clone(), p.touched))
                })
                .min_by_key(|(_, touched)| *touched);
            if let Some((oldest, _)) = oldest {
                records.remove(&oldest);
            } else {
                return Err(HostError::state("Too many Git operations are running"));
            }
        }
        let entry = Arc::new(Mutex::new(Progress {
            line: None,
            finished: false,
            touched: Instant::now(),
        }));
        records.insert(key, entry.clone());
        entry
    };
    let path = path.to_string();
    let push = verb == "git.pushWithProgress";
    spawn_blocking_workspace("Workspace Git progress", move || {
        let output = |line| {
            if let Ok(mut record) = entry.lock() {
                record.line = Some(line);
                record.touched = Instant::now();
            }
        };
        let result = if push {
            sc::git_push_with_progress(path, &output)
        } else {
            sc::git_pull_with_progress(path, &output)
        };
        if let Ok(mut record) = entry.lock() {
            record.finished = true;
            record.touched = Instant::now();
        }
        super::workspace_git_requests::encode(result)
    })
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn network_progress_is_scoped_and_does_not_replay_operation_ids() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("checkout");
        let remote = directory.path().join("remote.git");
        git2::Repository::init_bare(&remote).unwrap();
        let repo = git2::Repository::init(&path).unwrap();
        std::fs::write(path.join("file.txt"), "content\n").unwrap();
        let mut index = repo.index().unwrap();
        index.add_path(std::path::Path::new("file.txt")).unwrap();
        let tree_id = index.write_tree().unwrap();
        let tree = repo.find_tree(tree_id).unwrap();
        let signature = git2::Signature::now("Test", "test@example.org").unwrap();
        repo.commit(Some("HEAD"), &signature, &signature, "initial", &tree, &[])
            .unwrap();
        repo.remote("origin", remote.to_str().unwrap()).unwrap();
        let path = path.to_str().unwrap();
        let payload = json!({ "operationId": "one" });
        handle("workspace", path, "git.pushWithProgress", &payload)
            .await
            .unwrap();
        let progress = handle("workspace", path, "git.networkProgress", &payload)
            .await
            .unwrap();
        assert!(progress["line"]
            .as_str()
            .is_some_and(|line| !line.is_empty() && line.len() <= 512));
        assert!(handle("workspace", path, "git.pushWithProgress", &payload)
            .await
            .is_err());
        assert!(
            handle("other-workspace", path, "git.networkProgress", &payload)
                .await
                .unwrap()["line"]
                .is_null()
        );
        assert!(
            handle("workspace", "/other-path", "git.networkProgress", &payload)
                .await
                .unwrap()["line"]
                .is_null()
        );
    }
}
