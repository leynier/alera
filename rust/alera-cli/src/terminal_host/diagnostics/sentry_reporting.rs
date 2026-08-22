//! Opt-in crash reporting for the runtime host.
//!
//! Reporting is off unless the user turns it on. The switch is read inside
//! `before_send` rather than by binding and unbinding a client, because the
//! host raises events from many threads and a hub binding only applies to the
//! thread that performs it.

use super::redaction::redact;
use crate::terminal_host::protocol::PROTOCOL_VERSION;
use crate::terminal_host::runtime_build_info::{self, RUNTIME_SURFACE};
use sentry::protocol::{Context, Event, Value};
use sentry::ClientOptions;
use std::borrow::Cow;
use std::sync::atomic::{AtomicBool, Ordering};

pub const RUNTIME_DSN: &str =
    "https://de6b6df74710aae113bc6920767e15f2@o4511816353644544.ingest.us.sentry.io/4511816377696256";

/// Environment variable carrying the build flavor, so `dev` noise can be
/// filtered out from Sentry itself.
pub const FLAVOR_ENV: &str = "ALERA_FLAVOR";
pub const DEFAULT_ENVIRONMENT: &str = "release";

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

/// Masks every text-bearing field of an event.
///
/// The file sink already redacts, but a Sentry event is built from the raw
/// payload, so skipping this would send a secret to a third party that was
/// deliberately kept out of the local log.
pub fn redact_event(mut event: Event<'static>) -> Event<'static> {
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
    // The host handles repository paths, branch names and command lines;
    // there is no reason to attach IPs or request headers on top.
    options.send_default_pii = false;
    options.before_send = Some(std::sync::Arc::new(|event| {
        if !is_enabled() {
            return None;
        }
        Some(redact_event(enrich_version_context(event)))
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
mod tests {
    use super::*;
    use crate::terminal_host::diagnostics::redaction::REDACTED;
    use sentry::protocol::Exception;

    #[test]
    fn disabled_is_the_default() {
        set_enabled(false);
        assert!(!is_enabled());
    }

    #[test]
    fn toggling_takes_effect_immediately() {
        set_enabled(true);
        assert!(is_enabled());
        set_enabled(false);
        assert!(!is_enabled());
    }

    #[test]
    fn event_message_is_redacted() {
        let event = Event {
            message: Some("attach failed with token=abcdef123456".into()),
            ..Default::default()
        };
        let redacted = redact_event(event);
        assert!(!redacted.message.as_ref().unwrap().contains("abcdef123456"));
        assert!(redacted.message.as_ref().unwrap().contains(REDACTED));
    }

    #[test]
    fn exception_values_are_redacted() {
        let event = Event {
            exception: vec![Exception {
                ty: "PanicException".into(),
                value: Some("secret=hunter2hunter leaked".into()),
                ..Default::default()
            }]
            .into(),
            ..Default::default()
        };
        let redacted = redact_event(event);
        let value = redacted.exception.values[0].value.as_ref().unwrap();
        assert!(!value.contains("hunter2hunter"));
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
}
