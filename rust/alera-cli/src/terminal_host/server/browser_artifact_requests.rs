use std::path::Path;

use chrono::Utc;
use serde_json::{json, Value};

use super::browser_artifact_store::{
    BrowserArtifact, BrowserArtifactCompletionError, BrowserArtifactStore,
};
use super::browser_broker::BrowserCall;

pub(super) struct BrowserArtifactFailure {
    pub code: &'static str,
    pub message: String,
    pub next_steps: &'static [&'static str],
}

pub(super) fn prepare_browser_call_params(
    runtime_dir: &Path,
    request_type: &str,
    payload: &Value,
    correlation_id: &str,
) -> std::io::Result<Value> {
    let mut params = payload.clone();
    let Some(format) = capture_format(request_type) else {
        return Ok(params);
    };
    let Some(object) = params.as_object_mut() else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "browser payload must be an object",
        ));
    };
    for untrusted in ["outputPath", "destinationPath", "expiresAt", "format"] {
        object.remove(untrusted);
    }
    let artifact =
        BrowserArtifactStore::in_runtime_dir(runtime_dir).reserve(correlation_id, format)?;
    object.insert("destinationPath".to_string(), json!(artifact.path));
    object.insert("expiresAt".to_string(), json!(artifact.expires_at));
    object.insert("format".to_string(), json!(artifact.format));
    Ok(params)
}

pub(super) fn remove_browser_artifact(runtime_dir: &Path, call: &BrowserCall) {
    if let Some(artifact) = browser_artifact(call) {
        BrowserArtifactStore::in_runtime_dir(runtime_dir).remove(&artifact);
    }
}

pub(super) fn normalize_browser_outcome(outcome: &mut Value) {
    if !outcome.get("ok").is_some_and(Value::is_boolean) {
        *outcome = json!({"ok": true, "result": outcome.take()});
        return;
    }
    if outcome["ok"].as_bool() != Some(false) {
        return;
    }
    let object = outcome
        .as_object_mut()
        .expect("browser outcome with an ok field is an object");
    let raw_error = object
        .remove("error")
        .unwrap_or_else(|| json!({"message": "The browser driver reported an error."}));
    let mut error = match raw_error {
        Value::Object(error) => error,
        Value::String(message) => {
            serde_json::Map::from_iter([("message".to_string(), json!(message))])
        }
        _ => serde_json::Map::new(),
    };
    error
        .entry("code")
        .or_insert_with(|| json!("browser_driver_error"));
    error
        .entry("message")
        .or_insert_with(|| json!("The browser driver reported an error."));
    error.entry("nextSteps").or_insert_with(|| json!([]));
    error.entry("retryable").or_insert_with(|| json!(true));
    object.insert("error".to_string(), Value::Object(error));
}

pub(super) fn finalize_capture_outcome(
    runtime_dir: &Path,
    call: &BrowserCall,
    outcome: &mut Value,
) -> Option<BrowserArtifactFailure> {
    let artifact = browser_artifact(call)?;
    strip_capture_data(outcome);
    let store = BrowserArtifactStore::in_runtime_dir(runtime_dir);
    if outcome["ok"].as_bool() == Some(true) {
        match store.completed(artifact.clone()) {
            Ok(artifact) => {
                outcome
                    .as_object_mut()
                    .expect("normalized browser outcome is an object")
                    .insert("artifact".to_string(), json!(artifact));
                return None;
            }
            Err(error) => return Some(artifact_completion_failure(error)),
        }
    }
    store.remove(&artifact);
    None
}

fn capture_format(request_type: &str) -> Option<&'static str> {
    match request_type {
        "browser.screenshot" => Some("png"),
        "browser.pdf" => Some("pdf"),
        _ => None,
    }
}

fn browser_artifact(call: &BrowserCall) -> Option<BrowserArtifact> {
    let format = capture_format(&call.request_type)?;
    let path = call.params.get("destinationPath")?.as_str()?.to_string();
    let expires_at = call
        .params
        .get("expiresAt")?
        .as_str()?
        .parse::<chrono::DateTime<Utc>>()
        .ok()?;
    Some(BrowserArtifact {
        path,
        format,
        mime_type: match format {
            "pdf" => "application/pdf",
            _ => "image/png",
        },
        size_bytes: 0,
        expires_at,
        suggested_file_name: format!(
            "{}-{}.{}",
            if format == "pdf" {
                "browser-page"
            } else {
                "browser-screenshot"
            },
            call.correlation_id,
            format,
        ),
        reservation_id: call.correlation_id.clone(),
    })
}

fn artifact_completion_failure(error: BrowserArtifactCompletionError) -> BrowserArtifactFailure {
    match error {
        BrowserArtifactCompletionError::InvalidReservation
        | BrowserArtifactCompletionError::Missing
        | BrowserArtifactCompletionError::Empty => BrowserArtifactFailure {
            code: "artifact_missing",
            message: "The browser driver completed without a valid reserved artifact."
                .to_string(),
            next_steps: &["Retry the capture or inspect the registered browser driver."],
        },
        BrowserArtifactCompletionError::FileTooLarge {
            size_bytes,
            max_bytes,
        } => BrowserArtifactFailure {
            code: "artifact_too_large",
            message: format!(
                "The browser artifact used {size_bytes} bytes, exceeding the {max_bytes}-byte per-file limit."
            ),
            next_steps: &[
                "Capture a smaller viewport or reduce the printable page before retrying.",
            ],
        },
        BrowserArtifactCompletionError::StoreQuotaExceeded {
            store_size_bytes,
            max_bytes,
        } => BrowserArtifactFailure {
            code: "artifact_quota_exceeded",
            message: format!(
                "Browser artifacts used {store_size_bytes} bytes, exceeding the {max_bytes}-byte store quota."
            ),
            next_steps: &[
                "Delete no-longer-needed artifact files or wait for their expiry, then retry.",
            ],
        },
        BrowserArtifactCompletionError::StoreUnavailable(message) => BrowserArtifactFailure {
            code: "artifact_unavailable",
            message: format!("The browser artifact store could not validate the result: {message}"),
            next_steps: &["Check the Alera runtime directory permissions and retry."],
        },
    }
}

fn strip_capture_data(value: &mut Value) {
    match value {
        Value::Object(object) => {
            for key in [
                "base64",
                "bytes",
                "content",
                "data",
                "destinationPath",
                "outputPath",
                "path",
            ] {
                object.remove(key);
            }
            for child in object.values_mut() {
                strip_capture_data(child);
            }
        }
        Value::Array(items) => {
            for item in items {
                strip_capture_data(item);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const REQUEST_ID: &str = "00000000-0000-4000-8000-000000000001";

    #[test]
    fn caller_paths_are_replaced_by_private_host_paths() {
        let runtime = tempfile::tempdir().unwrap();
        let params = prepare_browser_call_params(
            runtime.path(),
            "browser.screenshot",
            &json!({
                "outputPath": "/tmp/caller",
                "destinationPath": "/tmp/driver",
                "expiresAt": "never",
            }),
            REQUEST_ID,
        )
        .unwrap();
        assert_ne!(params["destinationPath"], "/tmp/driver");
        assert!(params["destinationPath"]
            .as_str()
            .unwrap()
            .ends_with(&format!("browser/artifacts/{REQUEST_ID}.png")));
        assert!(params.get("outputPath").is_none());
        assert_eq!(params["format"], "png");
    }

    #[test]
    fn driver_failures_always_have_retryability() {
        let mut value = json!({"ok": false, "error": {"message": "blocked"}});
        normalize_browser_outcome(&mut value);
        assert_eq!(value["error"]["retryable"], true);
        assert_eq!(value["error"]["code"], "browser_driver_error");
    }

    #[test]
    fn capture_results_drop_driver_bytes_and_paths() {
        let mut value = json!({
            "ok": true,
            "result": {
                "bytes": [1, 2, 3],
                "path": "/tmp/driver-controlled",
                "width": 800,
            }
        });
        strip_capture_data(&mut value);
        assert_eq!(value["result"].get("bytes"), None);
        assert_eq!(value["result"].get("path"), None);
        assert_eq!(value["result"]["width"], 800);
    }

    #[test]
    fn artifact_limit_failures_have_stable_machine_readable_codes() {
        let too_large = artifact_completion_failure(BrowserArtifactCompletionError::FileTooLarge {
            size_bytes: 5,
            max_bytes: 4,
        });
        let quota =
            artifact_completion_failure(BrowserArtifactCompletionError::StoreQuotaExceeded {
                store_size_bytes: 11,
                max_bytes: 10,
            });

        assert_eq!(too_large.code, "artifact_too_large");
        assert_eq!(quota.code, "artifact_quota_exceeded");
    }
}
