use std::io::{self, Read, Write};
use std::path::Path;

use cap_fs_ext::{FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::{ambient_authority, fs::Dir, fs::OpenOptions};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use zeroize::Zeroizing;

const KEY_FILE: &str = "desktop-workflow-approval.key";
const DOMAIN: &[u8] = b"alera.desktop-workflow-decision.v1\0";
const KEY_FILE_MAX_BYTES: u64 = 4096;
pub const APPROVAL_MESSAGE_MAX_BYTES: usize = 8192;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowDecision {
    Approve,
    Reject,
    RequestChanges,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowApprovalChallenge {
    pub version: u32,
    pub nonce: String,
    pub audience: String,
    pub run_id: String,
    pub revision: i64,
    /// "plan", or "stage:<exact recipe stage id>".
    pub scope: String,
    pub plan_digest: String,
    pub evidence_digest: String,
    pub integration_sha: String,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowApprovalStatement {
    pub challenge: WorkflowApprovalChallenge,
    pub decision: WorkflowDecision,
    pub reason: String,
}

impl WorkflowApprovalStatement {
    pub fn message(&self) -> io::Result<Vec<u8>> {
        let challenge = &self.challenge;
        if challenge.version != 1
            || challenge.revision < 1
            || self.reason.len() > 4096
            || self.reason.contains('\0')
            || (self.decision != WorkflowDecision::Approve && self.reason.trim().is_empty())
        {
            return Err(invalid("invalid desktop workflow decision"));
        }
        let bytes = serde_json::to_vec(self).map_err(|_| invalid("invalid workflow statement"))?;
        if bytes.len() > APPROVAL_MESSAGE_MAX_BYTES {
            return Err(invalid("workflow approval exceeds the byte limit"));
        }
        Ok(bytes)
    }
}

/// Separate from the public runtime control token. Deliberately has no
/// Debug/Serialize implementation and never returns raw key material.
pub struct DesktopWorkflowCredential(Zeroizing<[u8; 32]>);

impl DesktopWorkflowCredential {
    pub fn load_or_create(runtime_dir: &Path) -> io::Result<Self> {
        // The caller supplies the existing, runtime-owned private directory.
        // A same-user process with arbitrary filesystem access is not isolated.
        let metadata = std::fs::symlink_metadata(runtime_dir)?;
        if !metadata.is_dir() || metadata.file_type().is_symlink() {
            return Err(invalid(
                "workflow credential requires a private runtime directory",
            ));
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if metadata.permissions().mode() & 0o077 != 0 {
                return Err(invalid("workflow runtime directory is not private"));
            }
        }
        let directory = Dir::open_ambient_dir(runtime_dir, ambient_authority())?;
        match Self::read(&directory) {
            Ok(key) => return Ok(key),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
        let mut key = Zeroizing::new([0u8; 32]);
        key[..16].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
        key[16..].copy_from_slice(uuid::Uuid::new_v4().as_bytes());
        // Atomic publication prevents concurrent desktop/host initialization
        // from observing a partially written key or replacing an existing one.
        let mut temporary = tempfile::NamedTempFile::new_in(runtime_dir)?;
        temporary.write_all(&encode_key(key.as_ref())?)?;
        temporary.as_file().sync_all()?;
        match temporary.persist_noclobber(runtime_dir.join(KEY_FILE)) {
            Ok(_) => {}
            Err(error) if error.error.kind() == io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error.error),
        }
        Self::read(&directory)
    }

    fn read(directory: &Dir) -> io::Result<Self> {
        let mut options = OpenOptions::new();
        options.read(true).follow(FollowSymlinks::No).nonblock(true);
        let file = directory.open_with(KEY_FILE, &options)?;
        let metadata = file.metadata()?;
        if !metadata.is_file() || metadata.len() == 0 || metadata.len() > KEY_FILE_MAX_BYTES {
            return Err(invalid("invalid desktop workflow credential file"));
        }
        #[cfg(unix)]
        {
            use cap_std::fs::PermissionsExt;
            if metadata.permissions().mode() & 0o077 != 0 {
                return Err(invalid("desktop workflow credential file is not private"));
            }
        }
        let mut bytes = Zeroizing::new(Vec::new());
        file.take(KEY_FILE_MAX_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > KEY_FILE_MAX_BYTES {
            return Err(invalid("invalid desktop workflow credential length"));
        }
        let decoded = decode_key(&bytes)?;
        let key: [u8; 32] = decoded
            .as_slice()
            .try_into()
            .map_err(|_| invalid("invalid desktop workflow credential length"))?;
        Ok(Self(Zeroizing::new(key)))
    }

    pub fn sign(&self, statement: &WorkflowApprovalStatement) -> io::Result<Vec<u8>> {
        Ok(self.mac(statement)?.finalize().into_bytes().to_vec())
    }

    pub fn verify(
        &self,
        statement: WorkflowApprovalStatement,
        proof: &[u8],
    ) -> io::Result<VerifiedWorkflowDecision> {
        self.mac(&statement)?
            .verify_slice(proof)
            .map_err(|_| invalid("desktop workflow authorization failed"))?;
        Ok(VerifiedWorkflowDecision(statement))
    }

    fn mac(&self, statement: &WorkflowApprovalStatement) -> io::Result<Hmac<Sha256>> {
        let mut mac = Hmac::<Sha256>::new_from_slice(self.0.as_ref())
            .map_err(|_| invalid("desktop workflow credential unavailable"))?;
        mac.update(DOMAIN);
        mac.update(&statement.message()?);
        Ok(mac)
    }
}

/// Only the credential verifier can construct this capability. Runtime store
/// decisions cannot be authorized by an actor/clientKind string.
pub struct VerifiedWorkflowDecision(WorkflowApprovalStatement);

impl VerifiedWorkflowDecision {
    pub fn statement(&self) -> &WorkflowApprovalStatement {
        &self.0
    }
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[cfg(not(windows))]
fn encode_key(key: &[u8]) -> io::Result<Zeroizing<Vec<u8>>> {
    Ok(Zeroizing::new(key.to_vec()))
}

#[cfg(not(windows))]
fn decode_key(key: &[u8]) -> io::Result<Zeroizing<Vec<u8>>> {
    Ok(Zeroizing::new(key.to_vec()))
}

#[cfg(windows)]
#[path = "workflow_approval_windows.rs"]
mod windows_credential;
#[cfg(windows)]
use windows_credential::{decode_key, encode_key};

#[cfg(test)]
#[path = "workflow_approval_tests.rs"]
mod tests;
