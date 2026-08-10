use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::prompt_file_store::{
    PromptFileStore, MAX_PROMPT_FILE_BYTES, MAX_PROMPT_FILE_CHUNK_BYTES,
    MAX_PROMPT_FILE_STORE_BYTES,
};
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};

const MAX_ENCODED_CHUNK_BYTES: usize = MAX_PROMPT_FILE_CHUNK_BYTES.div_ceil(3) * 4;
type UploadGate = Mutex<()>;
type UploadGateRegistry = Mutex<HashMap<String, Weak<UploadGate>>>;

static UPLOAD_GATES: OnceLock<UploadGateRegistry> = OnceLock::new();

impl ServerActor {
    pub(super) fn start_mobile_prompt_file_request(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) {
        let runtime_dir = self.runtime_dir.clone();
        let request_type = request_type.to_string();
        let upload_id = payload
            .get("uploadId")
            .and_then(Value::as_str)
            .map(str::to_string);
        let payload = payload.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let operation = request_type.clone();
            let result = tokio::task::spawn_blocking(move || {
                handle_prompt_file_request(runtime_dir, &request_type, &payload)
            })
            .await
            .map_err(|error| HostError::state(format!("Prompt file operation failed: {error}")))
            .and_then(|result| result);
            let _ = inbox.send(ServerCommand::MobilePromptFileFinished {
                client_id,
                request_id,
                request_type: operation,
                upload_id,
                result,
            });
        });
    }

    pub(super) fn handle_mobile_prompt_file_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        requested_upload_id: Option<&str>,
        result: HostResult<Value>,
    ) {
        if matches!(
            request_type,
            "mobile.promptFile.complete" | "mobile.promptFile.cancel"
        ) {
            if let Some(upload_id) = requested_upload_id {
                self.remove_mobile_prompt_file_upload(client_id, upload_id);
            }
        }
        if !self.clients.contains_key(&client_id) {
            cancel_orphaned_start(&self.runtime_dir, &result);
            return;
        }
        let response = match &result {
            Ok(value) => ok_response(request_id, value.clone()),
            Err(error) => error_response(request_id, error),
        };
        if !self.try_client_write(client_id, response) {
            cancel_orphaned_start(&self.runtime_dir, &result);
            return;
        }
        if result.is_err() {
            return;
        }
        if request_type == "mobile.promptFile.start" {
            if let Some(upload_id) = result
                .as_ref()
                .ok()
                .and_then(|value| value.get("uploadId"))
                .and_then(Value::as_str)
            {
                self.mobile_prompt_file_uploads
                    .entry(client_id)
                    .or_default()
                    .insert(upload_id.to_string());
            }
        }
    }

    pub(super) fn cancel_mobile_prompt_file_uploads(&mut self, client_id: u64) {
        let Some(upload_ids) = self.mobile_prompt_file_uploads.remove(&client_id) else {
            return;
        };
        let runtime_dir = self.runtime_dir.clone();
        tokio::task::spawn_blocking(move || {
            for upload_id in upload_ids {
                cancel_upload(&runtime_dir, &upload_id);
            }
        });
    }

    fn remove_mobile_prompt_file_upload(&mut self, client_id: u64, upload_id: &str) {
        let Some(upload_ids) = self.mobile_prompt_file_uploads.get_mut(&client_id) else {
            return;
        };
        upload_ids.remove(upload_id);
        if upload_ids.is_empty() {
            self.mobile_prompt_file_uploads.remove(&client_id);
        }
    }
}

fn cancel_orphaned_start(runtime_dir: &std::path::Path, result: &HostResult<Value>) {
    let Some(upload_id) = result
        .as_ref()
        .ok()
        .and_then(|value| value.get("uploadId"))
        .and_then(Value::as_str)
    else {
        return;
    };
    cancel_upload(runtime_dir, upload_id);
}

fn cancel_upload(runtime_dir: &std::path::Path, upload_id: &str) {
    let store = PromptFileStore::in_runtime_dir(runtime_dir);
    if let Err(error) = with_upload_gate(upload_id, || {
        store.cancel(upload_id).map_err(prompt_file_error)
    }) {
        if !error.wire_message().contains("reservation is missing") {
            tracing::warn!(target: "prompt_file_store", "Could not cancel disconnected prompt file upload: {error}");
        }
    }
}

fn handle_prompt_file_request(
    runtime_dir: PathBuf,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let store = PromptFileStore::in_runtime_dir(&runtime_dir);
    match request_type {
        "mobile.promptFile.start" => {
            let display_name = require_string_key(payload, "name")?;
            let declared_bytes = payload
                .get("sizeBytes")
                .and_then(Value::as_u64)
                .ok_or_else(|| HostError::state("Prompt file sizeBytes must be an integer."))?;
            let reservation = store
                .start(&display_name, declared_bytes)
                .map_err(prompt_file_error)?;
            Ok(json!({
                "uploadId": reservation.upload_id,
                "chunkBytes": reservation.chunk_bytes,
                "maxFileBytes": MAX_PROMPT_FILE_BYTES,
                "maxStoreBytes": MAX_PROMPT_FILE_STORE_BYTES,
            }))
        }
        "mobile.promptFile.chunk" => {
            let upload_id = require_string_key(payload, "uploadId")?;
            let offset = payload
                .get("offset")
                .and_then(Value::as_u64)
                .ok_or_else(|| HostError::state("Prompt file offset must be an integer."))?;
            let encoded = require_string_key(payload, "dataBase64")?;
            if encoded.len() > MAX_ENCODED_CHUNK_BYTES {
                return Err(HostError::state(
                    "Prompt file chunk exceeds the decoded limit.",
                ));
            }
            let bytes = STANDARD
                .decode(encoded.as_bytes())
                .map_err(|_| HostError::state("Prompt file chunk is not valid base64."))?;
            let next_offset = with_upload_gate(&upload_id, || {
                store
                    .append_chunk(&upload_id, offset, &bytes)
                    .map_err(prompt_file_error)
            })?;
            Ok(json!({"nextOffset": next_offset}))
        }
        "mobile.promptFile.complete" => {
            let upload_id = require_string_key(payload, "uploadId")?;
            let path = with_upload_gate(&upload_id, || {
                store.complete(&upload_id).map_err(prompt_file_error)
            })?;
            Ok(json!({"path": path, "uploadId": upload_id}))
        }
        "mobile.promptFile.cancel" => {
            let upload_id = require_string_key(payload, "uploadId")?;
            with_upload_gate(&upload_id, || {
                store.cancel(&upload_id).map_err(prompt_file_error)
            })?;
            Ok(json!({}))
        }
        _ => Err(HostError::state("Unsupported prompt file operation.")),
    }
}

fn prompt_file_error(error: super::prompt_file_store::PromptFileStoreError) -> HostError {
    HostError::state(error.to_string())
}

fn with_upload_gate<T>(
    upload_id: &str,
    operation: impl FnOnce() -> HostResult<T>,
) -> HostResult<T> {
    let gate = {
        let mut gates = upload_gates()
            .lock()
            .map_err(|error| HostError::state(format!("Prompt file gate failed: {error}")))?;
        gates.retain(|_, gate| gate.strong_count() > 0);
        gates
            .entry(upload_id.to_string())
            .or_insert_with(Weak::new)
            .upgrade()
            .unwrap_or_else(|| {
                let gate = Arc::new(Mutex::new(()));
                gates.insert(upload_id.to_string(), Arc::downgrade(&gate));
                gate
            })
    };
    let guard = gate
        .lock()
        .map_err(|error| HostError::state(format!("Prompt file gate failed: {error}")))?;
    let result = operation();
    drop(guard);
    remove_idle_upload_gate(upload_id, &gate);
    result
}

fn upload_gates() -> &'static UploadGateRegistry {
    UPLOAD_GATES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn remove_idle_upload_gate(upload_id: &str, gate: &Arc<UploadGate>) {
    let Ok(mut gates) = upload_gates().lock() else {
        return;
    };
    if Arc::strong_count(gate) == 1
        && gates
            .get(upload_id)
            .is_some_and(|registered| Weak::ptr_eq(registered, &Arc::downgrade(gate)))
    {
        gates.remove(upload_id);
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Barrier};
    use std::thread;
    use std::time::Duration;

    use super::*;
    use crate::terminal_host::client::ClientHandle;

    use super::super::actor_test_harness::{mobile_client, test_actor};

    #[test]
    fn mutations_for_one_upload_are_serialized() {
        let ready = Arc::new(Barrier::new(3));
        let active = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let mut workers = Vec::new();

        for _ in 0..2 {
            let ready = Arc::clone(&ready);
            let active = Arc::clone(&active);
            let peak = Arc::clone(&peak);
            workers.push(thread::spawn(move || {
                ready.wait();
                with_upload_gate("same-upload", || {
                    let current = active.fetch_add(1, Ordering::SeqCst) + 1;
                    peak.fetch_max(current, Ordering::SeqCst);
                    thread::sleep(Duration::from_millis(25));
                    active.fetch_sub(1, Ordering::SeqCst);
                    Ok(())
                })
                .expect("gated mutation");
            }));
        }

        ready.wait();
        for worker in workers {
            worker.join().expect("worker");
        }
        assert_eq!(peak.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn different_uploads_can_mutate_concurrently() {
        let entered = Arc::new(Barrier::new(3));
        let mut workers = Vec::new();

        for upload_id in ["first-upload", "second-upload"] {
            let entered = Arc::clone(&entered);
            workers.push(thread::spawn(move || {
                with_upload_gate(upload_id, || {
                    entered.wait();
                    Ok(())
                })
                .expect("gated mutation");
            }));
        }

        entered.wait();
        for worker in workers {
            worker.join().expect("worker");
        }
    }

    #[test]
    fn disconnected_upload_results_release_their_store_reservation() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::in_runtime_dir(directory.path());
        let reservation = store.start("orphaned.bin", 1).expect("start");
        let start_result = Ok(json!({"uploadId": reservation.upload_id}));

        cancel_orphaned_start(directory.path(), &start_result);

        assert_eq!(
            store.append_chunk(&reservation.upload_id, 0, b"x"),
            Err(super::super::prompt_file_store::PromptFileStoreError::Missing)
        );

        let reservation = store.start("completed.bin", 1).expect("start");
        store
            .append_chunk(&reservation.upload_id, 0, b"x")
            .expect("append");
        let complete_result = handle_prompt_file_request(
            directory.path().to_path_buf(),
            "mobile.promptFile.complete",
            &json!({"uploadId": reservation.upload_id}),
        )
        .expect("complete");
        let completed_path = complete_result["path"].as_str().unwrap().to_string();

        cancel_orphaned_start(directory.path(), &Ok(complete_result));

        assert!(!std::path::Path::new(&completed_path).exists());
        assert_eq!(
            store.append_chunk(&reservation.upload_id, 0, b"x"),
            Err(super::super::prompt_file_store::PromptFileStoreError::Missing)
        );
    }

    #[tokio::test]
    async fn acknowledged_uploads_are_tracked_until_cancelled_or_disconnected() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::in_runtime_dir(directory.path());
        let (handle, _receiver) = ClientHandle::test_channels();
        let mut actor = test_actor(
            &directory,
            HashMap::from([(1, mobile_client(handle, "phone"))]),
            HashMap::new(),
        )
        .await;

        let cancelled = store.start("cancelled.bin", 1).expect("start");
        actor.handle_mobile_prompt_file_finished(
            1,
            1,
            "mobile.promptFile.start",
            None,
            Ok(json!({"uploadId": cancelled.upload_id})),
        );
        assert!(actor.mobile_prompt_file_uploads[&1].contains(&cancelled.upload_id));
        actor.handle_mobile_prompt_file_finished(
            1,
            2,
            "mobile.promptFile.cancel",
            Some(&cancelled.upload_id),
            Ok(json!({})),
        );
        assert!(!actor.mobile_prompt_file_uploads.contains_key(&1));

        let incomplete = store.start("incomplete.bin", 2).expect("start");
        store
            .append_chunk(&incomplete.upload_id, 0, b"x")
            .expect("append");
        actor.handle_mobile_prompt_file_finished(
            1,
            3,
            "mobile.promptFile.start",
            None,
            Ok(json!({"uploadId": incomplete.upload_id})),
        );
        let complete_result = handle_prompt_file_request(
            directory.path().to_path_buf(),
            "mobile.promptFile.complete",
            &json!({"uploadId": incomplete.upload_id}),
        );
        assert!(complete_result.is_err());
        actor.handle_mobile_prompt_file_finished(
            1,
            4,
            "mobile.promptFile.complete",
            Some(&incomplete.upload_id),
            complete_result,
        );
        assert!(!actor.mobile_prompt_file_uploads.contains_key(&1));
        assert_eq!(
            store.append_chunk(&incomplete.upload_id, 1, b"x"),
            Err(super::super::prompt_file_store::PromptFileStoreError::Missing)
        );

        let disconnected = store.start("disconnected.bin", 1).expect("start");
        actor.handle_mobile_prompt_file_finished(
            1,
            5,
            "mobile.promptFile.start",
            None,
            Ok(json!({"uploadId": disconnected.upload_id})),
        );
        actor.dispose_client(1).await;

        for _ in 0..50 {
            if matches!(
                store.append_chunk(&disconnected.upload_id, 0, b"x"),
                Err(super::super::prompt_file_store::PromptFileStoreError::Missing)
            ) {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("disconnected upload reservation was not cancelled");
    }
}
