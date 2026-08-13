use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use super::validate_retention_id;
use crate::git::{GitError, GitErrorKind};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostedReviewOperation {
    pub repo_path: String,
    pub retention_id: String,
    pub owner_pid: u32,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct HostedReviewOperationMarker {
    repo_path: String,
    retention_id: String,
    owner_pid: u32,
}

const OPERATION_MARKER_PREFIX: &str = "alera-hosted-review-operation-";
const OPERATION_MARKER_SUFFIX: &str = ".json";

pub fn hosted_review_operations() -> Vec<HostedReviewOperation> {
    let Ok(entries) = fs::read_dir(std::env::temp_dir()) else {
        return Vec::new();
    };
    entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name();
            let name = name.to_str()?;
            let retention_id = name
                .strip_prefix(OPERATION_MARKER_PREFIX)?
                .strip_suffix(OPERATION_MARKER_SUFFIX)?;
            if validate_retention_id(retention_id).is_err() {
                return None;
            }
            let encoded = fs::read(entry.path()).ok()?;
            let marker = serde_json::from_slice::<HostedReviewOperationMarker>(&encoded).ok()?;
            if marker.retention_id != retention_id || marker.repo_path.trim().is_empty() {
                return None;
            }
            Some(HostedReviewOperation {
                repo_path: marker.repo_path,
                retention_id: marker.retention_id,
                owner_pid: marker.owner_pid,
            })
        })
        .collect()
}

pub fn clear_hosted_review_operation(retention_id: &str) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    let path = operation_marker_path(retention_id);
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(hosted_review_io_error("clear operation marker", error)),
    }
}

pub(super) fn hosted_review_operation_is_recorded(retention_id: &str) -> bool {
    validate_retention_id(retention_id).is_ok() && operation_marker_path(retention_id).is_file()
}

pub fn record_hosted_review_operation(repo_path: &str, retention_id: &str) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    let marker = HostedReviewOperationMarker {
        repo_path: repo_path.to_string(),
        retention_id: retention_id.to_string(),
        owner_pid: std::process::id(),
    };
    let encoded = serde_json::to_vec(&marker)
        .map_err(|error| GitError::new(GitErrorKind::Internal, error.to_string()))?;
    let path = operation_marker_path(retention_id);
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&path)
        .map_err(|error| hosted_review_io_error("create operation marker", error))?;
    if let Err(error) = file.write_all(&encoded).and_then(|()| file.sync_all()) {
        let _ = fs::remove_file(path);
        return Err(hosted_review_io_error("write operation marker", error));
    }
    Ok(())
}

fn operation_marker_path(retention_id: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "{OPERATION_MARKER_PREFIX}{retention_id}{OPERATION_MARKER_SUFFIX}"
    ))
}

fn hosted_review_io_error(action: &str, error: std::io::Error) -> GitError {
    GitError::new(
        GitErrorKind::Internal,
        format!("could not {action}: {error}"),
    )
}
