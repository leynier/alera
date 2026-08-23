//! Maps runtime `ERROR` records to privacy-safe Sentry events.
//!
//! This deliberately does not use `sentry-tracing`. Runtime records commonly
//! carry workspace IDs, paths, commands, and agent output as structured fields
//! or interpolated messages. Visiting those fields would make safe redaction
//! depend on every call site. This layer instead creates a new event from a
//! small allowlist of compile-time metadata and discards the record payload.

use super::sentry_reporting;
use sentry::protocol::{Event as SentryEvent, Level as SentryLevel};
use std::borrow::Cow;
use std::sync::Arc;
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::Layer;

const PANIC_TARGET: &str = "alera.panic";
const FALLBACK_LOGGER: &str = "alera.runtime";

trait EventCapture: Send + Sync {
    fn capture(&self, event: SentryEvent<'static>);
}

struct MainHubCapture;

impl EventCapture for MainHubCapture {
    fn capture(&self, event: SentryEvent<'static>) {
        sentry::Hub::main().capture_event(event);
    }
}

pub struct SentryErrorLayer {
    capture: Arc<dyn EventCapture>,
}

impl SentryErrorLayer {
    pub fn new() -> Self {
        Self {
            capture: Arc::new(MainHubCapture),
        }
    }

    #[cfg(test)]
    fn with_capture(capture: Arc<dyn EventCapture>) -> Self {
        Self { capture }
    }
}

impl Default for SentryErrorLayer {
    fn default() -> Self {
        Self::new()
    }
}

fn safe_logger(target: &str) -> String {
    let is_runtime_target =
        target == "alera.host" || target == "alera.synthetic" || target.starts_with("alera_cli::");
    let has_safe_characters = target
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b':' | b'.'));
    if is_runtime_target && has_safe_characters && target.len() <= 160 {
        target.to_string()
    } else {
        FALLBACK_LOGGER.to_string()
    }
}

fn mapped_event(target: &str) -> SentryEvent<'static> {
    let logger = safe_logger(target);
    SentryEvent {
        level: SentryLevel::Error,
        fingerprint: Cow::Owned(vec![
            Cow::Borrowed("runtime-error"),
            Cow::Owned(logger.clone()),
        ]),
        message: Some("runtime error".to_string()),
        logger: Some(logger),
        ..Default::default()
    }
}

impl<S: Subscriber> Layer<S> for SentryErrorLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let metadata = event.metadata();
        if metadata.level() != &Level::ERROR
            || metadata.target() == PANIC_TARGET
            || !sentry_reporting::is_enabled()
        {
            return;
        }
        self.capture.capture(mapped_event(metadata.target()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sentry::protocol::{Envelope, Event as CapturedEvent};
    use sentry::{Client, Transport};
    use std::sync::Mutex;
    use tracing_subscriber::layer::SubscriberExt;

    #[derive(Default)]
    struct MemoryTransport {
        events: Mutex<Vec<CapturedEvent<'static>>>,
    }

    impl MemoryTransport {
        fn take_events(&self) -> Vec<CapturedEvent<'static>> {
            std::mem::take(&mut *self.events.lock().unwrap())
        }
    }

    impl Transport for MemoryTransport {
        fn send_envelope(&self, envelope: Envelope) {
            if let Some(event) = envelope.event() {
                self.events.lock().unwrap().push(event.clone());
            }
        }
    }

    struct ClientCapture {
        client: Arc<Client>,
    }

    impl EventCapture for ClientCapture {
        fn capture(&self, event: SentryEvent<'static>) {
            self.client.capture_event(event, None);
        }
    }

    fn test_layer(enabled: bool) -> (SentryErrorLayer, Arc<MemoryTransport>, Arc<Client>) {
        sentry_reporting::set_enabled(enabled);
        let transport = Arc::new(MemoryTransport::default());
        let mut options = sentry_reporting::client_options();
        options.integrations.clear();
        options.transport = Some(Arc::new(transport.clone()));
        let client = Arc::new(Client::from((sentry_reporting::RUNTIME_DSN, options)));
        let capture = Arc::new(ClientCapture {
            client: client.clone(),
        });
        (SentryErrorLayer::with_capture(capture), transport, client)
    }

    fn emit(layer: SentryErrorLayer, emit_events: impl FnOnce()) {
        let subscriber = tracing_subscriber::registry().with(layer);
        tracing::subscriber::with_default(subscriber, emit_events);
    }

    #[test]
    fn disabled_error_is_not_sent() {
        let _guard = sentry_reporting::test_serial_guard();
        let (layer, transport, _) = test_layer(false);
        emit(layer, || tracing::error!("disabled runtime error"));
        assert!(transport.take_events().is_empty());
    }

    #[test]
    fn enabled_error_is_sent_with_runtime_context() {
        let _guard = sentry_reporting::test_serial_guard();
        let (layer, transport, _) = test_layer(true);
        emit(layer, || tracing::error!("operational runtime failure"));
        let events = transport.take_events();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].message.as_deref(), Some("runtime error"));
        assert_eq!(
            events[0].tags.get("surface").map(String::as_str),
            Some("runtime")
        );
        assert!(events[0].tags.contains_key("runtime_protocol"));
        assert!(events[0].contexts.contains_key("alera_versions"));
    }

    #[test]
    fn warning_and_info_are_not_sent() {
        let _guard = sentry_reporting::test_serial_guard();
        let (layer, transport, _) = test_layer(true);
        emit(layer, || {
            tracing::info!("ordinary runtime status");
            tracing::warn!("recoverable runtime warning");
        });
        assert!(transport.take_events().is_empty());
    }

    #[test]
    fn sensitive_message_and_structured_fields_are_not_sent() {
        let _guard = sentry_reporting::test_serial_guard();
        let (layer, transport, _) = test_layer(true);
        emit(layer, || {
            tracing::error!(
                path = "/Users/private/customer/repository",
                workspace_id = "ws-sensitive-42",
                command = "deploy --token secret-value-123",
                token = "secret-value-123",
                "failed in /Users/private/customer/repository for ws-sensitive-42"
            );
        });
        let events = transport.take_events();
        assert_eq!(events.len(), 1);
        let serialized = serde_json::to_string(&events[0]).unwrap();
        for sensitive in [
            "/Users/private/customer/repository",
            "ws-sensitive-42",
            "deploy --token",
            "secret-value-123",
        ] {
            assert!(!serialized.contains(sensitive));
        }
    }

    #[test]
    fn panic_log_does_not_duplicate_the_panic_event() {
        let _guard = sentry_reporting::test_serial_guard();
        let (layer, transport, client) = test_layer(true);
        let mut panic = SentryEvent {
            level: SentryLevel::Fatal,
            ..Default::default()
        };
        panic.exception.values.push(sentry::protocol::Exception {
            ty: "panic".to_string(),
            value: Some("token=panic-secret-value".to_string()),
            ..Default::default()
        });
        client.capture_event(panic, None);
        emit(layer, || {
            tracing::error!(
                target: PANIC_TARGET,
                path = "/private/panic/path",
                "runtime host panicked: token=panic-secret-value"
            );
        });
        let events = transport.take_events();
        assert_eq!(events.len(), 1);
        let serialized = serde_json::to_string(&events[0]).unwrap();
        assert!(!serialized.contains("panic-secret-value"));
        assert!(!serialized.contains("/private/panic/path"));
    }
}
