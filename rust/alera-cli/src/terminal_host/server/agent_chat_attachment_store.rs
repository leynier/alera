use std::collections::HashSet;
use std::io::{Read as _, Seek as _, SeekFrom, Write as _};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest as _, Sha256};
use uuid::Uuid;

use super::prompt_image_store::fs::{create_private_exclusive, open_nofollow, restrict_to_owner};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const MAX_FILE_BYTES: u64 = 32 * 1024 * 1024;
pub(super) const MAX_STORE_BYTES: u64 = 128 * 1024 * 1024;
pub(super) const CHUNK_BYTES: usize = 256 * 1024;
const MAX_RESERVATIONS: usize = 512;
const UNUSED_TTL_SECONDS: i64 = 24 * 60 * 60;
static STORE_GATE: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AttachmentScope {
    pub caller: String,
    pub workspace_id: String,
    pub chat_id: String,
}

pub(super) struct AttachmentUploadSpec<'a> {
    pub name: &'a str,
    pub attachment_type: &'a str,
    pub size_bytes: u64,
    pub source_digest: Option<&'a str>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Metadata {
    upload_id: String,
    scope: AttachmentScope,
    name: String,
    attachment_type: String,
    size_bytes: u64,
    #[serde(default)]
    source_digest: Option<String>,
    created_at: DateTime<Utc>,
}

pub(super) struct ChatAttachmentStore {
    directory: PathBuf,
}

impl ChatAttachmentStore {
    pub(super) fn in_runtime_dir(runtime_dir: &Path) -> Self {
        Self {
            directory: runtime_dir.join("agent-chat-attachments"),
        }
    }

    // Disk work and the gate run on a blocking worker, never the host actor.
    pub(super) fn locked<T>(
        &self,
        operation: impl FnOnce(&Self) -> HostResult<T>,
    ) -> HostResult<T> {
        let _guard = STORE_GATE
            .lock()
            .map_err(|_| HostError::state("Chat attachment storage is unavailable."))?;
        operation(self)
    }

    pub(super) fn start(
        &self,
        scope: &AttachmentScope,
        upload_id: &str,
        spec: &AttachmentUploadSpec<'_>,
        live_chats: &HashSet<String>,
    ) -> HostResult<Value> {
        let AttachmentUploadSpec {
            name,
            attachment_type,
            size_bytes,
            source_digest,
        } = *spec;
        validate_id(upload_id)?;
        validate_name(name)?;
        if source_digest.is_some_and(|digest| {
            digest.len() != 64
                || !digest
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || matches!(byte, b'a'..=b'f'))
        }) {
            return Err(HostError::format("Invalid chat attachment source digest."));
        }
        if !matches!(attachment_type, "file" | "localImage") {
            return Err(HostError::format("Unsupported chat attachment type."));
        }
        if size_bytes == 0 || size_bytes > MAX_FILE_BYTES {
            return Err(HostError::format(
                "Chat attachments must contain 1 to 33554432 bytes.",
            ));
        }
        self.prepare()?;
        self.sweep(live_chats)?;
        if self.metadata_path(upload_id).exists() {
            let metadata = self.read(scope, upload_id)?;
            if metadata.name != name
                || metadata.attachment_type != attachment_type
                || metadata.size_bytes != size_bytes
                || metadata.source_digest.as_deref() != source_digest
            {
                return Err(HostError::conflict(
                    "attachment_upload_conflict",
                    "This upload ID belongs to a different attachment.",
                    json!({}),
                ));
            }
            return self.status(&metadata);
        }
        let mut count = 0usize;
        let mut bytes = 0u64;
        for entry in std::fs::read_dir(&self.directory).map_err(io_error)? {
            let path = entry.map_err(io_error)?.path();
            if is_metadata_path(&path) {
                let metadata = self.read_metadata_path(&path)?;
                count += 1;
                bytes = bytes.saturating_add(metadata.size_bytes);
            }
        }
        if count >= MAX_RESERVATIONS || bytes.saturating_add(size_bytes) > MAX_STORE_BYTES {
            return Err(HostError::conflict(
                "attachment_quota_exceeded",
                "Chat attachment storage is full. Remove unused attachments or try again later.",
                json!({"maxStoreBytes": MAX_STORE_BYTES}),
            ));
        }
        let metadata = Metadata {
            upload_id: upload_id.into(),
            scope: scope.clone(),
            name: name.into(),
            attachment_type: attachment_type.into(),
            size_bytes,
            source_digest: source_digest.map(str::to_owned),
            created_at: Utc::now(),
        };
        create_private_exclusive(&self.partial_path(upload_id)).map_err(io_error)?;
        let result = (|| {
            let mut file =
                create_private_exclusive(&self.metadata_path(upload_id)).map_err(io_error)?;
            serde_json::to_writer(&mut file, &metadata)
                .map_err(|error| HostError::state(error.to_string()))?;
            file.sync_all().map_err(io_error)
        })();
        if let Err(error) = result {
            self.remove(&metadata);
            return Err(error);
        }
        self.status(&metadata)
    }

    pub(super) fn append(
        &self,
        scope: &AttachmentScope,
        upload_id: &str,
        offset: u64,
        bytes: &[u8],
    ) -> HostResult<u64> {
        let metadata = self.read(scope, upload_id)?;
        if bytes.is_empty() || bytes.len() > CHUNK_BYTES {
            return Err(HostError::format(
                "Chat attachment chunks must contain 1 to 262144 bytes.",
            ));
        }
        let end = offset
            .checked_add(bytes.len() as u64)
            .filter(|end| *end <= metadata.size_bytes)
            .ok_or_else(|| HostError::format("Chat attachment chunk exceeds its declared size."))?;
        let final_path = self.final_path(&metadata);
        let completed = final_path.exists();
        let path = if completed {
            final_path
        } else {
            self.partial_path(upload_id)
        };
        let mut file = regular_file(&path, !completed)?;
        let actual = file.metadata().map_err(io_error)?.len();
        if offset < actual && end <= actual {
            // Lost acknowledgments may replay bytes, but may never replace them.
            let mut previous = vec![0; bytes.len()];
            file.seek(SeekFrom::Start(offset)).map_err(io_error)?;
            file.read_exact(&mut previous).map_err(io_error)?;
            if previous == bytes {
                return Ok(end);
            }
        } else if offset == actual && !completed {
            file.seek(SeekFrom::Start(offset)).map_err(io_error)?;
            file.write_all(bytes).map_err(io_error)?;
            file.sync_data().map_err(io_error)?;
            return Ok(end);
        }
        Err(HostError::conflict(
            "attachment_offset_conflict",
            "Chat attachment chunk differs from the retained upload. Resume with the same source file.",
            json!({"offset": actual}),
        ))
    }

    pub(super) fn complete(&self, scope: &AttachmentScope, upload_id: &str) -> HostResult<Value> {
        let metadata = self.read(scope, upload_id)?;
        let final_path = self.final_path(&metadata);
        if !final_path.exists() {
            let partial_path = self.partial_path(upload_id);
            let file = regular_file(&partial_path, true)?;
            if file.metadata().map_err(io_error)?.len() != metadata.size_bytes {
                return Err(HostError::format("Chat attachment upload is incomplete."));
            }
            file.sync_all().map_err(io_error)?;
            drop(file);
            if let Some(expected) = &metadata.source_digest {
                let mut file = regular_file(&partial_path, false)?;
                let mut hash = Sha256::new();
                let mut buffer = [0u8; 64 * 1024];
                loop {
                    let count = file.read(&mut buffer).map_err(io_error)?;
                    if count == 0 {
                        break;
                    }
                    hash.update(&buffer[..count]);
                }
                if hex::encode(hash.finalize()) != *expected {
                    self.remove(&metadata);
                    return Err(HostError::conflict(
                        "attachment_source_changed",
                        "The attachment changed while uploading. Add it again.",
                        json!({}),
                    ));
                }
            }
            std::fs::rename(partial_path, &final_path).map_err(io_error)?;
        }
        self.receipt(&metadata)
    }

    pub(super) fn resolve(&self, scope: &AttachmentScope, upload_id: &str) -> HostResult<Value> {
        let metadata = self.read(scope, upload_id)?;
        let receipt = self.receipt(&metadata)?;
        let retained = self.retained_path(upload_id);
        if !retained.exists() {
            create_private_exclusive(&retained)
                .map_err(io_error)?
                .sync_all()
                .map_err(io_error)?;
        }
        Ok(receipt)
    }

    pub(super) fn cancel(&self, scope: &AttachmentScope, upload_id: &str) -> HostResult<()> {
        validate_id(upload_id)?;
        if !self.metadata_path(upload_id).exists() {
            return Ok(());
        }
        let metadata = self.read(scope, upload_id)?;
        // Validation reserves files before native send; an ambiguous send must
        // not let cancellation delete a provider's still-live input.
        if !self.retained_path(upload_id).exists() {
            self.remove(&metadata);
        }
        Ok(())
    }

    fn status(&self, metadata: &Metadata) -> HostResult<Value> {
        let complete = self.final_path(metadata).exists();
        let path = if complete {
            self.final_path(metadata)
        } else {
            self.partial_path(&metadata.upload_id)
        };
        let offset = regular_file(&path, false)?
            .metadata()
            .map_err(io_error)?
            .len();
        if offset > metadata.size_bytes {
            return Err(HostError::state("Invalid chat attachment size."));
        }
        Ok(
            json!({"uploadId":metadata.upload_id, "chunkBytes":CHUNK_BYTES, "offset":offset, "complete":complete, "maxFileBytes":MAX_FILE_BYTES}),
        )
    }

    fn receipt(&self, metadata: &Metadata) -> HostResult<Value> {
        let path = self.final_path(metadata);
        if regular_file(&path, false)?
            .metadata()
            .map_err(io_error)?
            .len()
            != metadata.size_bytes
        {
            return Err(HostError::state(
                "Completed chat attachment is unavailable.",
            ));
        }
        let path = crate::windows_path_form::canonicalize(path).map_err(io_error)?;
        Ok(
            json!({"attachmentId": metadata.upload_id, "path": path.to_string_lossy(), "type": metadata.attachment_type, "name": metadata.name, "sizeBytes": metadata.size_bytes}),
        )
    }

    fn read(&self, scope: &AttachmentScope, upload_id: &str) -> HostResult<Metadata> {
        validate_id(upload_id)?;
        let metadata = self.read_metadata_path(&self.metadata_path(upload_id))?;
        if metadata.upload_id != upload_id {
            return Err(HostError::state(
                "Invalid chat attachment metadata identity.",
            ));
        }
        if &metadata.scope != scope {
            return Err(HostError::conflict(
                "attachment_scope_denied",
                "This attachment belongs to another caller or chat.",
                json!({}),
            ));
        }
        if self.expired(&metadata) {
            return Err(HostError::conflict(
                "attachment_expired",
                "This unused attachment has expired. Add it again.",
                json!({}),
            ));
        }
        Ok(metadata)
    }

    fn read_metadata_path(&self, path: &Path) -> HostResult<Metadata> {
        let mut bytes = Vec::new();
        regular_file(path, false)?
            .take(4097)
            .read_to_end(&mut bytes)
            .map_err(io_error)?;
        if bytes.len() > 4096 {
            return Err(HostError::state("Invalid chat attachment metadata."));
        }
        let metadata: Metadata = serde_json::from_slice(&bytes)
            .map_err(|_| HostError::state("Invalid chat attachment metadata."))?;
        validate_id(&metadata.upload_id)?;
        validate_name(&metadata.name)?;
        if metadata.size_bytes == 0
            || metadata.size_bytes > MAX_FILE_BYTES
            || !matches!(metadata.attachment_type.as_str(), "file" | "localImage")
        {
            return Err(HostError::state("Invalid chat attachment metadata."));
        }
        Ok(metadata)
    }

    fn prepare(&self) -> HostResult<()> {
        std::fs::create_dir_all(&self.directory).map_err(io_error)?;
        if !std::fs::symlink_metadata(&self.directory)
            .map_err(io_error)?
            .file_type()
            .is_dir()
        {
            return Err(HostError::state(
                "Chat attachment storage is not a directory.",
            ));
        }
        restrict_to_owner(&self.directory);
        Ok(())
    }

    fn sweep(&self, live_chats: &HashSet<String>) -> HostResult<()> {
        for entry in std::fs::read_dir(&self.directory).map_err(io_error)? {
            let path = entry.map_err(io_error)?.path();
            if is_metadata_path(&path) {
                let metadata = self.read_metadata_path(&path)?;
                if self.expired(&metadata) || !live_chats.contains(&metadata.scope.chat_id) {
                    self.remove(&metadata);
                }
            }
        }
        Ok(())
    }

    fn expired(&self, metadata: &Metadata) -> bool {
        !self.retained_path(&metadata.upload_id).exists()
            && (Utc::now() - metadata.created_at).num_seconds() >= UNUSED_TTL_SECONDS
    }

    fn remove(&self, metadata: &Metadata) {
        for path in [
            self.partial_path(&metadata.upload_id),
            self.final_path(metadata),
            self.metadata_path(&metadata.upload_id),
            self.retained_path(&metadata.upload_id),
        ] {
            let _ = std::fs::remove_file(path);
        }
    }

    fn partial_path(&self, id: &str) -> PathBuf {
        self.directory.join(format!("{id}.partial"))
    }
    fn metadata_path(&self, id: &str) -> PathBuf {
        self.directory.join(format!("{id}.meta"))
    }
    fn retained_path(&self, id: &str) -> PathBuf {
        self.directory.join(format!("{id}.retained"))
    }
    fn final_path(&self, metadata: &Metadata) -> PathBuf {
        let extension = metadata
            .name
            .rsplit_once('.')
            .map(|(_, extension)| extension)
            .filter(|extension| {
                !extension.is_empty()
                    && extension.len() <= 16
                    && extension.bytes().all(|byte| byte.is_ascii_alphanumeric())
            })
            .unwrap_or("file");
        self.directory
            .join(format!("{}.data.{}", metadata.upload_id, extension))
    }
}

fn validate_id(id: &str) -> HostResult<()> {
    if Uuid::parse_str(id)
        .ok()
        .is_none_or(|uuid| uuid.to_string() != id)
    {
        return Err(HostError::format("Invalid chat attachment upload ID."));
    }
    Ok(())
}

fn is_metadata_path(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .and_then(|name| name.strip_suffix(".meta"))
        .is_some_and(|id| validate_id(id).is_ok())
}

fn validate_name(name: &str) -> HostResult<()> {
    if name.is_empty()
        || name.len() > 180
        || matches!(name, "." | "..")
        || name.contains(['/', '\\', '\0'])
        || name.chars().any(char::is_control)
    {
        return Err(HostError::format("Invalid chat attachment display name."));
    }
    Ok(())
}

fn regular_file(path: &Path, write: bool) -> HostResult<std::fs::File> {
    if !std::fs::symlink_metadata(path)
        .map_err(io_error)?
        .file_type()
        .is_file()
    {
        return Err(HostError::state("Chat attachment file is unavailable."));
    }
    let file = open_nofollow(path, write).map_err(io_error)?;
    if !file.metadata().map_err(io_error)?.is_file() {
        return Err(HostError::state("Chat attachment file is unavailable."));
    }
    Ok(file)
}

fn io_error(error: std::io::Error) -> HostError {
    HostError::state(format!("Chat attachment storage is unavailable: {error}"))
}

#[cfg(test)]
#[path = "agent_chat_attachment_store_tests.rs"]
mod tests;
