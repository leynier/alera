use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{bail, Context as _, Result};
use serde_json::{json, Value};
use tokio::time::{sleep, Instant};

use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::runtime_owner::{
    live_owner_identity, terminate_live_owner, RuntimeClearGuard,
};

const GRACEFUL_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(15);
const FORCED_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(10);

const RUNTIME_IDENTITY_MARKERS: &[&str] = &[
    "runtime-owner.lock",
    "runtime-owner.json",
    "runtime.sqlite",
    "terminal_history.sqlite",
];

pub(crate) async fn clear_runtime_profile(runtime_dir: &Path, force: bool) -> Result<Value> {
    match std::fs::symlink_metadata(runtime_dir) {
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(clear_payload(runtime_dir, force, false, 0));
        }
        Err(error) => {
            return Err(error).with_context(|| {
                format!("failed inspecting runtime path {}", runtime_dir.display())
            });
        }
    }
    validate_clear_target(runtime_dir)?;

    let mut host_stopped = false;
    match RuntimeHostRpcClient::connect(runtime_dir).await? {
        Some(_) if !force => {
            bail!("runtime host is running; stop it first or retry `alera runtime clear --force`");
        }
        Some(mut client) => {
            client
                .request_value("host.shutdown", &json!({ "force": true }))
                .await
                .context("runtime host refused forced shutdown before clear")?;
            host_stopped = true;
        }
        None => {
            if let Some(owner) = live_owner_identity(runtime_dir)? {
                if !force {
                    bail!(
                        "runtime host process {} is still alive but its control metadata is unavailable; retry `alera runtime clear --force`",
                        owner.pid
                    );
                }
                terminate_live_owner(runtime_dir)?;
                host_stopped = true;
            }
        }
    }

    if host_stopped && !wait_for_owner_exit(runtime_dir, GRACEFUL_SHUTDOWN_TIMEOUT).await? {
        terminate_live_owner(runtime_dir)?;
        if !wait_for_owner_exit(runtime_dir, FORCED_SHUTDOWN_TIMEOUT).await? {
            let pid = live_owner_identity(runtime_dir)?
                .map(|owner| owner.pid.to_string())
                .unwrap_or_else(|| "unknown".to_string());
            bail!("runtime host process {pid} did not exit; refusing to clear its profile");
        }
    }

    let guard = RuntimeClearGuard::acquire(runtime_dir)?;
    let entries_removed = guard.clear_profile(runtime_dir)?;
    Ok(clear_payload(
        runtime_dir,
        force,
        host_stopped,
        entries_removed,
    ))
}

async fn wait_for_owner_exit(runtime_dir: &Path, timeout: Duration) -> Result<bool> {
    let deadline = Instant::now() + timeout;
    loop {
        if live_owner_identity(runtime_dir)?.is_none() {
            return Ok(true);
        }
        if Instant::now() >= deadline {
            return Ok(false);
        }
        sleep(Duration::from_millis(25)).await;
    }
}

fn validate_clear_target(runtime_dir: &Path) -> Result<()> {
    let metadata = std::fs::symlink_metadata(runtime_dir)
        .with_context(|| format!("failed inspecting runtime path {}", runtime_dir.display()))?;
    if metadata.file_type().is_symlink() {
        bail!(
            "refusing to clear runtime path {} because it is a symbolic link",
            runtime_dir.display()
        );
    }
    if !metadata.is_dir() {
        bail!(
            "refusing to clear runtime path {} because it is not a directory",
            runtime_dir.display()
        );
    }

    let canonical = dunce::canonicalize(runtime_dir).with_context(|| {
        format!(
            "failed resolving runtime directory {} before clear",
            runtime_dir.display()
        )
    })?;
    reject_broad_target(&canonical)?;

    let mut empty = true;
    let mut recognized = false;
    for entry in std::fs::read_dir(runtime_dir)
        .with_context(|| format!("failed reading runtime directory {}", runtime_dir.display()))?
    {
        let entry = entry?;
        empty = false;
        if RUNTIME_IDENTITY_MARKERS
            .iter()
            .any(|marker| entry.file_name() == *marker)
        {
            recognized = true;
        }
    }
    if !empty && !recognized {
        bail!(
            "refusing to clear {} because it does not look like an Alera runtime profile",
            runtime_dir.display()
        );
    }
    Ok(())
}

fn reject_broad_target(canonical: &Path) -> Result<()> {
    if canonical.parent().is_none() {
        bail!("refusing to clear filesystem root {}", canonical.display());
    }
    if let Some(home) = home_directory().and_then(canonical_existing_path) {
        if canonical == home {
            bail!("refusing to clear home directory {}", canonical.display());
        }
    }
    if let Ok(current) = std::env::current_dir().and_then(dunce::canonicalize) {
        if current.starts_with(canonical) {
            bail!(
                "refusing to clear {} because it contains the current working directory",
                canonical.display()
            );
        }
    }
    Ok(())
}

fn home_directory() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

fn canonical_existing_path(path: PathBuf) -> Option<PathBuf> {
    dunce::canonicalize(path).ok()
}

fn clear_payload(
    runtime_dir: &Path,
    forced: bool,
    host_stopped: bool,
    entries_removed: usize,
) -> Value {
    json!({
        "runtimeDir": runtime_dir.display().to_string(),
        "cleared": true,
        "forced": forced,
        "hostStopped": host_stopped,
        "entriesRemoved": entries_removed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn clears_recognized_profile_but_keeps_stable_lock_inode() {
        let root = tempfile::tempdir().unwrap();
        let runtime = root.path().join("runtime");
        std::fs::create_dir_all(runtime.join("logs")).unwrap();
        std::fs::write(runtime.join("runtime.sqlite"), b"database").unwrap();
        std::fs::write(runtime.join("logs").join("runtime.log"), b"log").unwrap();

        let result = clear_runtime_profile(&runtime, false).await.unwrap();

        assert_eq!(result["cleared"], true);
        assert_eq!(result["hostStopped"], false);
        assert!(runtime.join("runtime-owner.lock").is_file());
        assert_eq!(std::fs::read_dir(&runtime).unwrap().count(), 1);
    }

    #[tokio::test]
    async fn refuses_non_runtime_directory() {
        let root = tempfile::tempdir().unwrap();
        let target = root.path().join("unrelated");
        std::fs::create_dir(&target).unwrap();
        std::fs::write(target.join("important.txt"), b"keep").unwrap();

        let error = clear_runtime_profile(&target, true).await.unwrap_err();

        assert!(error.to_string().contains("does not look like"));
        assert_eq!(
            std::fs::read(target.join("important.txt")).unwrap(),
            b"keep"
        );
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn refuses_dangling_runtime_directory_symlink() {
        use std::os::unix::fs::symlink;

        let root = tempfile::tempdir().unwrap();
        let target = root.path().join("runtime");
        symlink(root.path().join("missing"), &target).unwrap();

        let error = clear_runtime_profile(&target, true).await.unwrap_err();

        assert!(error.to_string().contains("symbolic link"));
        assert!(std::fs::symlink_metadata(target).is_ok());
    }

    #[tokio::test]
    async fn clears_stale_owner_metadata_after_the_recorded_process_is_gone() {
        let root = tempfile::tempdir().unwrap();
        let runtime = root.path().join("runtime");
        std::fs::create_dir_all(&runtime).unwrap();
        std::fs::write(runtime.join("runtime.sqlite"), b"database").unwrap();
        std::fs::write(
            runtime.join("runtime-owner.json"),
            serde_json::to_vec(&json!({
                "schemaVersion": 1,
                "platform": std::env::consts::OS,
                "pid": u32::MAX,
                "processStartMarker": 1,
            }))
            .unwrap(),
        )
        .unwrap();

        clear_runtime_profile(&runtime, false).await.unwrap();

        assert!(runtime.join("runtime-owner.lock").is_file());
        assert!(!runtime.join("runtime-owner.json").exists());
        assert_eq!(std::fs::read_dir(&runtime).unwrap().count(), 1);
    }
}
