//! Writes one JSON object per log record.
//!
//! JSON Lines rather than plain text because the desktop bundle merges runtime
//! and app logs into a single timeline; doing that reliably over free-form text
//! means re-parsing whatever each side happened to print.

use super::redaction::redact;
use super::rotating_writer::RotatingFileWriter;
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::fmt;
use std::io::Write;
use std::sync::{Arc, Mutex};
use tracing::field::{Field, Visit};
use tracing::{Event, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::Layer;

pub struct JsonlLayer {
    writer: Arc<Mutex<RotatingFileWriter>>,
    source: &'static str,
}

impl JsonlLayer {
    pub fn new(writer: Arc<Mutex<RotatingFileWriter>>, source: &'static str) -> Self {
        Self { writer, source }
    }
}

#[derive(Default)]
struct FieldCollector {
    message: String,
    error: Option<String>,
    extra: BTreeMap<String, String>,
}

impl FieldCollector {
    fn record(&mut self, name: &str, value: String) {
        match name {
            "message" => self.message = value,
            "error" => self.error = Some(value),
            _ => {
                self.extra.insert(name.to_string(), value);
            }
        }
    }
}

impl Visit for FieldCollector {
    fn record_debug(&mut self, field: &Field, value: &dyn fmt::Debug) {
        self.record(field.name(), format!("{value:?}"));
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        self.record(field.name(), value.to_string());
    }
}

pub fn timestamp() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

/// Builds the record separately from writing it so tests can assert the shape
/// without touching the filesystem.
pub fn build_record(
    source: &str,
    level: &str,
    logger: &str,
    message: &str,
    error: Option<&str>,
    extra: &BTreeMap<String, String>,
) -> Value {
    let mut record = Map::new();
    record.insert("ts".into(), json!(timestamp()));
    record.insert("level".into(), json!(level));
    record.insert("source".into(), json!(source));
    record.insert("logger".into(), json!(logger));
    record.insert("msg".into(), json!(redact(message)));
    if let Some(error) = error {
        record.insert("error".into(), json!(redact(error)));
    }
    for (key, value) in extra {
        record.insert(key.clone(), json!(redact(value)));
    }
    Value::Object(record)
}

impl<S: Subscriber> Layer<S> for JsonlLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let mut collector = FieldCollector::default();
        event.record(&mut collector);

        let metadata = event.metadata();
        let record = build_record(
            self.source,
            metadata.level().as_str(),
            metadata.target(),
            &collector.message,
            collector.error.as_deref(),
            &collector.extra,
        );

        let Ok(mut writer) = self.writer.lock() else {
            return;
        };
        // A failed write must stay silent: reporting it through tracing would
        // re-enter this layer and recurse.
        let _ = writeln!(writer, "{record}");
        let _ = writer.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::diagnostics::redaction::{register_secret, REDACTED};

    #[test]
    fn record_carries_the_agreed_schema() {
        let record = build_record(
            "runtime",
            "WARN",
            "alera_cli::terminal_host::server",
            "mobile gateway unavailable",
            None,
            &BTreeMap::new(),
        );
        assert_eq!(record["level"], "WARN");
        assert_eq!(record["source"], "runtime");
        assert_eq!(record["logger"], "alera_cli::terminal_host::server");
        assert_eq!(record["msg"], "mobile gateway unavailable");
        assert!(record["ts"].as_str().is_some_and(|ts| ts.ends_with('Z')));
    }

    #[test]
    fn message_and_error_are_redacted() {
        register_secret("jsonl-layer-secret-token");
        let record = build_record(
            "runtime",
            "ERROR",
            "test",
            "attach failed for jsonl-layer-secret-token",
            Some("token=jsonl-layer-secret-token"),
            &BTreeMap::new(),
        );
        assert!(!record["msg"].as_str().unwrap().contains("secret-token"));
        assert!(record["error"].as_str().unwrap().contains(REDACTED));
    }

    #[test]
    fn extra_fields_are_kept_and_redacted() {
        let mut extra = BTreeMap::new();
        extra.insert("workspaceId".to_string(), "ws-17".to_string());
        extra.insert("secret".to_string(), "password=hunter2hunter".to_string());
        let record = build_record("runtime", "INFO", "test", "spawned", None, &extra);

        assert_eq!(record["workspaceId"], "ws-17");
        assert!(!record["secret"].as_str().unwrap().contains("hunter2hunter"));
    }
}
