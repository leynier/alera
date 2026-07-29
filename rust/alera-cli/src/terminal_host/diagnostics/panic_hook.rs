//! Records a panic before the process dies.
//!
//! Without this a panic in the actor loop leaves nothing behind at all: the
//! sidecar is spawned detached with its stderr pointed at null, so the default
//! panic output goes to a closed descriptor and the only visible trace is a
//! runtime that stopped answering.

use std::backtrace::Backtrace;
use std::panic::PanicHookInfo;

pub fn panic_message(info: &PanicHookInfo<'_>) -> String {
    if let Some(message) = info.payload().downcast_ref::<&str>() {
        return (*message).to_string();
    }
    if let Some(message) = info.payload().downcast_ref::<String>() {
        return message.clone();
    }
    "panic with a non-string payload".to_string()
}

pub fn panic_location(info: &PanicHookInfo<'_>) -> String {
    info.location()
        .map(|location| {
            format!(
                "{}:{}:{}",
                location.file(),
                location.line(),
                location.column()
            )
        })
        .unwrap_or_else(|| "unknown".to_string())
}

/// Installs the logging panic hook, chaining whatever hook was already set.
///
/// This must run *before* `sentry::init`, whose panic integration also chains
/// the previous hook: installing in that order means a panic reaches the local
/// log file even when crash reporting is disabled or its upload fails.
pub fn install() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let backtrace = Backtrace::force_capture();
        tracing::error!(
            target: "alera.panic",
            location = %panic_location(info),
            backtrace = %backtrace,
            "runtime host panicked: {}",
            panic_message(info)
        );
        previous(info);
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_str_payloads() {
        let message = std::panic::catch_unwind(|| {
            std::panic::set_hook(Box::new(|info| {
                assert_eq!(panic_message(info), "boom");
            }));
            panic!("boom");
        });
        let _ = std::panic::take_hook();
        assert!(message.is_err());
    }

    #[test]
    fn formatted_payloads_become_owned_strings() {
        let captured = std::sync::Arc::new(std::sync::Mutex::new(String::new()));
        let sink = captured.clone();
        std::panic::set_hook(Box::new(move |info| {
            *sink.lock().unwrap() = panic_message(info);
        }));
        let result = std::panic::catch_unwind(|| panic!("value was {}", 42));
        let _ = std::panic::take_hook();

        assert!(result.is_err());
        assert_eq!(captured.lock().unwrap().as_str(), "value was 42");
    }
}
