//! Masks secrets before anything reaches a log file or an error report.
//!
//! Redaction lives in the sink rather than at the call sites on purpose: a
//! diagnostics bundle is meant to be shared, and a call site that forgets to
//! mask is indistinguishable from one that had nothing to mask.

use std::sync::{OnceLock, RwLock};

/// The pattern rules are shared with the agent transport, which masks the
/// stderr tail of a provider exit error, so both mask the same shapes.
pub use alera_agent_transport::REDACTED;

/// Values below this length are not worth registering: short strings collide
/// with ordinary words and would mask unrelated text.
const MIN_REGISTERED_SECRET_LEN: usize = 8;

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

/// Replaces every known secret in `input` with [`REDACTED`]: registered
/// literals first, then credential shapes such as `OPENAI_API_KEY=...`,
/// `Bearer ...` or an `sk-` key.
pub fn redact(input: &str) -> String {
    let mut output = input.to_string();

    if let Ok(secrets) = registered_secrets().read() {
        for secret in secrets.iter() {
            if output.contains(secret.as_str()) {
                output = output.replace(secret.as_str(), REDACTED);
            }
        }
    }

    alera_agent_transport::redact_secrets(&output)
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

    #[test]
    fn masks_compound_credential_key_names() {
        let redacted = redact(
            "env OPENAI_API_KEY=key-one FOO_API_KEY=key-two MY_SECRET=secret-three \
             GITHUB_TOKEN=token-four x_api_key: key-five clientSecret: key-six",
        );
        assert_eq!(
            redacted,
            "env OPENAI_API_KEY=[redacted] FOO_API_KEY=[redacted] MY_SECRET=[redacted] \
             GITHUB_TOKEN=[redacted] x_api_key: [redacted] clientSecret: [redacted]"
        );
    }

    #[test]
    fn masks_provider_failure_credentials_but_not_ordinary_keys() {
        let redacted = redact(
            r#"oauth refresh failed: client_secret=client-value refresh_token=refresh-value {"client_secret":"json-value"} clientSecret: camel-value X-Auth-Token: header-value max_tokens=4096"#,
        );
        assert_eq!(
            redacted,
            r#"oauth refresh failed: client_secret=[redacted] refresh_token=[redacted] {"client_secret":"[redacted]"} clientSecret: [redacted] X-Auth-Token: [redacted] max_tokens=4096"#
        );
    }

    #[test]
    fn masks_provider_keys_with_underscores_in_stderr() {
        let redacted = redact(
            "anthropic=sk-ant-api03-AbCdEf_GhIjKlMnOpQr-StUvWx_yz0123456789-AA\n\
             openai=sk-proj-AbCdEfGhIj_KlMnOpQrStUv-WxYz_0123456789",
        );
        assert_eq!(redacted, "anthropic=[redacted]\nopenai=[redacted]");
    }

    #[test]
    fn keeps_authorization_scheme_while_masking_its_credential() {
        let redacted = redact("request failed: Authorization: Bearer bearer-secret");
        assert_eq!(redacted, "request failed: Authorization: Bearer [redacted]");
    }
}
