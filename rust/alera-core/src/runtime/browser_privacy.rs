use anyhow::Result;
use serde_json::Value;
use url::Url;

use super::RuntimeStoreError;

pub const BROWSER_TITLE_MAX_BYTES: usize = 1024;

const SENSITIVE_QUERY_KEYS: &[&str] = &[
    "accesstoken",
    "apikey",
    "assertion",
    "auth",
    "authorization",
    "code",
    "credential",
    "idtoken",
    "jwt",
    "key",
    "oauth",
    "oauthtoken",
    "passwd",
    "password",
    "refreshtoken",
    "samlrequest",
    "samlresponse",
    "secret",
    "session",
    "sessionid",
    "signature",
    "sig",
    "state",
    "ticket",
    "token",
];
const SENSITIVE_PATH_FRAGMENTS: &[&str] = &[
    "/oauth/callback",
    "/oauth2/callback",
    "/auth/callback",
    "/signin-oidc",
    "/saml/acs",
    "/magic-link",
    "/reset-password",
    "/password-reset",
];

pub(super) fn canonical_browser_origin(raw: &str) -> Result<String> {
    let value = raw.trim();
    let Some(separator) = value.find("://") else {
        return Err(invalid_origin());
    };
    let scheme = &value[..separator];
    if !scheme.eq_ignore_ascii_case("http") && !scheme.eq_ignore_ascii_case("https") {
        return Err(invalid_origin());
    }
    let remainder = &value[(separator + 3)..];
    let authority_end = remainder.find(['/', '?', '#']).unwrap_or(remainder.len());
    let authority = &remainder[..authority_end];
    let suffix = &remainder[authority_end..];
    if authority.is_empty()
        || authority.contains('@')
        || authority.ends_with(':')
        || authority.contains('\\')
        || !matches!(suffix, "" | "/")
    {
        return Err(invalid_origin());
    }
    let parsed = Url::parse(value).map_err(|_| invalid_origin())?;
    if !matches!(parsed.scheme(), "http" | "https")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.path() != "/"
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return Err(invalid_origin());
    }
    let origin = parsed.origin().ascii_serialization();
    if origin == "null" {
        return Err(invalid_origin());
    }
    Ok(origin)
}

pub(super) fn sanitize_browser_tab_payload(kind: &str, payload: &mut Value) {
    if kind != "browser" {
        return;
    }
    let Some(object) = payload.as_object_mut() else {
        *payload = serde_json::json!({});
        return;
    };
    let raw_url = object
        .get("browserUrl")
        .and_then(Value::as_str)
        .map(str::to_string);
    let title_may_persist = raw_url
        .as_deref()
        .is_some_and(browser_url_allows_title_persistence);
    let safe_url = raw_url.as_deref().and_then(browser_url_for_persistence);
    if let Some(url) = safe_url {
        object.insert("browserUrl".to_string(), Value::String(url));
    } else {
        object.remove("browserUrl");
    }
    if !title_may_persist {
        object.remove("browserRuntimeTitle");
    } else if let Some(title) = object
        .get("browserRuntimeTitle")
        .and_then(Value::as_str)
        .map(normalize_browser_title)
    {
        if title.is_empty() {
            object.remove("browserRuntimeTitle");
        } else {
            object.insert("browserRuntimeTitle".to_string(), Value::String(title));
        }
    }
}

pub fn normalize_browser_title(value: &str) -> String {
    let mut normalized = String::with_capacity(value.len().min(BROWSER_TITLE_MAX_BYTES));
    for character in value.trim().chars() {
        if character.is_control() {
            continue;
        }
        if normalized.len() + character.len_utf8() > BROWSER_TITLE_MAX_BYTES {
            break;
        }
        normalized.push(character);
    }
    normalized.trim().to_string()
}

pub fn browser_url_allows_title_persistence(raw: &str) -> bool {
    let raw = raw.trim();
    let Ok(url) = Url::parse(raw) else {
        return false;
    };
    if url.scheme() == "about"
        && url.path() == "blank"
        && url.query().is_none()
        && url.fragment().is_none()
    {
        return true;
    }
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return false;
    }
    let sensitive_query = url
        .query_pairs()
        .any(|(key, _)| is_sensitive_query_key(&key));
    let sensitive_fragment = url.fragment().is_some_and(|fragment| {
        let normalized = normalized_sensitive_text(fragment);
        SENSITIVE_QUERY_KEYS
            .iter()
            .any(|candidate| normalized.contains(candidate))
    });
    let normalized_path = url.path().to_ascii_lowercase();
    let sensitive_path = SENSITIVE_PATH_FRAGMENTS
        .iter()
        .any(|candidate| normalized_path.contains(candidate));
    let has_credentials = !url.username().is_empty()
        || url.password().is_some()
        || raw_authority(raw).is_some_and(|authority| authority.contains('@'));
    !(sensitive_query || sensitive_fragment || sensitive_path || has_credentials)
}

pub(super) fn browser_url_for_persistence(raw: &str) -> Option<String> {
    let raw = raw.trim();
    let mut url = Url::parse(raw).ok()?;
    if url.scheme() == "about"
        && url.path() == "blank"
        && url.query().is_none()
        && url.fragment().is_none()
    {
        return Some("about:blank".to_string());
    }
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return None;
    }
    let sensitive_query = url
        .query_pairs()
        .any(|(key, _)| is_sensitive_query_key(&key));
    let sensitive_fragment = url.fragment().is_some_and(|fragment| {
        let normalized = normalized_sensitive_text(fragment);
        SENSITIVE_QUERY_KEYS
            .iter()
            .any(|candidate| normalized.contains(candidate))
    });
    let normalized_path = url.path().to_ascii_lowercase();
    let sensitive_path = SENSITIVE_PATH_FRAGMENTS
        .iter()
        .any(|candidate| normalized_path.contains(candidate));
    let has_credentials = !url.username().is_empty()
        || url.password().is_some()
        || raw_authority(raw).is_some_and(|authority| authority.contains('@'));
    if sensitive_query || sensitive_fragment || sensitive_path || has_credentials {
        let origin = url.origin().ascii_serialization();
        return (origin != "null").then(|| format!("{origin}/"));
    }
    url.set_fragment(None);
    Some(url.to_string())
}

fn is_sensitive_query_key(value: &str) -> bool {
    let normalized = normalized_sensitive_text(value);
    SENSITIVE_QUERY_KEYS.contains(&normalized.as_str())
        || ["token", "secret", "password", "signature"]
            .iter()
            .any(|suffix| normalized.ends_with(suffix))
}

fn normalized_sensitive_text(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .map(|character| character.to_ascii_lowercase())
        .collect()
}

fn raw_authority(value: &str) -> Option<&str> {
    let (_, remainder) = value.split_once("://")?;
    let end = remainder.find(['/', '?', '#']).unwrap_or(remainder.len());
    Some(&remainder[..end])
}

fn invalid_origin() -> anyhow::Error {
    RuntimeStoreError::Message(
        "browser permission origin must contain only an HTTP(S) scheme, host, and optional port"
            .to_string(),
    )
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persistence_filter_collapses_all_sensitive_query_key_shapes() {
        for raw in [
            "https://example.com/?SAMLResponse=secret",
            "https://example.com/?assertion=secret",
            "https://example.com/?session_id=secret",
            "https://example.com/?passwd=secret",
            "https://example.com/?oauth=secret",
            "https://example.com/?customAccessToken=secret",
        ] {
            assert_eq!(
                browser_url_for_persistence(raw),
                Some("https://example.com/".to_string())
            );
        }
    }

    #[test]
    fn browser_titles_drop_controls_and_stop_at_a_utf8_boundary() {
        let raw = format!(" \u{0}Docs\n{}\t ", "🚀".repeat(300));
        let normalized = normalize_browser_title(&raw);

        assert!(!normalized.chars().any(char::is_control));
        assert_eq!(normalized.len(), BROWSER_TITLE_MAX_BYTES);
        assert_eq!(normalized, format!("Docs{}", "🚀".repeat(255)));
    }

    #[test]
    fn titles_are_not_persisted_for_sensitive_or_rejected_page_urls() {
        for raw in [
            "https://example.com/oauth/callback",
            "https://example.com/?SAMLResponse=secret",
            "https://example.com/#access_token=secret",
            "https://user:password@example.com/private",
            "file:///tmp/private",
        ] {
            assert!(!browser_url_allows_title_persistence(raw), "{raw}");
        }
        assert!(browser_url_allows_title_persistence(
            "https://example.com/docs#section"
        ));
        assert!(browser_url_allows_title_persistence("about:blank"));
    }
}
