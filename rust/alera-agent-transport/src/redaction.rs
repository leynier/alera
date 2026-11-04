//! Masks credentials in text a provider process produced, such as the stderr
//! tail an exit error carries, before it reaches a log, an error report or the
//! chat.
//!
//! The rules only recognize credential shapes: a key whose name ends in a
//! credential word, an authorization scheme, a well-known token prefix or URL
//! user info. A secret printed with none of these beside it stays visible.

use std::sync::OnceLock;

use regex::{Captures, Regex};

/// The marker that replaces every masked value.
pub const REDACTED: &str = "[redacted]";

/// `key=value` and `key: value`, quoted or not. The key may be compound, as in
/// `OPENAI_API_KEY`, `client_secret`, `clientSecret` or `X-Auth-Token`, but must
/// end in a credential word, so `max_tokens` or `passwordless` stay readable.
/// An authorization scheme before the value is kept.
fn keyed_secret_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(concat!(
            r"(?i)(?P<key>[a-z0-9_-]*(?:api[_-]?key|access[_-]?key|secret[_-]?key|private[_-]?key",
            r"|token|secret|password|passwd|credential|authorization))(?-u:\b)",
            r#"(?P<separator>["']?[ \t]*[:=][ \t]*)"#,
            r"(?P<scheme>(?:bearer|basic)[ \t]+)?",
            r#"(?P<value>"(?:[^"\\\r\n]|\\.)+"|'(?:[^'\\\r\n]|\\.)+'|["']?[^\s"',;})]+)"#,
        ))
        .expect("keyed secret pattern is valid")
    })
}

fn bearer_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"(?i)(?-u:\b)(?P<scheme>bearer)[ \t]+[A-Za-z0-9._~+/=-]+")
            .expect("bearer pattern is valid")
    })
}

/// OpenAI and Anthropic `sk-` keys, GitHub tokens and Slack tokens.
fn prefixed_token_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(concat!(
            r"(?-u:\b)(?:sk-[A-Za-z0-9][A-Za-z0-9_-]{7,}|gh[opsur]_[A-Za-z0-9]{8,}",
            r"|github_pat_[A-Za-z0-9_]{8,}|xox[a-z]-[A-Za-z0-9-]{8,})(?-u:\b)",
        ))
        .expect("prefixed token pattern is valid")
    })
}

fn url_user_info_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"(?i)(?-u:\b)(?P<scheme>[a-z][a-z0-9+.-]*)://(?P<user>[^\s/?#@]+)@")
            .expect("URL user info pattern is valid")
    })
}

/// Replaces every recognizable credential in `text` with [`REDACTED`].
pub fn redact_secrets(text: &str) -> String {
    let output = url_user_info_pattern().replace_all(text, |caps: &Captures<'_>| {
        let scheme = &caps["scheme"];
        // A bare user name is only an account, but an HTTP user name is often
        // a token and any password is a secret.
        let secret = caps["user"].contains(':')
            || scheme.eq_ignore_ascii_case("http")
            || scheme.eq_ignore_ascii_case("https");
        if secret {
            format!("{scheme}://{REDACTED}@")
        } else {
            caps[0].to_string()
        }
    });
    let output = keyed_secret_pattern().replace_all(&output, |caps: &Captures<'_>| {
        let scheme = caps.name("scheme").map_or("", |scheme| scheme.as_str());
        format!(
            "{}{}{scheme}{}",
            &caps["key"],
            &caps["separator"],
            masked_value(&caps["value"])
        )
    });
    let output = prefixed_token_pattern().replace_all(&output, REDACTED);
    bearer_pattern()
        .replace_all(&output, |caps: &Captures<'_>| {
            format!("{} {REDACTED}", &caps["scheme"])
        })
        .into_owned()
}

/// Keeps the quotes around a masked value so JSON and similar output keeps
/// its shape.
fn masked_value(value: &str) -> String {
    let Some(quote) = value
        .chars()
        .next()
        .filter(|first| matches!(first, '"' | '\''))
    else {
        return REDACTED.to_string();
    };
    let closed = value.len() > 1 && value.ends_with(quote);
    let close = if closed {
        quote.to_string()
    } else {
        String::new()
    };
    format!("{quote}{REDACTED}{close}")
}

#[cfg(test)]
#[path = "redaction_tests.rs"]
mod tests;
