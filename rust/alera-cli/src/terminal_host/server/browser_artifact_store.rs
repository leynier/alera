use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use chrono::{DateTime, Utc};
use serde::Serialize;
use uuid::Uuid;

const ARTIFACT_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60 * 60);
const CLEANUP_MARKER: &str = ".last-cleanup";
const RESERVATION_MARKER_SUFFIX: &str = ".reservation";
pub(super) const MAX_BROWSER_ARTIFACT_BYTES: u64 = 64 * 1024 * 1024;
pub(super) const MAX_BROWSER_ARTIFACT_STORE_BYTES: u64 = 256 * 1024 * 1024;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct BrowserArtifact {
    pub path: String,
    pub format: &'static str,
    pub mime_type: &'static str,
    pub size_bytes: u64,
    pub expires_at: DateTime<Utc>,
    pub suggested_file_name: String,
    #[serde(skip)]
    pub reservation_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum BrowserArtifactCompletionError {
    InvalidReservation,
    Missing,
    Empty,
    FileTooLarge {
        size_bytes: u64,
        max_bytes: u64,
    },
    StoreQuotaExceeded {
        store_size_bytes: u64,
        max_bytes: u64,
    },
    StoreUnavailable(String),
}

#[derive(Clone, Copy)]
struct BrowserArtifactLimits {
    max_file_bytes: u64,
    max_store_bytes: u64,
}

pub(super) struct BrowserArtifactStore {
    directory: PathBuf,
    limits: BrowserArtifactLimits,
}

impl BrowserArtifactStore {
    pub(super) fn in_runtime_dir(runtime_dir: &Path) -> Self {
        Self {
            directory: runtime_dir.join("browser").join("artifacts"),
            limits: BrowserArtifactLimits {
                max_file_bytes: MAX_BROWSER_ARTIFACT_BYTES,
                max_store_bytes: MAX_BROWSER_ARTIFACT_STORE_BYTES,
            },
        }
    }

    pub(super) fn reserve(
        &self,
        correlation_id: &str,
        format: &'static str,
    ) -> std::io::Result<BrowserArtifact> {
        debug_assert!(matches!(format, "png" | "pdf"));
        std::fs::create_dir_all(&self.directory)?;
        restrict_to_owner(&self.directory);
        self.sweep_if_due();
        if self.store_usage_bytes()? >= self.limits.max_store_bytes {
            return Err(store_quota_error(self.limits.max_store_bytes));
        }
        let reservation_id = canonical_reservation_id(correlation_id)?;
        let path = self.artifact_path(&reservation_id, format);
        let marker = self.reservation_marker_path(&reservation_id, format);
        let placeholder = create_private_exclusive(&path)?;
        let reservation = match create_private_exclusive(&marker) {
            Ok(reservation) => reservation,
            Err(error) => {
                drop(placeholder);
                let _ = std::fs::remove_file(&path);
                return Err(error);
            }
        };
        drop(placeholder);
        drop(reservation);
        if let Err(error) = std::fs::remove_file(&path) {
            let _ = std::fs::remove_file(&marker);
            return Err(error);
        }
        Ok(BrowserArtifact {
            path: path.to_string_lossy().into_owned(),
            format,
            mime_type: mime_type(format),
            size_bytes: 0,
            expires_at: DateTime::<Utc>::from(SystemTime::now() + ARTIFACT_TTL),
            suggested_file_name: suggested_file_name(correlation_id, format),
            reservation_id,
        })
    }

    pub(super) fn completed(
        &self,
        mut artifact: BrowserArtifact,
    ) -> Result<BrowserArtifact, BrowserArtifactCompletionError> {
        let Some((path, marker)) = self.reserved_paths(&artifact) else {
            return Err(BrowserArtifactCompletionError::InvalidReservation);
        };
        if !is_regular_file(&marker) {
            return Err(BrowserArtifactCompletionError::InvalidReservation);
        }
        let metadata = match std::fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.remove(&artifact);
                return Err(BrowserArtifactCompletionError::Missing);
            }
            Err(error) => {
                self.remove(&artifact);
                return Err(BrowserArtifactCompletionError::StoreUnavailable(
                    error.to_string(),
                ));
            }
        };
        if !metadata.file_type().is_file() {
            self.remove(&artifact);
            return Err(BrowserArtifactCompletionError::InvalidReservation);
        }
        let size_bytes = metadata.len();
        if size_bytes == 0 {
            self.remove(&artifact);
            return Err(BrowserArtifactCompletionError::Empty);
        }
        if size_bytes > self.limits.max_file_bytes {
            self.remove(&artifact);
            return Err(BrowserArtifactCompletionError::FileTooLarge {
                size_bytes,
                max_bytes: self.limits.max_file_bytes,
            });
        }
        let store_size_bytes = match self.store_usage_bytes() {
            Ok(size_bytes) => size_bytes,
            Err(error) => {
                self.remove(&artifact);
                return Err(BrowserArtifactCompletionError::StoreUnavailable(
                    error.to_string(),
                ));
            }
        };
        if store_size_bytes > self.limits.max_store_bytes {
            self.remove(&artifact);
            return Err(BrowserArtifactCompletionError::StoreQuotaExceeded {
                store_size_bytes,
                max_bytes: self.limits.max_store_bytes,
            });
        }
        artifact.size_bytes = size_bytes;
        Ok(artifact)
    }

    pub(super) fn remove(&self, artifact: &BrowserArtifact) {
        let Some((path, marker)) = self.reserved_paths(artifact) else {
            return;
        };
        if !is_regular_file(&marker) {
            return;
        }
        let _ = std::fs::remove_file(path);
        let _ = std::fs::remove_file(marker);
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
            let marker = entry.path();
            let Some((reservation_id, format)) = reservation_from_marker_path(&marker) else {
                continue;
            };
            let expired = std::fs::symlink_metadata(&marker)
                .ok()
                .filter(|metadata| metadata.file_type().is_file())
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|modified| now.duration_since(modified).ok())
                .is_some_and(|age| age > ARTIFACT_TTL);
            if expired {
                let _ = std::fs::remove_file(self.artifact_path(&reservation_id, format));
                let _ = std::fs::remove_file(marker);
            }
        }
    }

    fn store_usage_bytes(&self) -> std::io::Result<u64> {
        let mut size_bytes = 0_u64;
        for entry in std::fs::read_dir(&self.directory)? {
            let marker = entry?.path();
            let Some((reservation_id, format)) = reservation_from_marker_path(&marker) else {
                continue;
            };
            if !is_regular_file(&marker) {
                continue;
            }
            let artifact = self.artifact_path(&reservation_id, format);
            let Ok(metadata) = std::fs::symlink_metadata(artifact) else {
                continue;
            };
            if metadata.file_type().is_file() {
                size_bytes = size_bytes.saturating_add(metadata.len());
            }
        }
        Ok(size_bytes)
    }

    fn reserved_paths(&self, artifact: &BrowserArtifact) -> Option<(PathBuf, PathBuf)> {
        let reservation_id = canonical_reservation_id(&artifact.reservation_id).ok()?;
        if !matches!(artifact.format, "png" | "pdf") {
            return None;
        }
        let path = self.artifact_path(&reservation_id, artifact.format);
        if Path::new(&artifact.path) != path {
            return None;
        }
        let marker = self.reservation_marker_path(&reservation_id, artifact.format);
        Some((path, marker))
    }

    fn artifact_path(&self, reservation_id: &str, format: &str) -> PathBuf {
        self.directory.join(format!("{reservation_id}.{format}"))
    }

    fn reservation_marker_path(&self, reservation_id: &str, format: &str) -> PathBuf {
        self.directory.join(format!(
            ".{reservation_id}.{format}{RESERVATION_MARKER_SUFFIX}"
        ))
    }

    #[cfg(test)]
    fn with_limits(runtime_dir: &Path, max_file_bytes: u64, max_store_bytes: u64) -> Self {
        Self {
            directory: runtime_dir.join("browser").join("artifacts"),
            limits: BrowserArtifactLimits {
                max_file_bytes,
                max_store_bytes,
            },
        }
    }
}

fn mime_type(format: &str) -> &'static str {
    match format {
        "pdf" => "application/pdf",
        _ => "image/png",
    }
}

fn suggested_file_name(correlation_id: &str, format: &str) -> String {
    let kind = if format == "pdf" {
        "browser-page"
    } else {
        "browser-screenshot"
    };
    format!("{kind}-{correlation_id}.{format}")
}

fn sweep_is_due(marker: &Path) -> bool {
    std::fs::symlink_metadata(marker)
        .ok()
        .filter(|metadata| metadata.file_type().is_file())
        .and_then(|metadata| metadata.modified().ok())
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .is_none_or(|age| age >= CLEANUP_INTERVAL)
}

#[cfg(unix)]
fn create_private_exclusive(path: &Path) -> std::io::Result<std::fs::File> {
    use std::os::unix::fs::OpenOptionsExt as _;
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
}

#[cfg(not(unix))]
fn create_private_exclusive(path: &Path) -> std::io::Result<std::fs::File> {
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) {
    use std::os::unix::fs::PermissionsExt as _;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700));
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) {}

fn canonical_reservation_id(value: &str) -> std::io::Result<String> {
    let parsed = Uuid::parse_str(value).map_err(|_| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "browser artifact reservation id must be a UUID",
        )
    })?;
    let canonical = parsed.to_string();
    if canonical != value {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "browser artifact reservation id must use canonical UUID form",
        ));
    }
    Ok(canonical)
}

fn reservation_from_marker_path(path: &Path) -> Option<(String, &'static str)> {
    let file_name = path.file_name()?.to_str()?;
    let reservation = file_name
        .strip_prefix('.')?
        .strip_suffix(RESERVATION_MARKER_SUFFIX)?;
    let (reservation_id, format) = reservation.rsplit_once('.')?;
    let reservation_id = canonical_reservation_id(reservation_id).ok()?;
    let format = match format {
        "png" => "png",
        "pdf" => "pdf",
        _ => return None,
    };
    Some((reservation_id, format))
}

fn is_regular_file(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_file())
}

fn store_quota_error(max_bytes: u64) -> std::io::Error {
    std::io::Error::new(
        std::io::ErrorKind::QuotaExceeded,
        format!("browser artifact store reached its {max_bytes}-byte quota"),
    )
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
#[path = "browser_artifact_store_tests.rs"]
mod tests;
