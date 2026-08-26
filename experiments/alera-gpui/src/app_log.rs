use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Mutex, OnceLock};

use chrono::{SecondsFormat, Utc};
use regex::Regex;
use sentry::protocol::Event;
use sentry::ClientOptions;
use serde_json::json;

const MAX_BYTES: u64 = 5 * 1024 * 1024;
const MAX_FILES: usize = 5;
const REDACTED: &str = "[redacted]";

static WRITER: OnceLock<Mutex<RotatingFileWriter>> = OnceLock::new();
static DIRECTORY: OnceLock<PathBuf> = OnceLock::new();
static LEVEL: AtomicU8 = AtomicU8::new(LogLevel::Info as u8);
static CRASH_REPORTING_ENABLED: AtomicBool = AtomicBool::new(false);

const DESKTOP_SENTRY_DSN: &str =
    "https://78d67dfb2e865b558f8ab133546d4ec4@o4511816353644544.ingest.us.sentry.io/4511816381497344";

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum LogLevel {
    Error = 0,
    Warning = 1,
    Info = 2,
    Debug = 3,
}

impl LogLevel {
    fn label(self) -> &'static str {
        match self {
            Self::Error => "ERROR",
            Self::Warning => "WARNING",
            Self::Info => "INFO",
            Self::Debug => "DEBUG",
        }
    }
}

pub fn configure(directory: PathBuf) {
    let _ = DIRECTORY.set(directory.clone());
    let _ = WRITER.set(Mutex::new(RotatingFileWriter::new(
        directory, "alera", MAX_BYTES, MAX_FILES,
    )));
    info("alera_gpui", "application logging initialized");
}

pub fn install_panic_hook() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        error("panic", &info.to_string());
        flush();
        previous(info);
    }));
}

pub fn init_crash_reporting(enabled: bool) -> sentry::ClientInitGuard {
    set_crash_reporting_enabled(enabled);
    let mut options = ClientOptions::default();
    options.release = sentry::release_name!();
    options.environment = Some(
        std::env::var("ALERA_FLAVOR")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "release".to_string())
            .into(),
    );
    options.send_default_pii = false;
    options.before_send = Some(std::sync::Arc::new(|event| {
        CRASH_REPORTING_ENABLED
            .load(Ordering::Relaxed)
            .then(|| redact_event(event))
    }));
    sentry::init((DESKTOP_SENTRY_DSN, options))
}

pub fn set_crash_reporting_enabled(enabled: bool) {
    CRASH_REPORTING_ENABLED.store(enabled, Ordering::Relaxed);
}

pub fn directory() -> Option<&'static Path> {
    DIRECTORY.get().map(PathBuf::as_path)
}

pub fn set_level(value: &str) {
    let level = match value {
        "Error" => LogLevel::Error,
        "Warning" => LogLevel::Warning,
        "Debug" => LogLevel::Debug,
        _ => LogLevel::Info,
    };
    LEVEL.store(level as u8, Ordering::Relaxed);
}

pub fn error(logger: &str, message: &str) {
    write(LogLevel::Error, logger, message);
}

#[allow(dead_code)]
pub fn warning(logger: &str, message: &str) {
    write(LogLevel::Warning, logger, message);
}

pub fn info(logger: &str, message: &str) {
    write(LogLevel::Info, logger, message);
}

#[allow(dead_code)]
pub fn debug(logger: &str, message: &str) {
    write(LogLevel::Debug, logger, message);
}

pub fn flush() {
    if let Some(writer) = WRITER.get() {
        if let Ok(mut writer) = writer.lock() {
            let _ = writer.flush();
        }
    }
}

fn write(level: LogLevel, logger: &str, message: &str) {
    if level as u8 > LEVEL.load(Ordering::Relaxed) {
        return;
    }
    let record = json!({
        "ts": Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
        "level": level.label(),
        "source": "app",
        "logger": logger,
        "msg": redact(message),
    });
    if let Some(writer) = WRITER.get() {
        if let Ok(mut writer) = writer.lock() {
            let _ = writeln!(writer, "{record}");
            let _ = writer.flush();
        }
    }
}

fn redact(input: &str) -> String {
    let keyed = keyed_secret_pattern().replace_all(input, |captures: &regex::Captures<'_>| {
        format!("{}={REDACTED}", &captures[1])
    });
    bearer_pattern()
        .replace_all(&keyed, |_: &regex::Captures<'_>| {
            format!("Bearer {REDACTED}")
        })
        .into_owned()
}

fn redact_event(mut event: Event<'static>) -> Event<'static> {
    if let Some(message) = event.message.take() {
        event.message = Some(redact(&message));
    }
    if let Some(logentry) = event.logentry.as_mut() {
        logentry.message = redact(&logentry.message);
    }
    for exception in event.exception.values.iter_mut() {
        if let Some(value) = exception.value.as_ref() {
            exception.value = Some(redact(value));
        }
    }
    for breadcrumb in event.breadcrumbs.values.iter_mut() {
        if let Some(message) = breadcrumb.message.as_ref() {
            breadcrumb.message = Some(redact(message));
        }
    }
    event
}

fn keyed_secret_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(
            r#"(?i)\b(token|secret|password|passwd|api[_-]?key|authorization|deviceToken)\b"?\s*[:=]\s*"?([^\s",;}\)]+)"#,
        )
        .expect("valid keyed secret pattern")
    })
}

fn bearer_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN
        .get_or_init(|| Regex::new(r"(?i)\bbearer\s+([A-Za-z0-9._\-+/=]+)").expect("valid bearer"))
}

struct RotatingFileWriter {
    directory: PathBuf,
    base_name: String,
    max_bytes: u64,
    max_files: usize,
    file: Option<File>,
    written: u64,
}

impl RotatingFileWriter {
    fn new(
        directory: PathBuf,
        base_name: impl Into<String>,
        max_bytes: u64,
        max_files: usize,
    ) -> Self {
        Self {
            directory,
            base_name: base_name.into(),
            max_bytes: max_bytes.max(1),
            max_files: max_files.max(1),
            file: None,
            written: 0,
        }
    }

    fn path_for(&self, index: usize) -> PathBuf {
        let name = if index == 0 {
            format!("{}.log", self.base_name)
        } else {
            format!("{}.{index}.log", self.base_name)
        };
        self.directory.join(name)
    }

    fn ensure_open(&mut self) -> io::Result<()> {
        if self.file.is_some() {
            return Ok(());
        }
        fs::create_dir_all(&self.directory)?;
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.path_for(0))?;
        self.written = file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        self.file = Some(file);
        Ok(())
    }

    fn rotate(&mut self) -> io::Result<()> {
        self.file = None;
        self.written = 0;
        let oldest = self.path_for(self.max_files - 1);
        if oldest.exists() {
            let _ = fs::remove_file(oldest);
        }
        for index in (1..self.max_files.saturating_sub(1)).rev() {
            let source = self.path_for(index);
            if source.exists() {
                let _ = fs::rename(source, self.path_for(index + 1));
            }
        }
        if self.max_files > 1 {
            let active = self.path_for(0);
            if active.exists() {
                let _ = fs::rename(active, self.path_for(1));
            }
        } else {
            let _ = fs::remove_file(self.path_for(0));
        }
        self.ensure_open()
    }
}

impl Write for RotatingFileWriter {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.ensure_open()?;
        if self.written > 0 && self.written.saturating_add(buffer.len() as u64) > self.max_bytes {
            self.rotate()?;
        }
        let file = self
            .file
            .as_mut()
            .ok_or_else(|| io::Error::other("app log file is not open"))?;
        let written = file.write(buffer)?;
        self.written = self.written.saturating_add(written as u64);
        Ok(written)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.as_mut().map_or(Ok(()), Write::flush)
    }
}

#[cfg(test)]
mod tests {
    use super::{redact, redact_event};
    use sentry::protocol::Event;

    #[test]
    fn redacts_keyed_and_bearer_secrets() {
        let value = redact("token=abcdef123456 Bearer eyJ.payload");
        assert!(!value.contains("abcdef123456"));
        assert!(!value.contains("eyJ.payload"));
        assert!(value.contains("[redacted]"));
    }

    #[test]
    fn redacts_crash_event_messages() {
        let event = Event {
            message: Some("failed with password=hunter2hunter".to_string()),
            ..Default::default()
        };
        let event = redact_event(event);
        let message = event.message.expect("redacted message");
        assert!(!message.contains("hunter2hunter"));
        assert!(message.contains("[redacted]"));
    }
}
