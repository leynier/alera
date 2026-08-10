use std::io::{Read as _, Seek as _, SeekFrom, Write as _};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

use super::prompt_image_store::fs::{create_private_exclusive, open_nofollow, restrict_to_owner};

pub(super) const DIRECTORY: &str = "prompt-files";
const PARTIAL_SUFFIX: &str = ".partial";
const METADATA_SUFFIX: &str = ".meta";
const CLEANUP_MARKER: &str = ".last-cleanup";
const FILE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60 * 60);
static START_GATE: Mutex<()> = Mutex::new(());

pub(super) const MAX_PROMPT_FILE_BYTES: u64 = 32 * 1024 * 1024;
pub(super) const MAX_PROMPT_FILE_STORE_BYTES: u64 = 128 * 1024 * 1024;
pub(super) const MAX_PROMPT_FILE_CHUNK_BYTES: usize = 256 * 1024;
const MAX_PROMPT_FILE_RESERVATIONS: usize = 1024;

#[derive(Debug, Error, PartialEq, Eq)]
pub(super) enum PromptFileStoreError {
    #[error("prompt file store is unavailable: {0}")]
    Io(String),
    #[error("prompt file upload id is invalid")]
    InvalidUploadId,
    #[error("prompt file name is invalid")]
    InvalidFileName,
    #[error("prompt file is empty")]
    Empty,
    #[error("prompt file is too large: {size_bytes} bytes, maximum is {max_bytes} bytes")]
    FileTooLarge { size_bytes: u64, max_bytes: u64 },
    #[error("prompt file store quota exceeded: {size_bytes} bytes, maximum is {max_bytes} bytes")]
    StoreQuotaExceeded { size_bytes: u64, max_bytes: u64 },
    #[error("prompt file store reservation limit exceeded: {count}, maximum is {max_count}")]
    StoreReservationLimitExceeded { count: usize, max_count: usize },
    #[error("prompt file chunk is empty")]
    EmptyChunk,
    #[error("prompt file chunk is too large")]
    ChunkTooLarge,
    #[error("prompt file chunk offset {offset} does not match {actual}")]
    InvalidOffset { offset: u64, actual: u64 },
    #[error("prompt file chunk exceeds the declared length")]
    DeclaredLengthExceeded,
    #[error("prompt file upload reservation is missing")]
    Missing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(super) struct PromptFileReservation {
    pub upload_id: String,
    pub chunk_bytes: usize,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct PromptFileMetadata {
    upload_id: String,
    display_name: String,
    declared_bytes: u64,
    created_at: DateTime<Utc>,
}

pub(super) struct PromptFileStore {
    directory: PathBuf,
    max_reservations: usize,
}

impl PromptFileStore {
    pub(super) fn in_runtime_dir(runtime_dir: &Path) -> Self {
        Self {
            directory: runtime_dir.join(DIRECTORY),
            max_reservations: MAX_PROMPT_FILE_RESERVATIONS,
        }
    }

    #[cfg(test)]
    fn with_reservation_limit(runtime_dir: &Path, max_reservations: usize) -> Self {
        Self {
            directory: runtime_dir.join(DIRECTORY),
            max_reservations,
        }
    }

    pub(super) fn start(
        &self,
        display_name: &str,
        declared_bytes: u64,
    ) -> Result<PromptFileReservation, PromptFileStoreError> {
        let display_name = safe_display_name(display_name)?;
        if declared_bytes == 0 {
            return Err(PromptFileStoreError::Empty);
        }
        if declared_bytes > MAX_PROMPT_FILE_BYTES {
            return Err(PromptFileStoreError::FileTooLarge {
                size_bytes: declared_bytes,
                max_bytes: MAX_PROMPT_FILE_BYTES,
            });
        }
        let _gate = START_GATE
            .lock()
            .map_err(|error| PromptFileStoreError::Io(error.to_string()))?;
        self.prepare_directory()?;
        self.sweep_if_due();
        let usage = self.store_usage()?;
        if usage.reservation_count >= self.max_reservations {
            return Err(PromptFileStoreError::StoreReservationLimitExceeded {
                count: usage.reservation_count.saturating_add(1),
                max_count: self.max_reservations,
            });
        }
        if usage.declared_bytes.saturating_add(declared_bytes) > MAX_PROMPT_FILE_STORE_BYTES {
            return Err(PromptFileStoreError::StoreQuotaExceeded {
                size_bytes: usage.declared_bytes.saturating_add(declared_bytes),
                max_bytes: MAX_PROMPT_FILE_STORE_BYTES,
            });
        }
        let upload_id = Uuid::new_v4().to_string();
        let partial_path = self.partial_path(&upload_id);
        create_private_exclusive(&partial_path).map_err(io_error)?;
        let metadata = PromptFileMetadata {
            upload_id: upload_id.clone(),
            display_name,
            declared_bytes,
            created_at: Utc::now(),
        };
        let metadata_result = (|| {
            let mut metadata_file =
                create_private_exclusive(&self.metadata_path(&upload_id)).map_err(io_error)?;
            serde_json::to_writer(&mut metadata_file, &metadata)
                .map_err(|error| PromptFileStoreError::Io(error.to_string()))?;
            metadata_file.sync_all().map_err(io_error)
        })();
        if let Err(error) = metadata_result {
            let _ = std::fs::remove_file(&partial_path);
            let _ = std::fs::remove_file(self.metadata_path(&upload_id));
            return Err(error);
        }
        Ok(PromptFileReservation {
            upload_id,
            chunk_bytes: MAX_PROMPT_FILE_CHUNK_BYTES,
        })
    }

    pub(super) fn append_chunk(
        &self,
        upload_id: &str,
        offset: u64,
        bytes: &[u8],
    ) -> Result<u64, PromptFileStoreError> {
        let metadata = self.read_metadata(upload_id)?;
        if bytes.is_empty() {
            return Err(PromptFileStoreError::EmptyChunk);
        }
        if bytes.len() > MAX_PROMPT_FILE_CHUNK_BYTES {
            return Err(PromptFileStoreError::ChunkTooLarge);
        }
        let mut file = open_nofollow(&self.partial_path(upload_id), true).map_err(io_error)?;
        let actual = file.metadata().map_err(io_error)?.len();
        if actual != offset {
            return Err(PromptFileStoreError::InvalidOffset { offset, actual });
        }
        let next_offset = offset
            .checked_add(bytes.len() as u64)
            .ok_or(PromptFileStoreError::DeclaredLengthExceeded)?;
        if next_offset > metadata.declared_bytes {
            return Err(PromptFileStoreError::DeclaredLengthExceeded);
        }
        file.seek(SeekFrom::Start(offset)).map_err(io_error)?;
        file.write_all(bytes).map_err(io_error)?;
        Ok(next_offset)
    }

    pub(super) fn complete(&self, upload_id: &str) -> Result<String, PromptFileStoreError> {
        let result = self.complete_inner(upload_id);
        if result.is_err() {
            let _ = self.cancel(upload_id);
        }
        result
    }

    fn complete_inner(&self, upload_id: &str) -> Result<String, PromptFileStoreError> {
        let metadata = self.read_metadata(upload_id)?;
        let partial = self.partial_path(upload_id);
        let actual = std::fs::symlink_metadata(&partial).map_err(io_error)?.len();
        if actual != metadata.declared_bytes {
            return Err(PromptFileStoreError::InvalidOffset {
                offset: metadata.declared_bytes,
                actual,
            });
        }
        open_nofollow(&partial, true)
            .map_err(io_error)?
            .sync_all()
            .map_err(io_error)?;
        let final_path = self.final_path(upload_id, &metadata.display_name);
        std::fs::rename(&partial, &final_path).map_err(io_error)?;
        let path = std::fs::canonicalize(final_path).map_err(io_error)?;
        Ok(path.to_string_lossy().into_owned())
    }

    pub(super) fn cancel(&self, upload_id: &str) -> Result<(), PromptFileStoreError> {
        let upload_id = canonical_upload_id(upload_id)?;
        let metadata = self.read_metadata(&upload_id).ok();
        let _ = std::fs::remove_file(self.partial_path(&upload_id));
        let _ = std::fs::remove_file(self.metadata_path(&upload_id));
        if let Some(metadata) = metadata {
            let _ = std::fs::remove_file(self.final_path(&upload_id, &metadata.display_name));
        }
        Ok(())
    }

    fn prepare_directory(&self) -> Result<(), PromptFileStoreError> {
        std::fs::create_dir_all(&self.directory).map_err(io_error)?;
        let metadata = std::fs::symlink_metadata(&self.directory).map_err(io_error)?;
        if !metadata.file_type().is_dir() {
            return Err(PromptFileStoreError::Io(
                "prompt file directory is not a directory".into(),
            ));
        }
        restrict_to_owner(&self.directory);
        Ok(())
    }

    fn read_metadata(&self, upload_id: &str) -> Result<PromptFileMetadata, PromptFileStoreError> {
        let upload_id = canonical_upload_id(upload_id)?;
        let mut file = open_nofollow(&self.metadata_path(&upload_id), false).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                PromptFileStoreError::Missing
            } else {
                io_error(error)
            }
        })?;
        let mut contents = String::new();
        file.read_to_string(&mut contents).map_err(io_error)?;
        let metadata: PromptFileMetadata = serde_json::from_str(&contents)
            .map_err(|error| PromptFileStoreError::Io(error.to_string()))?;
        if metadata.upload_id != upload_id
            || metadata.declared_bytes == 0
            || metadata.declared_bytes > MAX_PROMPT_FILE_BYTES
            || safe_display_name(&metadata.display_name).is_err()
        {
            return Err(PromptFileStoreError::Missing);
        }
        Ok(metadata)
    }

    fn store_usage(&self) -> Result<PromptFileUsage, PromptFileStoreError> {
        let mut usage = PromptFileUsage::default();
        for entry in std::fs::read_dir(&self.directory).map_err(io_error)? {
            let path = entry.map_err(io_error)?.path();
            let Some(upload_id) = upload_id_from_metadata_path(&path) else {
                continue;
            };
            if let Ok(metadata) = self.read_metadata(&upload_id) {
                usage.declared_bytes = usage.declared_bytes.saturating_add(metadata.declared_bytes);
                usage.reservation_count = usage.reservation_count.saturating_add(1);
            }
        }
        Ok(usage)
    }

    fn sweep_if_due(&self) {
        let marker = self.directory.join(CLEANUP_MARKER);
        if !sweep_is_due(&marker) {
            return;
        }
        let _ = refresh_cleanup_marker(&marker);
        let Ok(entries) = std::fs::read_dir(&self.directory) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(upload_id) = upload_id_from_metadata_path(&path) else {
                continue;
            };
            let expired = path
                .metadata()
                .ok()
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|modified| SystemTime::now().duration_since(modified).ok())
                .is_some_and(|age| age > FILE_TTL);
            if expired {
                let _ = self.cancel(&upload_id);
            }
        }
    }

    fn partial_path(&self, upload_id: &str) -> PathBuf {
        self.directory.join(format!("{upload_id}{PARTIAL_SUFFIX}"))
    }

    fn metadata_path(&self, upload_id: &str) -> PathBuf {
        self.directory
            .join(format!(".{upload_id}{METADATA_SUFFIX}"))
    }

    fn final_path(&self, upload_id: &str, display_name: &str) -> PathBuf {
        let extension = Path::new(display_name)
            .extension()
            .and_then(|value| value.to_str())
            .filter(|value| {
                !value.is_empty()
                    && value.len() <= 16
                    && value
                        .chars()
                        .all(|character| character.is_ascii_alphanumeric())
            })
            .unwrap_or("file");
        self.directory.join(format!("{upload_id}.{extension}"))
    }
}

#[derive(Default)]
struct PromptFileUsage {
    declared_bytes: u64,
    reservation_count: usize,
}

fn safe_display_name(value: &str) -> Result<String, PromptFileStoreError> {
    let name = Path::new(value)
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty() && value.len() <= 180)
        .ok_or(PromptFileStoreError::InvalidFileName)?;
    if name == "." || name == ".." || name.contains('\0') {
        return Err(PromptFileStoreError::InvalidFileName);
    }
    Ok(name.to_string())
}

fn canonical_upload_id(value: &str) -> Result<String, PromptFileStoreError> {
    let parsed = Uuid::parse_str(value).map_err(|_| PromptFileStoreError::InvalidUploadId)?;
    let canonical = parsed.to_string();
    if canonical != value {
        return Err(PromptFileStoreError::InvalidUploadId);
    }
    Ok(canonical)
}

fn upload_id_from_metadata_path(path: &Path) -> Option<String> {
    let file_name = path.file_name()?.to_str()?;
    let id = file_name.strip_prefix('.')?.strip_suffix(METADATA_SUFFIX)?;
    canonical_upload_id(id).ok()
}

fn io_error(error: std::io::Error) -> PromptFileStoreError {
    PromptFileStoreError::Io(error.to_string())
}

fn sweep_is_due(marker: &Path) -> bool {
    marker
        .metadata()
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .is_none_or(|age| age >= CLEANUP_INTERVAL)
}

fn refresh_cleanup_marker(path: &Path) -> std::io::Result<()> {
    match std::fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    create_private_exclusive(path).map(drop)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upload_enforces_chunks_offsets_completion_and_cancellation() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::in_runtime_dir(directory.path());
        let reservation = store.start("report.md", 5).expect("start");

        assert_eq!(store.append_chunk(&reservation.upload_id, 0, b"hel"), Ok(3));
        assert_eq!(
            store.append_chunk(&reservation.upload_id, 0, b"lo"),
            Err(PromptFileStoreError::InvalidOffset {
                offset: 0,
                actual: 3,
            })
        );
        assert_eq!(store.append_chunk(&reservation.upload_id, 3, b"lo"), Ok(5));
        let completed = store.complete(&reservation.upload_id).expect("complete");
        assert_eq!(std::fs::read(completed).expect("read"), b"hello");
        store.cancel(&reservation.upload_id).expect("cancel");
    }

    #[test]
    fn upload_storage_names_are_host_safe_and_preserve_common_extensions() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::in_runtime_dir(directory.path());
        let reservation = store.start("report:2026.txt", 1).expect("start");
        store
            .append_chunk(&reservation.upload_id, 0, b"x")
            .expect("append");

        let completed = store.complete(&reservation.upload_id).expect("complete");
        let file_name = Path::new(&completed)
            .file_name()
            .and_then(|value| value.to_str())
            .expect("file name");

        assert_eq!(file_name, format!("{}.txt", reservation.upload_id));
        assert!(!file_name.contains(':'));
        store.cancel(&reservation.upload_id).expect("cancel");
    }

    #[test]
    fn upload_rejects_invalid_names_sizes_chunks_and_store_quota() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::in_runtime_dir(directory.path());
        assert_eq!(
            store.start("..", 1),
            Err(PromptFileStoreError::InvalidFileName)
        );
        assert!(matches!(
            store.start("large.bin", MAX_PROMPT_FILE_BYTES + 1),
            Err(PromptFileStoreError::FileTooLarge { .. })
        ));

        let reservation = store.start("chunk.bin", 1).expect("start");
        assert_eq!(
            store.append_chunk(
                &reservation.upload_id,
                0,
                &vec![0; MAX_PROMPT_FILE_CHUNK_BYTES + 1],
            ),
            Err(PromptFileStoreError::ChunkTooLarge)
        );
        store.cancel(&reservation.upload_id).expect("cancel");

        let mut reservations = Vec::new();
        for index in 0..4 {
            reservations.push(
                store
                    .start(&format!("quota-{index}.bin"), MAX_PROMPT_FILE_BYTES)
                    .expect("quota reservation"),
            );
        }
        assert!(matches!(
            store.start("overflow.bin", 1),
            Err(PromptFileStoreError::StoreQuotaExceeded { .. })
        ));
        for reservation in reservations {
            store.cancel(&reservation.upload_id).expect("cancel quota");
        }
    }

    #[test]
    fn upload_caps_tiny_reservations_independently_of_byte_quota() {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = PromptFileStore::with_reservation_limit(directory.path(), 2);
        let first = store.start("first.bin", 1).expect("first");
        let second = store.start("second.bin", 1).expect("second");

        assert_eq!(
            store.start("overflow.bin", 1),
            Err(PromptFileStoreError::StoreReservationLimitExceeded {
                count: 3,
                max_count: 2,
            })
        );

        store.cancel(&first.upload_id).expect("cancel first");
        let replacement = store.start("replacement.bin", 1).expect("replacement");
        store.cancel(&second.upload_id).expect("cancel second");
        store
            .cancel(&replacement.upload_id)
            .expect("cancel replacement");
    }
}
