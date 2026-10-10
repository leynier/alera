use chrono::{Duration, Utc};
use uuid::Uuid;

use super::{check_runtime_access, check_tool_scope, resolve_runtime, RuntimeCandidate};
use crate::{auth::McpAuthContext, mcp_models::ToolAccess};

fn runtime(id: &str, name: &str, access: &str, online: bool) -> RuntimeCandidate {
    let now = Utc::now();
    RuntimeCandidate {
        id: id.to_owned(),
        name: name.to_owned(),
        mcp_access: access.to_owned(),
        last_seen_at: now,
        relay_granted_at: Some(if online {
            now
        } else {
            now - Duration::hours(1)
        }),
    }
}

fn error_code<T>(result: Result<T, crate::error::ApiError>) -> String {
    match result {
        Ok(_) => "ok".to_owned(),
        Err(crate::error::ApiError::Request { code, .. }) => code.to_owned(),
        Err(other) => other.to_string(),
    }
}

fn grant(scopes: &[&str]) -> McpAuthContext {
    McpAuthContext {
        account_id: Uuid::nil(),
        family_id: Uuid::nil(),
        grant_id: Uuid::nil(),
        client_id: "client".to_owned(),
        client_name: "Client".to_owned(),
        all_runtimes: true,
        scopes: scopes.iter().map(|scope| (*scope).to_owned()).collect(),
    }
}

#[test]
fn tool_classes_need_their_scope() {
    let full = grant(&["mcp:read", "mcp:execute"]);
    let admin = grant(&["mcp:read", "mcp:execute", "mcp:admin"]);
    let read = grant(&["mcp:read"]);
    assert_eq!(error_code(check_tool_scope(&read, ToolAccess::Read)), "ok");
    assert_eq!(
        error_code(check_tool_scope(&read, ToolAccess::Execute)),
        "insufficient_scope"
    );
    assert_eq!(
        error_code(check_tool_scope(&full, ToolAccess::Execute)),
        "ok"
    );
    let refused = check_tool_scope(&full, ToolAccess::Admin);
    assert!(matches!(
        refused,
        Err(crate::error::ApiError::Request { ref message, .. })
            if message.contains("mcp:admin") && message.contains("allow administrative tools")
    ));
    assert_eq!(error_code(refused), "insufficient_scope");
    assert_eq!(
        error_code(check_tool_scope(&admin, ToolAccess::Admin)),
        "ok"
    );
}

#[test]
fn runtime_levels_gate_tool_classes() {
    let cases = [
        ("off", ToolAccess::Read, "runtime_mcp_disabled"),
        ("read", ToolAccess::Read, "ok"),
        ("read", ToolAccess::Execute, "runtime_read_only"),
        ("read", ToolAccess::Admin, "runtime_not_admin"),
        ("full", ToolAccess::Execute, "ok"),
        ("full", ToolAccess::Admin, "runtime_not_admin"),
        ("admin", ToolAccess::Read, "ok"),
        ("admin", ToolAccess::Execute, "ok"),
        ("admin", ToolAccess::Admin, "ok"),
        ("unknown", ToolAccess::Read, "runtime_mcp_disabled"),
    ];
    for (level, access, expected) in cases {
        let candidate = runtime("r1", "Laptop", level, true);
        assert_eq!(
            error_code(check_runtime_access(&candidate, access)),
            expected,
            "{level} {access:?}"
        );
    }
    let refused = check_runtime_access(&runtime("r1", "Laptop", "full", true), ToolAccess::Admin);
    assert!(matches!(
        refused,
        Err(crate::error::ApiError::Request { status, ref message, .. })
            if status == axum::http::StatusCode::FORBIDDEN
                && message.starts_with("MCP Control on this runtime does not allow administrative tools.")
    ));
}

fn code(result: Result<&RuntimeCandidate, crate::error::ApiError>) -> String {
    match result {
        Ok(runtime) => runtime.id.clone(),
        Err(crate::error::ApiError::Request { code, .. }) => code.to_owned(),
        Err(other) => other.to_string(),
    }
}

#[test]
fn resolves_by_id_then_case_insensitive_name() {
    let runtimes = vec![
        runtime("r1", "Laptop", "full", true),
        runtime("r2", "laptop", "read", false),
        runtime("r3", "Server", "full", true),
    ];
    let now = Utc::now();
    assert_eq!(code(resolve_runtime(&runtimes, Some("r2"), now)), "r2");
    assert_eq!(code(resolve_runtime(&runtimes, Some("SERVER"), now)), "r3");
    assert_eq!(
        code(resolve_runtime(&runtimes, Some("LAPTOP"), now)),
        "runtime_ambiguous"
    );
    assert_eq!(
        code(resolve_runtime(&runtimes, Some("missing"), now)),
        "runtime_not_found"
    );
    assert_eq!(
        code(resolve_runtime(&runtimes, None, now)),
        "runtime_required"
    );
}

#[test]
fn omitted_runtime_needs_exactly_one_connected() {
    let now = Utc::now();
    let one = vec![
        runtime("r1", "Laptop", "full", true),
        runtime("r2", "Server", "off", true),
        runtime("r3", "Old", "full", false),
    ];
    assert_eq!(code(resolve_runtime(&one, None, now)), "r1");
    let none = vec![runtime("r3", "Old", "full", false)];
    let error = resolve_runtime(&none, None, now);
    assert!(matches!(
        error,
        Err(crate::error::ApiError::Request { ref message, .. }) if message.contains("Old")
    ));
    assert_eq!(code(error), "no_runtime_available");
    assert_eq!(
        code(resolve_runtime(&[], None, now)),
        "no_runtime_available"
    );
}
