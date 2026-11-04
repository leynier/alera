use cursor_agent_sdk::{is_usage_limit_code, CursorSdkError};
use serde_json::json;

#[test]
fn usage_and_rate_limit_codes_name_a_usage_limit() {
    for code in [
        "resource_exhausted",
        "RATE_LIMITED",
        "rate_limited_changeable",
        "PRO_USER_USAGE_LIMIT",
        "free_user_rate_limit",
        "TEAM_RATE_LIMIT_EXCEEDED",
        "USAGE_LIMIT_EXCEEDED",
        "SDK_ERROR_CODE_USAGE_LIMIT_EXCEEDED",
        "SDK_ERROR_CODE_RATE_LIMIT_EXCEEDED",
    ] {
        assert!(is_usage_limit_code(code), "{code}");
    }
    for code in [
        "",
        "UPSTREAM_ERROR",
        "unauthenticated",
        "usage_limit",
        "rate_limit",
        "PRO-USER_USAGE_LIMIT",
        "USAGE_LIMIT_EXCEEDED_SOON",
    ] {
        assert!(!is_usage_limit_code(code), "{code}");
    }
}

#[test]
fn http_429_and_limit_codes_are_usage_limits() {
    let http = |status| CursorSdkError::Http {
        status,
        message: "bridge request failed".into(),
    };
    let rpc = |code: &str| CursorSdkError::Rpc {
        method: "run stream".into(),
        code: code.into(),
        message: "Too many requests".into(),
        details: Box::new(json!({})),
    };
    assert!(http(429).is_usage_limit());
    assert!(!http(503).is_usage_limit());
    assert!(rpc("resource_exhausted").is_usage_limit());
    assert!(!rpc("unavailable").is_usage_limit());
    assert!(!CursorSdkError::Transport("429".into()).is_usage_limit());
}
