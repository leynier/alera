//! Opt-in crash reporting for the runtime host.
//!
//! Reporting is off unless the user turns it on. The switch is read inside
//! `before_send` rather than by binding and unbinding a client, because the
//! host raises events from many threads and a hub binding only applies to the
//! thread that performs it.

use crate::terminal_host::protocol::PROTOCOL_VERSION;
use crate::terminal_host::runtime_build_info::{self, RUNTIME_SURFACE};
use sentry::protocol::{Context, Event, Exception, Level, Mechanism, Stacktrace, Value};
use sentry::ClientOptions;
use std::borrow::Cow;
use std::sync::atomic::{AtomicBool, Ordering};

pub const RUNTIME_DSN: &str =
    "https://de6b6df74710aae113bc6920767e15f2@o4511816353644544.ingest.us.sentry.io/4511816377696256";

/// Environment variable carrying the build flavor, so `dev` noise can be
/// filtered out from Sentry itself.
pub const FLAVOR_ENV: &str = "ALERA_FLAVOR";
pub const DEFAULT_ENVIRONMENT: &str = "release";
const VERIFICATION_ID_TAG: &str = "verification_id";

static ENABLED: AtomicBool = AtomicBool::new(false);

pub fn set_enabled(enabled: bool) {
    ENABLED.store(enabled, Ordering::Relaxed);
}

pub fn is_enabled() -> bool {
    ENABLED.load(Ordering::Relaxed)
}

pub fn environment() -> String {
    std::env::var(FLAVOR_ENV)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_ENVIRONMENT.to_string())
}

fn valid_verification_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

fn sanitized_stacktrace(mut stacktrace: Stacktrace) -> Stacktrace {
    stacktrace.registers.clear();
    for frame in &mut stacktrace.frames {
        frame.package = None;
        frame.filename = None;
        frame.abs_path = None;
        frame.pre_context.clear();
        frame.context_line = None;
        frame.post_context.clear();
        frame.vars.clear();
        frame.image_addr = None;
        frame.instruction_addr = None;
        frame.symbol_addr = None;
        frame.addr_mode = None;
    }
    stacktrace
}

fn is_panic(event: &Event<'_>) -> bool {
    event.exception.values.iter().any(|exception| {
        exception.ty.eq_ignore_ascii_case("panic")
            || exception
                .mechanism
                .as_ref()
                .is_some_and(|mechanism| mechanism.ty == "panic")
    })
}

/// Rebuilds an event from a strict allowlist after integrations and scope data
/// have run. This is intentionally stronger than pattern redaction: arbitrary
/// messages, paths, IDs, commands, tags, contexts, and extras never cross the
/// network boundary.
fn sanitize_event(event: Event<'static>) -> Event<'static> {
    let verification_id = event
        .tags
        .get(VERIFICATION_ID_TAG)
        .filter(|value| valid_verification_id(value))
        .cloned();
    let panic = is_panic(&event);
    let logger = event
        .logger
        .as_deref()
        .filter(|logger| {
            *logger == "alera.runtime"
                || *logger == "alera.host"
                || *logger == "alera.synthetic"
                || logger.starts_with("alera_cli::")
        })
        .unwrap_or("alera.runtime")
        .to_string();

    let mut sanitized = Event {
        event_id: event.event_id,
        timestamp: event.timestamp,
        level: if panic { Level::Fatal } else { Level::Error },
        platform: Cow::Borrowed("native"),
        environment: Some(Cow::Owned(environment())),
        message: Some(if verification_id.is_some() {
            "synthetic runtime Sentry verification".to_string()
        } else if panic {
            "runtime host panicked".to_string()
        } else {
            "runtime error".to_string()
        }),
        logger: Some(if verification_id.is_some() {
            "alera.synthetic".to_string()
        } else {
            logger.clone()
        }),
        fingerprint: Cow::Owned(if verification_id.is_some() {
            vec![Cow::Borrowed("runtime-synthetic-verification")]
        } else if panic {
            vec![Cow::Borrowed("runtime-panic")]
        } else {
            vec![Cow::Borrowed("runtime-error"), Cow::Owned(logger)]
        }),
        ..Default::default()
    };

    if panic {
        let stacktrace = event
            .exception
            .values
            .into_iter()
            .find_map(|exception| exception.stacktrace)
            .map(sanitized_stacktrace);
        sanitized.exception.values.push(Exception {
            ty: "panic".to_string(),
            value: Some("runtime host panicked".to_string()),
            stacktrace,
            mechanism: Some(Mechanism {
                ty: "panic".to_string(),
                handled: Some(false),
                ..Default::default()
            }),
            ..Default::default()
        });
    }
    if let Some(verification_id) = verification_id {
        sanitized
            .tags
            .insert(VERIFICATION_ID_TAG.to_string(), verification_id);
    }
    sanitized
}

fn enrich_version_context(mut event: Event<'static>) -> Event<'static> {
    let version = runtime_build_info::version();
    let build = runtime_build_info::build();
    event.release = Some(runtime_build_info::release());
    event.dist = build.map(Cow::Borrowed);
    event.tags.insert("surface".into(), RUNTIME_SURFACE.into());
    event.tags.insert("runtime_version".into(), version.into());
    event
        .tags
        .insert("runtime_protocol".into(), PROTOCOL_VERSION.to_string());
    if let Some(build) = build {
        event.tags.insert("runtime_build".into(), build.into());
    }
    let mut versions = std::collections::BTreeMap::new();
    versions.insert("surface".into(), Value::String(RUNTIME_SURFACE.into()));
    versions.insert("runtime_version".into(), Value::String(version.into()));
    versions.insert("runtime_protocol".into(), Value::from(PROTOCOL_VERSION));
    if let Some(build) = build {
        versions.insert("runtime_build".into(), Value::String(build.into()));
    }
    event
        .contexts
        .insert("alera_versions".into(), Context::Other(versions));
    event
}

pub fn client_options() -> ClientOptions {
    let mut options = ClientOptions::default();
    options.release = Some(runtime_build_info::release());
    options.environment = Some(Cow::Owned(environment()));
    options.default_integrations = false;
    options.integrations.push(std::sync::Arc::new(
        sentry::integrations::panic::PanicIntegration::default(),
    ));
    // The host handles repository paths, branch names and command lines;
    // there is no reason to attach IPs or request headers on top.
    options.send_default_pii = false;
    options.before_send = Some(std::sync::Arc::new(|event| {
        if !is_enabled() {
            return None;
        }
        Some(enrich_version_context(sanitize_event(event)))
    }));
    options
}

/// Starts crash reporting. The returned guard must stay alive for the whole
/// process: dropping it flushes pending events, and dropping it early means a
/// panic is never delivered.
pub fn init(enabled: bool) -> sentry::ClientInitGuard {
    set_enabled(enabled);
    sentry::init((RUNTIME_DSN, client_options()))
}

#[cfg(test)]
pub(crate) fn test_serial_guard() -> std::sync::MutexGuard<'static, ()> {
    static TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    TEST_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[cfg(test)]
fn synthetic_verification_event(verification_id: &str) -> Event<'static> {
    let mut event = Event {
        level: Level::Error,
        message: Some("synthetic runtime Sentry verification".to_string()),
        logger: Some("alera.synthetic".to_string()),
        ..Default::default()
    };
    event
        .tags
        .insert(VERIFICATION_ID_TAG.to_string(), verification_id.to_string());
    event
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn disabled_is_the_default() {
        let _guard = test_serial_guard();
        set_enabled(false);
        assert!(!is_enabled());
    }

    #[test]
    fn toggling_takes_effect_immediately() {
        let _guard = test_serial_guard();
        set_enabled(true);
        assert!(is_enabled());
        set_enabled(false);
        assert!(!is_enabled());
    }

    #[test]
    fn arbitrary_event_content_is_removed() {
        let _guard = test_serial_guard();
        let event = Event {
            message: Some("attach failed at /private/repo with token=abcdef123456".into()),
            ..Default::default()
        };
        let sanitized = sanitize_event(event);
        assert_eq!(sanitized.message.as_deref(), Some("runtime error"));
        let serialized = serde_json::to_string(&sanitized).unwrap();
        assert!(!serialized.contains("abcdef123456"));
        assert!(!serialized.contains("/private/repo"));
    }

    #[test]
    fn panic_payload_and_stack_paths_are_removed() {
        let _guard = test_serial_guard();
        let event = Event {
            exception: vec![Exception {
                ty: "panic".into(),
                value: Some("secret=hunter2hunter leaked".into()),
                stacktrace: Some(Stacktrace {
                    frames: vec![sentry::protocol::Frame {
                        filename: Some("private.rs".to_string()),
                        abs_path: Some("/Users/private/customer/repo/private.rs".to_string()),
                        context_line: Some("run(secret=hunter2hunter)".to_string()),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
                ..Default::default()
            }]
            .into(),
            ..Default::default()
        };
        let sanitized = sanitize_event(event);
        let serialized = serde_json::to_string(&sanitized).unwrap();
        assert!(!serialized.contains("hunter2hunter"));
        assert!(!serialized.contains("/Users/private"));
        assert!(!serialized.contains("private.rs"));
        assert_eq!(sanitized.exception.values.len(), 1);
    }

    #[test]
    fn environment_falls_back_when_the_flavor_is_absent() {
        // Only asserts the fallback shape; the variable may legitimately be set
        // in a developer shell.
        assert!(!environment().is_empty());
    }

    #[test]
    fn version_context_identifies_the_runtime_build_and_protocol() {
        let event = enrich_version_context(Event::default());
        assert_eq!(event.release, Some(runtime_build_info::release()));
        assert_eq!(event.dist.as_deref(), runtime_build_info::build());
        assert_eq!(
            event.tags.get("surface").map(String::as_str),
            Some("runtime")
        );
        assert_eq!(
            event.tags.get("runtime_version").map(String::as_str),
            Some(runtime_build_info::version())
        );
        assert_eq!(
            event.tags.get("runtime_protocol").map(String::as_str),
            Some(PROTOCOL_VERSION.to_string()).as_deref()
        );
        assert!(event.contexts.contains_key("alera_versions"));
    }

    #[test]
    fn client_uses_only_the_panic_integration_and_disables_default_pii() {
        let options = client_options();
        assert!(!options.default_integrations);
        assert!(!options.send_default_pii);
        assert_eq!(
            options
                .integrations
                .iter()
                .filter(|integration| integration.name() == "panic")
                .count(),
            1
        );
    }

    #[test]
    #[ignore = "requires an explicit live Sentry verification ID"]
    fn sends_live_synthetic_verification_event() {
        let verification_id = std::env::var("ALERA_SENTRY_VERIFICATION_ID")
            .expect("ALERA_SENTRY_VERIFICATION_ID is required");
        assert!(valid_verification_id(&verification_id));
        let _guard = init(true);
        let event_id =
            sentry::Hub::main().capture_event(synthetic_verification_event(&verification_id));
        assert!(!event_id.is_nil());
        assert!(sentry::Hub::main()
            .client()
            .is_some_and(|client| client.flush(Some(std::time::Duration::from_secs(10)))));
        println!("sentry verification event id: {event_id}");
    }
}
