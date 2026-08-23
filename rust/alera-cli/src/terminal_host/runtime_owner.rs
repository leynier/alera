use std::fs::{File, OpenOptions};
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use alera_core::runtime::{
    create_private_runtime_file, prepare_private_runtime_directory, set_private_file_permissions,
};
use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};

mod process_identity;

use process_identity::{
    current_process_identity, ProcessIdentity, ProcessIdentityProbe, ProcessLookup,
    SystemProcessIdentityProbe, PLATFORM,
};

const LOCK_FILE_NAME: &str = "runtime-owner.lock";
const OWNER_FILE_NAME: &str = "runtime-owner.json";
const OWNER_SCHEMA_VERSION: u32 = 1;
const OWNER_EXIT_TIMEOUT: Duration = Duration::from_secs(10);
const OWNER_EXIT_RETRY_DELAY: Duration = Duration::from_millis(10);

/// Holds the runtime profile's operating-system lock for the host lifetime.
///
/// The file is intentionally never deleted. Removing a locked file can create
/// a second inode on Unix, letting another process lock the new inode while the
/// original owner is still running.
pub(crate) struct RuntimeOwnerGuard {
    _lock: File,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RuntimeOwnerIdentity {
    pub(crate) pid: u32,
    pub(crate) start_marker: u64,
}

impl From<ProcessIdentity> for RuntimeOwnerIdentity {
    fn from(identity: ProcessIdentity) -> Self {
        Self {
            pid: identity.pid,
            start_marker: identity.start_marker,
        }
    }
}

impl From<RuntimeOwnerIdentity> for ProcessIdentity {
    fn from(identity: RuntimeOwnerIdentity) -> Self {
        Self {
            pid: identity.pid,
            start_marker: identity.start_marker,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct RuntimeOwnerRecord {
    #[serde(rename = "schemaVersion")]
    schema_version: u32,
    platform: String,
    pid: u32,
    #[serde(rename = "processStartMarker")]
    process_start_marker: u64,
}

impl RuntimeOwnerRecord {
    fn new(identity: ProcessIdentity) -> Self {
        Self {
            schema_version: OWNER_SCHEMA_VERSION,
            platform: PLATFORM.to_string(),
            pid: identity.pid,
            process_start_marker: identity.start_marker,
        }
    }

    fn identity(&self) -> ProcessIdentity {
        ProcessIdentity {
            pid: self.pid,
            start_marker: self.process_start_marker,
        }
    }
}

impl RuntimeOwnerGuard {
    pub(crate) fn acquire(runtime_dir: &Path) -> Result<Self> {
        let identity = current_process_identity().map_err(|error| anyhow!(error))?;
        Self::acquire_with_probe(runtime_dir, identity, &SystemProcessIdentityProbe)
    }

    pub(crate) fn acquire_handoff(
        runtime_dir: &Path,
        expected_owner: RuntimeOwnerIdentity,
    ) -> Result<Self> {
        let identity = current_process_identity().map_err(|error| anyhow!(error))?;
        Self::acquire_handoff_with_probe(
            runtime_dir,
            expected_owner,
            identity,
            &SystemProcessIdentityProbe,
        )
    }

    fn acquire_handoff_with_probe(
        runtime_dir: &Path,
        expected_owner: RuntimeOwnerIdentity,
        identity: ProcessIdentity,
        probe: &impl ProcessIdentityProbe,
    ) -> Result<Self> {
        prepare_private_runtime_directory(runtime_dir)?;
        validate_handoff_owner(runtime_dir, expected_owner)?;
        let lock_path = runtime_dir.join(LOCK_FILE_NAME);
        let lock = open_lock_file(&lock_path)?;
        lock.lock().with_context(|| {
            format!(
                "failed waiting for runtime ownership at {}",
                lock_path.display()
            )
        })?;
        finish_handoff(runtime_dir, expected_owner, identity, probe, lock)
    }

    fn acquire_with_probe(
        runtime_dir: &Path,
        identity: ProcessIdentity,
        probe: &impl ProcessIdentityProbe,
    ) -> Result<Self> {
        prepare_private_runtime_directory(runtime_dir)?;
        let lock_path = runtime_dir.join(LOCK_FILE_NAME);
        let lock = open_lock_file(&lock_path)?;
        match lock.try_lock() {
            Ok(()) => {
                validate_abandoned_owner(runtime_dir, identity, probe)?;
                write_owner_record(runtime_dir, &RuntimeOwnerRecord::new(identity))?;
                Ok(Self { _lock: lock })
            }
            Err(std::fs::TryLockError::WouldBlock) => reject_locked_owner(runtime_dir, probe),
            Err(std::fs::TryLockError::Error(error)) => Err(error).with_context(|| {
                format!(
                    "failed locking runtime ownership at {}",
                    lock_path.display()
                )
            }),
        }
    }
}

fn finish_handoff(
    runtime_dir: &Path,
    expected_owner: RuntimeOwnerIdentity,
    identity: ProcessIdentity,
    probe: &impl ProcessIdentityProbe,
    lock: File,
) -> Result<RuntimeOwnerGuard> {
    validate_handoff_owner(runtime_dir, expected_owner)?;
    wait_for_owner_exit(expected_owner.into(), probe)?;
    validate_abandoned_owner(runtime_dir, identity, probe)?;
    write_owner_record(runtime_dir, &RuntimeOwnerRecord::new(identity))?;
    Ok(RuntimeOwnerGuard { _lock: lock })
}

pub(crate) fn current_owner_identity() -> Result<RuntimeOwnerIdentity> {
    current_process_identity()
        .map(RuntimeOwnerIdentity::from)
        .map_err(|error| anyhow!(error))
}

fn validate_handoff_owner(runtime_dir: &Path, expected_owner: RuntimeOwnerIdentity) -> Result<()> {
    let record = read_owner_record(runtime_dir)?.ok_or_else(|| {
        anyhow!(
            "runtime owner handoff expected process {}, but owner metadata is not available",
            expected_owner.pid
        )
    })?;
    if record.schema_version != OWNER_SCHEMA_VERSION || record.platform != PLATFORM {
        bail!(
            "runtime ownership metadata cannot be validated safely; expected schema {} on {}, found schema {} on {}",
            OWNER_SCHEMA_VERSION,
            PLATFORM,
            record.schema_version,
            record.platform
        );
    }
    if record.identity() != ProcessIdentity::from(expected_owner) {
        bail!(
            "runtime owner handoff expected process {} with start marker {}, but owner metadata names process {} with start marker {}; refusing replacement",
            expected_owner.pid,
            expected_owner.start_marker,
            record.pid,
            record.process_start_marker
        );
    }
    Ok(())
}

fn wait_for_owner_exit(owner: ProcessIdentity, probe: &impl ProcessIdentityProbe) -> Result<()> {
    let deadline = Instant::now() + OWNER_EXIT_TIMEOUT;
    loop {
        match probe.lookup(owner.pid) {
            ProcessLookup::Exited => return Ok(()),
            ProcessLookup::Live(actual) if actual != owner => return Ok(()),
            ProcessLookup::Live(_) if Instant::now() < deadline => {
                std::thread::sleep(OWNER_EXIT_RETRY_DELAY);
            }
            ProcessLookup::Live(_) => bail!(
                "replaced runtime owner process {} did not exit within {}s",
                owner.pid,
                OWNER_EXIT_TIMEOUT.as_secs()
            ),
            ProcessLookup::Unknown(reason) => bail!(
                "runtime owner process {} could not be validated after releasing its lock: {}",
                owner.pid,
                reason
            ),
        }
    }
}

pub(crate) fn live_owner_pid(runtime_dir: &Path) -> Result<Option<u32>> {
    let Some(record) = read_owner_record(runtime_dir)? else {
        return Ok(None);
    };
    if record.schema_version != OWNER_SCHEMA_VERSION || record.platform != PLATFORM {
        bail!(
            "runtime ownership metadata cannot be validated safely; expected schema {} on {}, found schema {} on {}",
            OWNER_SCHEMA_VERSION,
            PLATFORM,
            record.schema_version,
            record.platform
        );
    }
    let recorded = record.identity();
    match SystemProcessIdentityProbe.lookup(recorded.pid) {
        ProcessLookup::Live(actual) if actual == recorded => Ok(Some(recorded.pid)),
        ProcessLookup::Live(_) | ProcessLookup::Exited => Ok(None),
        ProcessLookup::Unknown(reason) => bail!(
            "runtime owner process {} could not be validated: {}",
            recorded.pid,
            reason
        ),
    }
}

fn open_lock_file(path: &Path) -> Result<File> {
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path)
        .with_context(|| format!("failed opening runtime ownership lock {}", path.display()))?;
    set_private_file_permissions(path)?;
    Ok(file)
}

fn validate_abandoned_owner(
    runtime_dir: &Path,
    current: ProcessIdentity,
    probe: &impl ProcessIdentityProbe,
) -> Result<()> {
    let Some(record) = read_owner_record(runtime_dir)? else {
        return Ok(());
    };
    if record.schema_version != OWNER_SCHEMA_VERSION || record.platform != PLATFORM {
        bail!(
            "runtime ownership metadata cannot be validated safely; expected schema {} on {}, found schema {} on {}",
            OWNER_SCHEMA_VERSION,
            PLATFORM,
            record.schema_version,
            record.platform
        );
    }
    let recorded = record.identity();
    match probe.lookup(recorded.pid) {
        ProcessLookup::Exited => Ok(()),
        ProcessLookup::Live(actual) if actual != recorded => Ok(()),
        ProcessLookup::Live(actual) if actual == current => bail!(
            "runtime directory is already attributed to this live process {}",
            actual.pid
        ),
        ProcessLookup::Live(actual) => bail!(
            "runtime ownership metadata still names live process {}; refusing stale-owner recovery",
            actual.pid
        ),
        ProcessLookup::Unknown(reason) => bail!(
            "runtime owner process {} could not be validated; refusing stale-owner recovery: {}",
            recorded.pid,
            reason
        ),
    }
}

fn reject_locked_owner(
    runtime_dir: &Path,
    probe: &impl ProcessIdentityProbe,
) -> Result<RuntimeOwnerGuard> {
    let record = read_owner_record(runtime_dir)?.ok_or_else(|| {
        anyhow!(
            "runtime ownership lock is held but owner metadata is not available; refusing to start"
        )
    })?;
    if record.schema_version != OWNER_SCHEMA_VERSION || record.platform != PLATFORM {
        bail!(
            "runtime ownership lock is held by unverifiable schema {} on {}; refusing to start",
            record.schema_version,
            record.platform
        );
    }
    let recorded = record.identity();
    match probe.lookup(recorded.pid) {
        ProcessLookup::Live(actual) if actual == recorded => bail!(
            "runtime directory is already owned by live runtime host process {}",
            actual.pid
        ),
        ProcessLookup::Live(_) | ProcessLookup::Exited => bail!(
            "runtime ownership lock is still held after recorded owner process {} exited or its PID was reused; refusing to start",
            recorded.pid
        ),
        ProcessLookup::Unknown(reason) => bail!(
            "runtime ownership lock is held but owner process {} could not be validated; refusing to start: {}",
            recorded.pid,
            reason
        ),
    }
}

fn read_owner_record(runtime_dir: &Path) -> Result<Option<RuntimeOwnerRecord>> {
    let path = runtime_dir.join(OWNER_FILE_NAME);
    let contents = match std::fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| {
                format!("failed reading runtime owner metadata {}", path.display())
            });
        }
    };
    serde_json::from_str(&contents)
        .map(Some)
        .with_context(|| format!("runtime owner metadata {} is invalid", path.display()))
}

fn write_owner_record(runtime_dir: &Path, record: &RuntimeOwnerRecord) -> Result<()> {
    let path = runtime_dir.join(OWNER_FILE_NAME);
    let temp = owner_temp_path(&path);
    let mut file = create_private_runtime_file(&temp)?;
    file.write_all(serde_json::to_string(record)?.as_bytes())?;
    file.sync_all()?;
    std::fs::rename(&temp, &path)?;
    set_private_file_permissions(&path)?;
    Ok(())
}

fn owner_temp_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(".tmp");
    PathBuf::from(name)
}

#[cfg(test)]
mod tests;
