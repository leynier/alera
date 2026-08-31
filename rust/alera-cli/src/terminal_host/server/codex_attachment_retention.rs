//! Accepted files remain usable by native history and forks after a tab closes.
//! Only private copies owned exclusively by canceled pending entries are removed.

use super::codex_queue::store_error;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::Value;
use std::path::{Path, PathBuf};

impl ServerActor {
    pub(super) async fn release_codex_attachments(&self, canceled: &Value) -> HostResult<()> {
        let states = self
            .runtime_store
            .list_codex_chat_states()
            .await
            .map_err(store_error)?;
        let root = self.runtime_dir.join("codex-attachments");
        let candidates = owned_directories(canceled, &root);
        tokio::task::spawn_blocking(move || {
            let references = serde_json::to_value(&states).map_err(store_error)?;
            for directory in candidates {
                if !directory.join("accepted").exists()
                    && !references_directory(&references, directory.to_string_lossy().as_ref())
                {
                    match std::fs::remove_dir_all(directory) {
                        Ok(()) => {}
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                        Err(error) => return Err(store_error(error)),
                    }
                }
            }
            Ok(())
        })
        .await
        .map_err(store_error)?
    }

    pub(super) async fn protect_accepted_codex_attachments(
        &self,
        payload: &Value,
    ) -> HostResult<()> {
        let root = self.runtime_dir.join("codex-attachments");
        let paths = owned_directories(payload, &root);
        tokio::task::spawn_blocking(move || {
            for directory in paths {
                alera_core::runtime::open_private_runtime_file(&directory.join("accepted"))
                    .and_then(|file| file.sync_all())
                    .map_err(store_error)?;
            }
            Ok::<_, HostError>(())
        })
        .await
        .map_err(store_error)?
    }
}

fn references_directory(value: &Value, directory: &str) -> bool {
    match value {
        Value::String(text) => text.contains(directory),
        Value::Array(items) => items
            .iter()
            .any(|value| references_directory(value, directory)),
        Value::Object(object) => object
            .values()
            .any(|value| references_directory(value, directory)),
        _ => false,
    }
}

fn owned_directories(payload: &Value, root: &Path) -> Vec<PathBuf> {
    payload
        .get("queueAttachmentDirectories")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(PathBuf::from)
        .filter(|path| {
            path.parent() == Some(root)
                && path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| uuid::Uuid::parse_str(name).is_ok())
        })
        .collect()
}
