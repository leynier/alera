//! Masks secrets before anything reaches a log file or an error report.
//!
//! Redaction lives in the sink rather than at the call sites on purpose: a
//! diagnostics bundle is meant to be shared, and a call site that forgets to
//! mask is indistinguishable from one that had nothing to mask.

use regex::Regex;
use std::sync::{OnceLock, RwLock};

pub const REDACTED: &str = "[redacted]";

/// Values below this length are not worth registering: short strings collide
/// with ordinary words and would mask unrelated text.
const MIN_REGISTERED_SECRET_LEN: usize = 8;

fn keyed_secret_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(
            r#"(?i)\b(token|secret|password|passwd|api[_-]?key|authorization|deviceToken)\b"?\s*[:=]\s*"?([^\s",;}\)]+)"#,
        )
        .expect("keyed secret pattern is valid")
    })
}

fn bearer_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN
        .get_or_init(|| Regex::new(r"(?i)\bbearer\s+([A-Za-z0-9._\-+/=]+)").expect("valid pattern"))
}

fn registered_secrets() -> &'static RwLock<Vec<String>> {
    static SECRETS: OnceLock<RwLock<Vec<String>>> = OnceLock::new();
    SECRETS.get_or_init(|| RwLock::new(Vec::new()))
}

/// Registers a literal value that must never appear in output.
///
/// The host knows its own control token and device tokens, so masking the exact
/// value is stronger than any pattern: it catches the token even when it is
/// logged without a recognizable key next to it.
pub fn register_secret(value: &str) {
    let trimmed = value.trim();
    if trimmed.len() < MIN_REGISTERED_SECRET_LEN {
        return;
    }
    let Ok(mut secrets) = registered_secrets().write() else {
        return;
    };
    if secrets.iter().any(|existing| existing == trimmed) {
        return;
    }
    secrets.push(trimmed.to_string());
}

/// Replaces every known secret in `input` with [`REDACTED`].
pub fn redact(input: &str) -> String {
    let mut output = input.to_string();

    if let Ok(secrets) = registered_secrets().read() {
        for secret in secrets.iter() {
            if output.contains(secret.as_str()) {
                output = output.replace(secret.as_str(), REDACTED);
            }
        }
    }

    output = keyed_secret_pattern()
        .replace_all(&output, |caps: &regex::Captures<'_>| {
            format!("{}={REDACTED}", &caps[1])
        })
        .into_owned();

    bearer_pattern()
        .replace_all(&output, |_: &regex::Captures<'_>| {
            format!("Bearer {REDACTED}")
        })
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masks_keyed_secrets_regardless_of_separator_or_quoting() {
        let redacted = redact(r#"connecting token=abc123def456 and "secret": "hunter2hunter""#);
        assert!(!redacted.contains("abc123def456"));
        assert!(!redacted.contains("hunter2hunter"));
        assert!(redacted.contains(REDACTED));
    }

    #[test]
    fn masks_bearer_headers() {
        let redacted = redact("authorization header was Bearer eyJhbGciOiJIUzI1NiJ9.payload");
        assert!(!redacted.contains("eyJhbGciOiJIUzI1NiJ9.payload"));
    }

    #[test]
    fn masks_registered_literal_even_without_a_key_next_to_it() {
        register_secret("s3cret-control-token-value");
        let redacted = redact("client presented s3cret-control-token-value while attaching");
        assert!(!redacted.contains("s3cret-control-token-value"));
        assert!(redacted.contains(REDACTED));
    }

    #[test]
    fn ignores_registered_values_too_short_to_be_distinctive() {
        register_secret("abc");
        assert_eq!(redact("abc def"), "abc def");
    }

    #[test]
    fn leaves_ordinary_text_untouched() {
        let message = "failed to record activity for workspace ws-17: database is locked";
        assert_eq!(redact(message), message);
    }
}
