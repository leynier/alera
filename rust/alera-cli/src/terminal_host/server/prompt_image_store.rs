use std::io::{Read as _, Seek as _, SeekFrom, Write as _};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub(super) mod fs;

use self::fs::{create_private_exclusive, open_nofollow, restrict_to_owner};

pub(super) const PROMPT_IMAGE_DIRECTORY: &str = "prompt-images";
const PARTIAL_SUFFIX: &str = ".partial";
const METADATA_SUFFIX: &str = ".meta";
const CLEANUP_MARKER: &str = ".last-cleanup";
const IMAGE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60 * 60);

pub(super) const MAX_PROMPT_IMAGE_BYTES: u64 = 18 * 1024 * 1024;
pub(super) const MAX_PROMPT_IMAGE_STORE_BYTES: u64 = 128 * 1024 * 1024;
pub(super) const MAX_PROMPT_IMAGE_CHUNK_BYTES: usize = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PromptImageFormat {
    Png,
    Jpeg,
    Gif,
    Webp,
}

impl PromptImageFormat {
    pub(super) fn parse(value: &str) -> Result<Self, PromptImageStoreError> {
        match value.to_ascii_lowercase().as_str() {
            "png" => Ok(Self::Png),
            "jpeg" | "jpg" => Ok(Self::Jpeg),
            "gif" => Ok(Self::Gif),
            "webp" => Ok(Self::Webp),
            _ => Err(PromptImageStoreError::UnsupportedFormat(value.to_string())),
        }
    }

    fn wire_name(self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpeg",
            Self::Gif => "gif",
            Self::Webp => "webp",
        }
    }

    fn extension(self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpg",
            Self::Gif => "gif",
            Self::Webp => "webp",
        }
    }

    fn matches_magic(self, header: &[u8]) -> bool {
        match self {
            Self::Png => header.starts_with(b"\x89PNG\r\n\x1a\n"),
            Self::Jpeg => header.starts_with(&[0xff, 0xd8, 0xff]),
            Self::Gif => header.starts_with(b"GIF87a") || header.starts_with(b"GIF89a"),
            Self::Webp => header.starts_with(b"RIFF") && header.get(8..12) == Some(b"WEBP"),
        }
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub(super) enum PromptImageStoreError {
    #[error("prompt image store is unavailable: {0}")]
    Io(String),
    #[error("prompt image upload id is invalid")]
    InvalidUploadId,
    #[error("prompt image format is unsupported: {0}")]
    UnsupportedFormat(String),
    #[error("prompt image is empty")]
    Empty,
    #[error("prompt image is too large: {size_bytes} bytes, maximum is {max_bytes} bytes")]
    FileTooLarge { size_bytes: u64, max_bytes: u64 },
    #[error("prompt image store quota exceeded: {size_bytes} bytes, maximum is {max_bytes} bytes")]
    StoreQuotaExceeded { size_bytes: u64, max_bytes: u64 },
    #[error("prompt image chunk is empty")]
    EmptyChunk,
    #[error("prompt image chunk is too large: {size_bytes} bytes, maximum is {max_bytes} bytes")]
    ChunkTooLarge { size_bytes: usize, max_bytes: usize },
    #[error(
        "prompt image chunk offset {offset} does not match the current upload offset {actual}"
    )]
    InvalidOffset { offset: u64, actual: u64 },
    #[error("prompt image chunk exceeds the declared image length")]
    DeclaredLengthExceeded,
    #[error("prompt image upload reservation is missing")]
    Missing,
    #[error("prompt image payload does not match the declared format")]
    FormatMismatch,
}

#[derive(Debug, Clone, Copy)]
struct PromptImageLimits {
    max_file_bytes: u64,
    max_store_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(super) struct PromptImageReservation {
    pub(super) upload_id: String,
    pub(super) chunk_bytes: usize,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct PromptImageMetadata {
    upload_id: String,
    format: String,
    declared_bytes: u64,
    created_at: DateTime<Utc>,
}

pub(super) struct PromptImageStore {
    directory: PathBuf,
    limits: PromptImageLimits,
}

impl PromptImageStore {
    pub(super) fn in_runtime_dir(runtime_dir: &Path) -> Self {
        Self {
            directory: runtime_dir.join(PROMPT_IMAGE_DIRECTORY),
            limits: PromptImageLimits {
                max_file_bytes: MAX_PROMPT_IMAGE_BYTES,
                max_store_bytes: MAX_PROMPT_IMAGE_STORE_BYTES,
            },
        }
    }

    pub(super) fn start(
        &self,
        format: &str,
        declared_bytes: u64,
    ) -> Result<PromptImageReservation, PromptImageStoreError> {
        let format = PromptImageFormat::parse(format)?;
        if declared_bytes == 0 {
            return Err(PromptImageStoreError::Empty);
        }
        if declared_bytes > self.limits.max_file_bytes {
            return Err(PromptImageStoreError::FileTooLarge {
                size_bytes: declared_bytes,
                max_bytes: self.limits.max_file_bytes,
            });
        }
        self.prepare_directory()?;
        self.sweep_if_due();
        let store_size = self.store_usage_bytes()?;
        if store_size.saturating_add(declared_bytes) > self.limits.max_store_bytes {
            return Err(PromptImageStoreError::StoreQuotaExceeded {
                size_bytes: store_size.saturating_add(declared_bytes),
                max_bytes: self.limits.max_store_bytes,
            });
        }

        for _ in 0..8 {
            let upload_id = Uuid::new_v4().to_string();
            let partial_path = self.partial_path(&upload_id);
            let metadata_path = self.metadata_path(&upload_id);
            let partial = match create_private_exclusive(&partial_path) {
                Ok(file) => file,
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(io_error(error)),
            };
            drop(partial);

            let metadata = PromptImageMetadata {
                upload_id: upload_id.clone(),
                format: format.wire_name().to_string(),
                declared_bytes,
                created_at: Utc::now(),
            };
            let mut metadata_file = match create_private_exclusive(&metadata_path) {
                Ok(file) => file,
                Err(error) => {
                    let _ = std::fs::remove_file(partial_path);
                    if error.kind() == std::io::ErrorKind::AlreadyExists {
                        continue;
                    }
                    return Err(io_error(error));
                }
            };
            if let Err(error) = serde_json::to_writer(&mut metadata_file, &metadata) {
                drop(metadata_file);
                let _ = std::fs::remove_file(&metadata_path);
                let _ = std::fs::remove_file(self.partial_path(&upload_id));
                return Err(PromptImageStoreError::Io(error.to_string()));
            }
            if let Err(error) = metadata_file.sync_all() {
                drop(metadata_file);
                let _ = std::fs::remove_file(&metadata_path);
                let _ = std::fs::remove_file(self.partial_path(&upload_id));
                return Err(io_error(error));
            }
            return Ok(PromptImageReservation {
                upload_id,
                chunk_bytes: MAX_PROMPT_IMAGE_CHUNK_BYTES,
            });
        }
        Err(PromptImageStoreError::Io(
            "could not reserve a unique prompt image identity".to_string(),
        ))
    }

    pub(super) fn append_chunk(
        &self,
        upload_id: &str,
        offset: u64,
        bytes: &[u8],
    ) -> Result<u64, PromptImageStoreError> {
        self.prepare_directory()?;
        self.sweep_if_due();
        let metadata = self.read_metadata(upload_id)?;
        if bytes.is_empty() {
            return Err(PromptImageStoreError::EmptyChunk);
        }
        if bytes.len() > MAX_PROMPT_IMAGE_CHUNK_BYTES {
            return Err(PromptImageStoreError::ChunkTooLarge {
                size_bytes: bytes.len(),
                max_bytes: MAX_PROMPT_IMAGE_CHUNK_BYTES,
            });
        }
        let path = self.partial_path(upload_id);
        let actual = std::fs::symlink_metadata(&path).map_err(io_error)?;
        if !actual.file_type().is_file() {
            return Err(PromptImageStoreError::Missing);
        }
        let mut file = open_nofollow(&path, true).map_err(io_error)?;
        let current_offset = file.metadata().map_err(io_error)?.len();
        if current_offset != offset {
            return Err(PromptImageStoreError::InvalidOffset {
                offset,
                actual: current_offset,
            });
        }
        let next_offset = offset
            .checked_add(bytes.len() as u64)
            .ok_or(PromptImageStoreError::DeclaredLengthExceeded)?;
        if next_offset > metadata.declared_bytes {
            return Err(PromptImageStoreError::DeclaredLengthExceeded);
        }
        file.seek(SeekFrom::Start(offset)).map_err(io_error)?;
        file.write_all(bytes).map_err(io_error)?;
        file.sync_data().map_err(io_error)?;
        Ok(next_offset)
    }

    pub(super) fn complete(&self, upload_id: &str) -> Result<String, PromptImageStoreError> {
        self.prepare_directory()?;
        self.sweep_if_due();
        let result = self.complete_inner(upload_id);
        if result.is_err() {
            self.remove_all_for_id(upload_id);
        }
        result
    }

    pub(super) fn cancel(&self, upload_id: &str) -> Result<(), PromptImageStoreError> {
        let _ = canonical_upload_id(upload_id)?;
        self.prepare_directory()?;
        self.sweep_if_due();
        self.remove_all_for_id(upload_id);
        Ok(())
    }

    fn complete_inner(&self, upload_id: &str) -> Result<String, PromptImageStoreError> {
        let metadata = self.read_metadata(upload_id)?;
        let format = PromptImageFormat::parse(&metadata.format)?;
        let partial_path = self.partial_path(upload_id);
        let partial_metadata = std::fs::symlink_metadata(&partial_path).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                PromptImageStoreError::Missing
            } else {
                io_error(error)
            }
        })?;
        if !partial_metadata.file_type().is_file() {
            return Err(PromptImageStoreError::Missing);
        }
        let actual_bytes = partial_metadata.len();
        if actual_bytes != metadata.declared_bytes {
            return Err(PromptImageStoreError::InvalidOffset {
                offset: metadata.declared_bytes,
                actual: actual_bytes,
            });
        }
        let mut file = open_nofollow(&partial_path, false).map_err(io_error)?;
        let mut header = [0_u8; 12];
        let header_bytes = file.read(&mut header).map_err(io_error)?;
        if !format.matches_magic(&header[..header_bytes]) {
            return Err(PromptImageStoreError::FormatMismatch);
        }
        let final_path = self.final_path(upload_id, format);
        if std::fs::symlink_metadata(&final_path).is_ok_and(|entry| !entry.file_type().is_file()) {
            return Err(PromptImageStoreError::Missing);
        }
        std::fs::rename(&partial_path, &final_path).map_err(io_error)?;
        let absolute_path = std::fs::canonicalize(&final_path).map_err(io_error)?;
        Ok(absolute_path.to_string_lossy().into_owned())
    }

    fn prepare_directory(&self) -> Result<(), PromptImageStoreError> {
        std::fs::create_dir_all(&self.directory).map_err(io_error)?;
        let metadata = std::fs::symlink_metadata(&self.directory).map_err(io_error)?;
        if !metadata.file_type().is_dir() {
            return Err(PromptImageStoreError::Io(
                "prompt image directory is not a directory".to_string(),
            ));
        }
        restrict_to_owner(&self.directory);
        Ok(())
    }

    fn read_metadata(&self, upload_id: &str) -> Result<PromptImageMetadata, PromptImageStoreError> {
        let upload_id = canonical_upload_id(upload_id)?;
        let path = self.metadata_path(&upload_id);
        let metadata = std::fs::symlink_metadata(&path).map_err(|error| {
            if error.kind() == std::io::ErrorKind::NotFound {
                PromptImageStoreError::Missing
            } else {
                io_error(error)
            }
        })?;
        if !metadata.file_type().is_file() {
            return Err(PromptImageStoreError::Missing);
        }
        let mut file = open_nofollow(&path, false).map_err(io_error)?;
        let mut contents = String::new();
        file.read_to_string(&mut contents).map_err(io_error)?;
        let metadata: PromptImageMetadata = serde_json::from_str(&contents)
            .map_err(|error| PromptImageStoreError::Io(error.to_string()))?;
        if metadata.upload_id != upload_id
            || metadata.declared_bytes == 0
            || metadata.declared_bytes > self.limits.max_file_bytes
        {
            return Err(PromptImageStoreError::Missing);
        }
        PromptImageFormat::parse(&metadata.format)?;
        Ok(metadata)
    }

    fn store_usage_bytes(&self) -> Result<u64, PromptImageStoreError> {
        let mut size_bytes = 0_u64;
        for entry in std::fs::read_dir(&self.directory).map_err(io_error)? {
            let path = entry.map_err(io_error)?.path();
            let Some(upload_id) = upload_id_from_metadata_path(&path) else {
                continue;
            };
            let Ok(metadata) = self.read_metadata(&upload_id) else {
                continue;
            };
            let format = PromptImageFormat::parse(&metadata.format)?;
            let has_state = is_regular_file(&self.partial_path(&upload_id))
                || is_regular_file(&self.final_path(&upload_id, format));
            if has_state {
                size_bytes = size_bytes.saturating_add(metadata.declared_bytes);
            }
        }
        Ok(size_bytes)
    }

    fn sweep_if_due(&self) {
        let marker = self.directory.join(CLEANUP_MARKER);
        if !sweep_is_due(&marker) {
            return;
        }
        let _ = refresh_cleanup_marker(&marker);
        self.sweep_expired(SystemTime::now());
    }

    fn sweep_expired(&self, now: SystemTime) {
        let Ok(entries) = std::fs::read_dir(&self.directory) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(upload_id) = upload_id_from_metadata_path(&path) else {
                continue;
            };
            let expired = std::fs::symlink_metadata(&path)
                .ok()
                .filter(|metadata| metadata.file_type().is_file())
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|modified| now.duration_since(modified).ok())
                .is_some_and(|age| age > IMAGE_TTL);
            if expired {
                self.remove_all_for_id(&upload_id);
            }
        }
    }

    fn remove_all_for_id(&self, upload_id: &str) {
        let Ok(upload_id) = canonical_upload_id(upload_id) else {
            return;
        };
        let _ = std::fs::remove_file(self.partial_path(&upload_id));
        let _ = std::fs::remove_file(self.metadata_path(&upload_id));
        for format in [
            PromptImageFormat::Png,
            PromptImageFormat::Jpeg,
            PromptImageFormat::Gif,
            PromptImageFormat::Webp,
        ] {
            let _ = std::fs::remove_file(self.final_path(&upload_id, format));
        }
    }

    fn partial_path(&self, upload_id: &str) -> PathBuf {
        self.directory.join(format!("{upload_id}{PARTIAL_SUFFIX}"))
    }

    fn metadata_path(&self, upload_id: &str) -> PathBuf {
        self.directory
            .join(format!(".{upload_id}{METADATA_SUFFIX}"))
    }

    fn final_path(&self, upload_id: &str, format: PromptImageFormat) -> PathBuf {
        self.directory
            .join(format!("{upload_id}.{}", format.extension()))
    }

    #[cfg(test)]
    fn with_limits(runtime_dir: &Path, max_file_bytes: u64, max_store_bytes: u64) -> Self {
        Self {
            directory: runtime_dir.join(PROMPT_IMAGE_DIRECTORY),
            limits: PromptImageLimits {
                max_file_bytes,
                max_store_bytes,
            },
        }
    }
}

fn canonical_upload_id(value: &str) -> Result<String, PromptImageStoreError> {
    let parsed = Uuid::parse_str(value).map_err(|_| PromptImageStoreError::InvalidUploadId)?;
    let canonical = parsed.to_string();
    if canonical != value {
        return Err(PromptImageStoreError::InvalidUploadId);
    }
    Ok(canonical)
}

fn upload_id_from_metadata_path(path: &Path) -> Option<String> {
    let file_name = path.file_name()?.to_str()?;
    let id = file_name.strip_prefix('.')?.strip_suffix(METADATA_SUFFIX)?;
    canonical_upload_id(id).ok()
}

fn is_regular_file(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_file())
}

fn io_error(error: std::io::Error) -> PromptImageStoreError {
    PromptImageStoreError::Io(error.to_string())
}

fn sweep_is_due(marker: &Path) -> bool {
    std::fs::symlink_metadata(marker)
        .ok()
        .filter(|metadata| metadata.file_type().is_file())
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
#[path = "prompt_image_store_tests.rs"]
mod tests;
