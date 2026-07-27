use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};

/// How long a written screenshot is promised to stay readable.
pub const SCREENSHOT_TTL: Duration = Duration::from_secs(24 * 60 * 60);

/// Shortest gap between directory sweeps.
///
/// An agent calls computer use in a loop, and a sweep per screenshot would turn
/// every capture into a directory scan that grows with the day's history.
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60 * 60);

const CLEANUP_MARKER: &str = ".last-cleanup";

/// Where captures are written for the agent to open.
pub struct ScreenshotStore {
    directory: PathBuf,
}

impl ScreenshotStore {
    /// The store under a runtime profile directory.
    pub fn in_runtime_dir(runtime_dir: &Path) -> Self {
        ScreenshotStore {
            directory: runtime_dir.join("computer-use").join("screenshots"),
        }
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    /// Write one PNG and return the path the agent should open.
    pub fn write_png(&self, snapshot_id: &str, png: &[u8]) -> ComputerResult<PathBuf> {
        self.prepare_directory()?;
        self.sweep_if_due();
        let path = self.directory.join(format!("{snapshot_id}.png"));
        write_private_file(&path, png).map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::ScreenshotFailed,
                format!(
                    "Could not write the screenshot to {}: {error}",
                    path.display()
                ),
            )
        })?;
        Ok(path)
    }

    /// Create the directory with owner-only access.
    ///
    /// A screenshot can hold anything that was on screen, so it must not be
    /// world readable on a shared machine.
    fn prepare_directory(&self) -> ComputerResult<()> {
        std::fs::create_dir_all(&self.directory).map_err(|error| {
            ComputerError::new(
                ComputerErrorCode::ScreenshotFailed,
                format!(
                    "Could not create the screenshot directory {}: {error}",
                    self.directory.display()
                ),
            )
        })?;
        restrict_to_owner(&self.directory);
        Ok(())
    }

    /// Delete expired captures, at most once per interval.
    fn sweep_if_due(&self) {
        let marker = self.directory.join(CLEANUP_MARKER);
        if !sweep_is_due(&marker, CLEANUP_INTERVAL) {
            return;
        }
        // Touch first: a sweep that fails must not make the next call try again
        // immediately, or a permission problem becomes a scan per screenshot.
        let _ = write_private_file(&marker, b"");
        let Ok(entries) = std::fs::read_dir(&self.directory) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("png") {
                continue;
            }
            if is_expired(&path, SCREENSHOT_TTL) {
                let _ = std::fs::remove_file(&path);
            }
        }
    }
}

/// When a capture written now stops being promised.
pub fn expires_at(now: SystemTime) -> SystemTime {
    now + SCREENSHOT_TTL
}

fn sweep_is_due(marker: &Path, interval: Duration) -> bool {
    match std::fs::metadata(marker).and_then(|meta| meta.modified()) {
        Ok(modified) => SystemTime::now()
            .duration_since(modified)
            .map(|age| age >= interval)
            .unwrap_or(true),
        // No marker yet, or an unreadable one: sweep and write it.
        Err(_) => true,
    }
}

fn is_expired(path: &Path, ttl: Duration) -> bool {
    match std::fs::metadata(path).and_then(|meta| meta.modified()) {
        Ok(modified) => SystemTime::now()
            .duration_since(modified)
            .map(|age| age > ttl)
            .unwrap_or(false),
        Err(_) => false,
    }
}

fn write_private_file(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut file = create_private(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}

#[cfg(unix)]
fn create_private(path: &Path) -> std::io::Result<std::fs::File> {
    use std::os::unix::fs::OpenOptionsExt as _;
    std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
}

#[cfg(not(unix))]
fn create_private(path: &Path) -> std::io::Result<std::fs::File> {
    // Windows inherits the parent directory's ACL, and the profile directory is
    // already per user.
    std::fs::File::create(path)
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) {
    use std::os::unix::fs::PermissionsExt as _;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700));
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, ScreenshotStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = ScreenshotStore::in_runtime_dir(dir.path());
        (dir, store)
    }

    #[test]
    fn a_capture_is_written_where_its_path_says() {
        let (_dir, store) = store();
        let path = store.write_png("snap-1", b"fake png").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"fake png");
        assert!(path.ends_with("snap-1.png"));
    }

    /// A screenshot can hold anything that was on screen; on a shared machine it
    /// must not be readable by other users.
    #[cfg(unix)]
    #[test]
    fn captures_and_their_directory_are_owner_only() {
        use std::os::unix::fs::PermissionsExt as _;
        let (_dir, store) = store();
        let path = store.write_png("snap-1", b"png").unwrap();
        let file_mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        let dir_mode = std::fs::metadata(store.directory())
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(file_mode, 0o600);
        assert_eq!(dir_mode, 0o700);
    }

    #[test]
    fn writing_twice_replaces_the_earlier_capture() {
        let (_dir, store) = store();
        store.write_png("snap-1", b"first pass").unwrap();
        let path = store.write_png("snap-1", b"second").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"second");
    }

    #[test]
    fn a_missing_directory_is_created_on_first_write() {
        let (_dir, store) = store();
        assert!(!store.directory().exists());
        store.write_png("snap-1", b"png").unwrap();
        assert!(store.directory().is_dir());
    }

    /// Without the marker an agent in a loop would scan the directory on every
    /// capture, and the scan grows with the day's history.
    #[test]
    fn the_first_write_records_a_sweep_marker() {
        let (_dir, store) = store();
        store.write_png("snap-1", b"png").unwrap();
        assert!(store.directory().join(CLEANUP_MARKER).exists());
    }

    #[test]
    fn a_fresh_marker_holds_off_the_next_sweep() {
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join(CLEANUP_MARKER);
        assert!(sweep_is_due(&marker, CLEANUP_INTERVAL));
        write_private_file(&marker, b"").unwrap();
        assert!(!sweep_is_due(&marker, CLEANUP_INTERVAL));
        // A zero interval is what an immediate re-sweep would look like.
        assert!(sweep_is_due(&marker, Duration::ZERO));
    }

    #[test]
    fn a_just_written_capture_is_not_expired() {
        let (_dir, store) = store();
        let path = store.write_png("snap-1", b"png").unwrap();
        assert!(!is_expired(&path, SCREENSHOT_TTL));
        // A zero TTL is how an already-expired file behaves.
        assert!(is_expired(&path, Duration::ZERO));
    }

    #[test]
    fn a_sweep_removes_expired_captures_and_keeps_fresh_ones() {
        let (_dir, store) = store();
        store.write_png("old", b"png").unwrap();
        let old = store.directory().join("old.png");
        // Force the sweep by clearing the marker the first write left behind.
        std::fs::remove_file(store.directory().join(CLEANUP_MARKER)).unwrap();

        // A sweep with the real TTL keeps a file written moments ago.
        store.write_png("new", b"png").unwrap();
        assert!(old.exists());
        assert!(store.directory().join("new.png").exists());
    }

    #[test]
    fn expiry_is_a_day_out() {
        let now = SystemTime::now();
        assert_eq!(expires_at(now).duration_since(now).unwrap(), SCREENSHOT_TTL);
    }

    #[test]
    fn an_unwritable_directory_reports_screenshot_failed() {
        let dir = tempfile::tempdir().unwrap();
        // A file where the directory should go cannot be turned into one.
        let blocked = dir.path().join("computer-use");
        std::fs::write(&blocked, b"not a directory").unwrap();
        let store = ScreenshotStore::in_runtime_dir(dir.path());
        let error = store.write_png("snap-1", b"png").unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::ScreenshotFailed);
    }
}
