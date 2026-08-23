//! Runtime host diagnostics: file logging, redaction, and crash reporting.
//!
//! The sidecar is spawned detached (`ProcessStartMode.detached` from the app,
//! `Stdio::null()` from the CLI), so anything printed to stderr is written to a
//! closed descriptor. A log file is the only channel that survives.

pub mod jsonl_layer;
pub mod panic_hook;
pub mod redaction;
pub mod rotating_writer;
pub mod sentry_error_layer;
pub mod sentry_reporting;

use jsonl_layer::JsonlLayer;
use rotating_writer::{RotatingFileWriter, DEFAULT_MAX_BYTES, DEFAULT_MAX_FILES};
use sentry_error_layer::SentryErrorLayer;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::EnvFilter;

/// Environment override for the log level, following the `ALERA_HOST_*`
/// convention already used by the makefile's debug knobs.
pub const LOG_LEVEL_ENV: &str = "ALERA_HOST_LOG";
pub const LOG_DIRECTORY_NAME: &str = "logs";
pub const LOG_BASE_NAME: &str = "runtime";
pub const DEFAULT_LOG_LEVEL: &str = "info";

static LOG_DIRECTORY: OnceLock<PathBuf> = OnceLock::new();

pub struct DiagnosticsConfig {
    pub runtime_dir: PathBuf,
    pub level: String,
    pub max_bytes: u64,
    pub max_files: usize,
}

impl DiagnosticsConfig {
    pub fn new(runtime_dir: impl Into<PathBuf>) -> Self {
        Self {
            runtime_dir: runtime_dir.into(),
            level: DEFAULT_LOG_LEVEL.to_string(),
            max_bytes: DEFAULT_MAX_BYTES,
            max_files: DEFAULT_MAX_FILES,
        }
    }

    pub fn with_level(mut self, level: impl Into<String>) -> Self {
        let level = level.into();
        if !level.trim().is_empty() {
            self.level = level;
        }
        self
    }

    pub fn log_directory(&self) -> PathBuf {
        self.runtime_dir.join(LOG_DIRECTORY_NAME)
    }
}

/// The directory the host writes logs to, once initialized.
///
/// Exposed through `status.get` so the desktop can collect runtime logs into a
/// diagnostics bundle without re-deriving the path resolution rules.
pub fn log_directory() -> Option<&'static Path> {
    LOG_DIRECTORY.get().map(PathBuf::as_path)
}

fn env_filter(level: &str) -> EnvFilter {
    EnvFilter::try_from_env(LOG_LEVEL_ENV).unwrap_or_else(|_| EnvFilter::new(level))
}

/// Initializes file logging and the panic hook.
///
/// Safe to call more than once: the second call leaves the existing subscriber
/// in place rather than panicking, which matters because tests and the CLI can
/// both reach this path in the same process.
pub fn init(config: DiagnosticsConfig) -> PathBuf {
    let directory = config.log_directory();
    let writer = Arc::new(Mutex::new(RotatingFileWriter::new(
        &directory,
        LOG_BASE_NAME,
        config.max_bytes,
        config.max_files,
    )));

    // Keep stderr output when a terminal is attached so `make host-debug` still
    // shows everything in the foreground.
    let stderr_layer = std::io::stderr()
        .is_terminal()
        .then(|| tracing_subscriber::fmt::layer().with_writer(std::io::stderr));

    let initialized = tracing_subscriber::registry()
        .with(env_filter(&config.level))
        .with(JsonlLayer::new(writer, "runtime"))
        .with(SentryErrorLayer::new())
        .with(stderr_layer)
        .try_init()
        .is_ok();

    if initialized {
        panic_hook::install();
    }
    let _ = LOG_DIRECTORY.set(directory.clone());
    directory
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_directory_sits_under_the_runtime_profile() {
        let config = DiagnosticsConfig::new(Path::new("/tmp/profile"));
        assert_eq!(
            config.log_directory(),
            Path::new("/tmp/profile").join(LOG_DIRECTORY_NAME)
        );
    }

    #[test]
    fn blank_levels_fall_back_to_the_default() {
        let config = DiagnosticsConfig::new("/tmp/profile").with_level("   ");
        assert_eq!(config.level, DEFAULT_LOG_LEVEL);
    }

    #[test]
    fn explicit_levels_are_kept() {
        let config = DiagnosticsConfig::new("/tmp/profile").with_level("debug");
        assert_eq!(config.level, "debug");
    }
}
