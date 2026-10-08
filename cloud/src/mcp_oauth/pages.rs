use axum::{
    http::{header, HeaderValue, StatusCode},
    response::{Html, IntoResponse, Response},
};
use base64::{engine::general_purpose::STANDARD, Engine};
use chrono::{DateTime, Utc};
use sha2::{Digest, Sha256};
use url::Url;

use crate::error::ApiError;

const STYLE: &str = "\
:root{color-scheme:dark}\
*{box-sizing:border-box}\
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;\
background:#0b0b0c;color:#e8e8ea;font:15px/1.5 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;padding:16px}\
main{width:100%;max-width:440px;background:#151517;border:1px solid #2a2a2e;border-radius:8px;padding:24px}\
h1{font-size:20px;margin:0 0 8px}\
p{margin:0 0 12px;color:#b4b4ba}\
.muted{color:#8a8a92;font-size:13px}\
.error{color:#ff8a80}\
.button{display:block;width:100%;margin:8px 0 0;padding:10px 12px;border-radius:8px;border:1px solid #3a3a40;\
background:#232327;color:#e8e8ea;font:inherit;text-align:center;text-decoration:none;cursor:pointer}\
.primary{background:#e8e8ea;color:#0b0b0c;border-color:#e8e8ea}\
fieldset{border:1px solid #2a2a2e;border-radius:8px;margin:12px 0;padding:8px 12px}\
legend{color:#8a8a92;font-size:13px;padding:0 4px}\
label{display:flex;gap:8px;align-items:flex-start;padding:6px 0}\
label span{display:block}\
input[type=text]{width:100%;padding:10px;border-radius:8px;border:1px solid #3a3a40;background:#0b0b0c;\
color:#e8e8ea;font:inherit;letter-spacing:2px;text-transform:uppercase}\
.row{display:flex;gap:8px}.row>*{flex:1}";

/// One server-rendered page. `form_targets` lists extra CSP `form-action` sources.
pub struct Page {
    pub title: String,
    pub body: String,
    pub form_targets: Vec<String>,
}

impl Page {
    pub fn new(title: impl Into<String>, body: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            body: body.into(),
            form_targets: Vec::new(),
        }
    }

    pub fn with_form_target(mut self, source: Option<String>) -> Self {
        self.form_targets.extend(source);
        self
    }

    pub fn into_response_with(self, status: StatusCode) -> Response {
        let html = format!(
            "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\
<meta name=\"referrer\" content=\"no-referrer\"><title>{}</title><style>{STYLE}</style></head>\
<body><main>{}</main></body></html>",
            escape(&self.title),
            self.body
        );
        let mut response = (status, Html(html)).into_response();
        let csp = content_security_policy(&self.form_targets);
        let headers = response.headers_mut();
        if let Ok(value) = HeaderValue::from_str(&csp) {
            headers.insert(header::CONTENT_SECURITY_POLICY, value);
        }
        headers.insert(header::X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
        headers.insert(
            header::X_CONTENT_TYPE_OPTIONS,
            HeaderValue::from_static("nosniff"),
        );
        headers.insert(
            header::REFERRER_POLICY,
            HeaderValue::from_static("no-referrer"),
        );
        headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        response
    }
}

impl IntoResponse for Page {
    fn into_response(self) -> Response {
        self.into_response_with(StatusCode::OK)
    }
}

pub fn content_security_policy(form_targets: &[String]) -> String {
    let style_hash = STANDARD.encode(Sha256::digest(STYLE.as_bytes()));
    let mut form_action = String::from("'self'");
    for target in form_targets {
        form_action.push(' ');
        form_action.push_str(target);
    }
    format!(
        "default-src 'none'; style-src 'sha256-{style_hash}'; img-src 'self'; \
form-action {form_action}; frame-ancestors 'none'; base-uri 'none'"
    )
}

/// The CSP source that admits a redirect to `redirect_uri`: its origin for web schemes,
/// or the bare scheme for private-use schemes such as `cursor:`.
pub fn form_action_source(redirect_uri: &str) -> Option<String> {
    let url = Url::parse(redirect_uri).ok()?;
    match url.scheme() {
        "http" | "https" => {
            let origin = url.origin().ascii_serialization();
            (origin != "null").then_some(origin)
        }
        scheme => Some(format!("{scheme}:")),
    }
}

/// A page-rendering failure shown to the person in the browser.
#[derive(Debug)]
pub struct PageError {
    pub status: StatusCode,
    pub title: &'static str,
    pub message: String,
}

impl PageError {
    pub fn new(status: StatusCode, title: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            title,
            message: message.into(),
        }
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "Request not valid", message)
    }

    pub fn expired() -> Self {
        Self::bad_request("This sign-in request expired or was already used. Start again from the app that sent you here.")
    }
}

impl From<sqlx::Error> for PageError {
    fn from(error: sqlx::Error) -> Self {
        ApiError::from(error).into()
    }
}

impl From<ApiError> for PageError {
    fn from(error: ApiError) -> Self {
        match error {
            ApiError::Request {
                status, message, ..
            } => Self::new(status, "Something went wrong", message),
            other => {
                let status = match other {
                    ApiError::Upstream(_) => StatusCode::BAD_GATEWAY,
                    _ => StatusCode::INTERNAL_SERVER_ERROR,
                };
                tracing::error!(error = %other, "sign-in page failure");
                Self::new(
                    status,
                    "Something went wrong",
                    "Alera could not complete the request. Try again in a moment.",
                )
            }
        }
    }
}

impl IntoResponse for PageError {
    fn into_response(self) -> Response {
        let body = format!(
            "<h1>{}</h1><p class=\"error\">{}</p>",
            escape(self.title),
            escape(&self.message)
        );
        Page::new(self.title, body).into_response_with(self.status)
    }
}

pub fn escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '&' => escaped.push_str("&amp;"),
            '<' => escaped.push_str("&lt;"),
            '>' => escaped.push_str("&gt;"),
            '"' => escaped.push_str("&quot;"),
            '\'' => escaped.push_str("&#39;"),
            other => escaped.push(other),
        }
    }
    escaped
}

pub fn hidden(name: &str, value: &str) -> String {
    format!(
        "<input type=\"hidden\" name=\"{}\" value=\"{}\">",
        escape(name),
        escape(value)
    )
}

pub fn provider_buttons(target_param: &str, target_id: &str) -> String {
    let link = |provider: &str, label: &str| {
        format!(
            "<a class=\"button\" href=\"/oauth/login?{}={}&amp;provider={provider}\">{label}</a>",
            escape(target_param),
            escape(target_id)
        )
    };
    format!(
        "{}{}",
        link("github", "Continue with GitHub"),
        link("google", "Continue with Google")
    )
}

pub fn format_time(value: DateTime<Utc>) -> String {
    value.format("%Y-%m-%d %H:%M UTC").to_string()
}

#[cfg(test)]
mod tests {
    use super::{content_security_policy, escape, form_action_source};

    #[test]
    fn escapes_markup_and_quotes() {
        assert_eq!(
            escape("<script>alert('x')</script> & \"q\""),
            "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; &quot;q&quot;"
        );
    }

    #[test]
    fn form_action_admits_the_client_redirect_origin() {
        assert_eq!(
            form_action_source("https://claude.ai/api/mcp/auth_callback?x=1").as_deref(),
            Some("https://claude.ai")
        );
        assert_eq!(
            form_action_source("http://127.0.0.1:33418/callback").as_deref(),
            Some("http://127.0.0.1:33418")
        );
        assert_eq!(
            form_action_source("cursor://anysphere.cursor-retrieval/oauth/callback").as_deref(),
            Some("cursor:")
        );
        let csp = content_security_policy(&["https://claude.ai".to_owned()]);
        assert!(csp.contains("form-action 'self' https://claude.ai;"));
        assert!(csp.contains("frame-ancestors 'none'"));
    }
}
