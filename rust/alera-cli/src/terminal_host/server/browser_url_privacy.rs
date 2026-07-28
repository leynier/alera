use alera_core::runtime::{browser_url_allows_title_persistence, normalize_browser_title};
use serde_json::Value;
use url::Url;

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

/// Returns the most useful URL that is safe to write to durable state.
///
/// Credentials, OAuth callback material and token-bearing fragments collapse
/// to the origin. Fragments are otherwise removed because they are often
/// application state that should not survive a browser session.
pub(super) fn browser_url_for_persistence(raw: &str) -> Option<String> {
    let mut url = Url::parse(raw.trim()).ok()?;
    if url.scheme() == "about" && url.path() == "blank" {
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
    let has_credentials = !url.username().is_empty() || url.password().is_some();
    if sensitive_query || sensitive_fragment || sensitive_path || has_credentials {
        return origin(&url);
    }
    url.set_fragment(None);
    Some(url.into())
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

pub(super) fn sanitize_browser_tab_payload(payload: &mut Value) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };
    let raw = object
        .get("browserUrl")
        .and_then(Value::as_str)
        .map(str::to_string);
    let title_may_persist = raw
        .as_deref()
        .is_some_and(browser_url_allows_title_persistence);
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
    let Some(raw) = raw else {
        return;
    };
    match browser_url_for_persistence(&raw) {
        Some(url) => {
            object.insert("browserUrl".to_string(), Value::String(url));
        }
        None => {
            object.remove("browserUrl");
        }
    }
}

fn origin(url: &Url) -> Option<String> {
    let host = url.host_str()?;
    let mut value = format!("{}://{host}", url.scheme());
    if let Some(port) = url.port() {
        value.push(':');
        value.push_str(&port.to_string());
    }
    value.push('/');
    Some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordinary_urls_keep_path_and_query_but_drop_fragments() {
        assert_eq!(
            browser_url_for_persistence("https://example.com/docs?q=rust#section"),
            Some("https://example.com/docs?q=rust".to_string())
        );
    }

    #[test]
    fn token_and_oauth_urls_collapse_to_origin() {
        for raw in [
            "https://example.com/callback?code=secret&state=opaque",
            "https://example.com/#access_token=secret",
            "https://user:password@example.com/private",
            "https://example.com/oauth/callback",
            "https://example.com/signin-oidc",
            "https://example.com/?SAMLResponse=secret",
            "https://example.com/?assertion=secret",
            "https://example.com/?session_id=secret",
            "https://example.com/?passwd=secret",
            "https://example.com/?oauth=secret",
        ] {
            assert_eq!(
                browser_url_for_persistence(raw),
                Some("https://example.com/".to_string())
            );
        }
    }

    #[test]
    fn non_web_schemes_are_not_persisted_except_about_blank() {
        assert_eq!(browser_url_for_persistence("file:///tmp/private"), None);
        assert_eq!(
            browser_url_for_persistence("about:blank"),
            Some("about:blank".to_string())
        );
    }

    #[test]
    fn tab_payloads_never_keep_sensitive_or_non_web_urls() {
        let mut token = serde_json::json!({
            "browserUrl": "https://example.com/callback?code=secret",
            "browserProfileId": "default",
        });
        sanitize_browser_tab_payload(&mut token);
        assert_eq!(token["browserUrl"], "https://example.com/");

        let mut local = serde_json::json!({"browserUrl": "file:///tmp/private"});
        sanitize_browser_tab_payload(&mut local);
        assert!(local.get("browserUrl").is_none());

        let mut title_without_url = serde_json::json!({
            "browserRuntimeTitle": "Private Account",
        });
        sanitize_browser_tab_payload(&mut title_without_url);
        assert!(title_without_url.get("browserRuntimeTitle").is_none());
    }
}
