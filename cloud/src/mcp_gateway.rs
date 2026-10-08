use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use chrono::{DateTime, Duration, Utc};
use sqlx::FromRow;
use uuid::Uuid;

use crate::{
    auth::{authenticate_mcp, McpAuthContext, McpCallGrantInput, MCP_CALL_GRANT_SECONDS},
    error::ApiError,
    mcp_models::{
        CreateMcpCallRequest, CreateMcpCallResponse, McpAccess, McpCallOutcomeRequest,
        McpRuntimeList, McpRuntimeSummary, ToolAccess, SCOPE_EXECUTE, SCOPE_READ,
    },
    relay::ACTIVE_RUNTIME_SECONDS,
    state::AppState,
};

const MAX_DURATION_MS: i64 = 24 * 60 * 60 * 1000;

#[derive(Clone, Debug, FromRow)]
pub struct RuntimeCandidate {
    pub id: String,
    pub name: String,
    pub mcp_access: String,
    pub last_seen_at: DateTime<Utc>,
    pub relay_granted_at: Option<DateTime<Utc>>,
}

impl RuntimeCandidate {
    fn access(&self) -> McpAccess {
        self.mcp_access.parse().unwrap_or(McpAccess::Off)
    }

    /// Online means a recent runtime relay grant that reported MCP Control on.
    pub fn online(&self, now: DateTime<Utc>) -> bool {
        self.access() != McpAccess::Off
            && self
                .relay_granted_at
                .is_some_and(|at| at > now - Duration::seconds(ACTIVE_RUNTIME_SECONDS))
    }
}

/// Runtimes this grant reaches: owned by the account, not transferred, and either named
/// by the grant or covered by an all-runtimes grant.
async fn reachable_runtimes(
    state: &AppState,
    auth: &McpAuthContext,
) -> Result<Vec<RuntimeCandidate>, ApiError> {
    Ok(sqlx::query_as::<_, RuntimeCandidate>(
        r#"
        SELECT r.id, r.name, r.mcp_access, r.last_seen_at, r.relay_granted_at
        FROM runtimes r
        WHERE r.account_id = $1
          AND r.transferred_at IS NULL
          AND (
              $2
              OR EXISTS (
                  SELECT 1 FROM mcp_grant_runtimes gr
                  WHERE gr.grant_id = $3 AND gr.runtime_id = r.id
              )
          )
        ORDER BY LOWER(r.name), r.id
        "#,
    )
    .bind(auth.account_id)
    .bind(auth.all_runtimes)
    .bind(auth.grant_id)
    .fetch_all(&state.pool)
    .await?)
}

async fn touch_grant(state: &AppState, auth: &McpAuthContext) -> Result<(), ApiError> {
    sqlx::query("UPDATE mcp_grants SET last_used_at = $2 WHERE id = $1")
        .bind(auth.grant_id)
        .bind(Utc::now())
        .execute(&state.pool)
        .await?;
    Ok(())
}

pub async fn list_runtimes(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<McpRuntimeList>, ApiError> {
    let auth = authenticate_mcp(&headers, &state).await?;
    auth.require_scope(SCOPE_READ)?;
    let now = Utc::now();
    let runtimes = reachable_runtimes(&state, &auth)
        .await?
        .into_iter()
        .map(|runtime| McpRuntimeSummary {
            online: runtime.online(now),
            mcp_access: runtime.access(),
            id: runtime.id,
            name: runtime.name,
            last_seen_at: runtime.last_seen_at,
        })
        .collect();
    touch_grant(&state, &auth).await?;
    Ok(Json(McpRuntimeList { runtimes }))
}

fn name_list(runtimes: &[&RuntimeCandidate]) -> String {
    runtimes
        .iter()
        .map(|runtime| runtime.name.as_str())
        .collect::<Vec<_>>()
        .join(", ")
}

/// Picks the runtime for a call by id, by case-insensitive name, or as the only connected one.
pub fn resolve_runtime<'a>(
    runtimes: &'a [RuntimeCandidate],
    requested: Option<&str>,
    now: DateTime<Utc>,
) -> Result<&'a RuntimeCandidate, ApiError> {
    if let Some(requested) = requested.map(str::trim).filter(|value| !value.is_empty()) {
        if let Some(runtime) = runtimes.iter().find(|runtime| runtime.id == requested) {
            return Ok(runtime);
        }
        let wanted = requested.to_lowercase();
        let named: Vec<&RuntimeCandidate> = runtimes
            .iter()
            .filter(|runtime| runtime.name.to_lowercase() == wanted)
            .collect();
        return match named.as_slice() {
            [runtime] => Ok(runtime),
            [] => Err(ApiError::not_found(
                "runtime_not_found",
                format!("No granted runtime is named {requested}."),
            )),
            several => Err(ApiError::conflict(
                "runtime_ambiguous",
                format!(
                    "Several runtimes are named {requested}. Pass the runtime id instead: {}.",
                    several
                        .iter()
                        .map(|runtime| runtime.id.as_str())
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            )),
        };
    }
    let connected: Vec<&RuntimeCandidate> = runtimes
        .iter()
        .filter(|runtime| runtime.online(now))
        .collect();
    match connected.as_slice() {
        [runtime] => Ok(runtime),
        [] => {
            let granted: Vec<&RuntimeCandidate> = runtimes.iter().collect();
            let message = if granted.is_empty() {
                "This authorization does not reach any runtime yet.".to_owned()
            } else {
                format!(
                    "No granted runtime is connected with MCP Control on. Granted runtimes: {}.",
                    name_list(&granted)
                )
            };
            Err(ApiError::not_found("no_runtime_available", message))
        }
        several => Err(ApiError::conflict(
            "runtime_required",
            format!(
                "Several runtimes are connected. Pass runtime with one of: {}.",
                name_list(several)
            ),
        )),
    }
}

fn validate_tool(tool: &str) -> Result<(), ApiError> {
    let valid = !tool.is_empty()
        && tool.len() <= 64
        && tool
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"_.-".contains(&byte));
    if valid {
        Ok(())
    } else {
        Err(ApiError::bad_request(
            "invalid_tool",
            "The tool name is invalid.",
        ))
    }
}

fn check_runtime_access(runtime: &RuntimeCandidate, access: ToolAccess) -> Result<(), ApiError> {
    match (runtime.access(), access) {
        (McpAccess::Off, _) => Err(ApiError::conflict(
            "runtime_mcp_disabled",
            format!("MCP Control is off on runtime {}.", runtime.name),
        )),
        (McpAccess::Read, ToolAccess::Execute) => {
            let message = format!(
                "Runtime {} allows only read tools. Turn on full MCP Control to run this tool.",
                runtime.name
            );
            Err(ApiError::forbidden("runtime_read_only", message))
        }
        _ => Ok(()),
    }
}

pub async fn create_call(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateMcpCallRequest>,
) -> Result<Json<CreateMcpCallResponse>, ApiError> {
    let auth = authenticate_mcp(&headers, &state).await?;
    auth.require_scope(SCOPE_READ)?;
    validate_tool(&request.tool)?;
    if request.access == ToolAccess::Execute {
        auth.require_scope(SCOPE_EXECUTE)?;
    }
    let now = Utc::now();
    let runtimes = reachable_runtimes(&state, &auth).await?;
    let runtime = resolve_runtime(&runtimes, request.runtime.as_deref(), now)?;
    check_runtime_access(runtime, request.access)?;
    let call_id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO mcp_calls (
            id, account_id, grant_id, client_id, client_name, runtime_id, tool, access,
            created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        "#,
    )
    .bind(call_id)
    .bind(auth.account_id)
    .bind(auth.grant_id)
    .bind(&auth.client_id)
    .bind(&auth.client_name)
    .bind(&runtime.id)
    .bind(&request.tool)
    .bind(request.access.as_str())
    .bind(now)
    .execute(&state.pool)
    .await?;
    touch_grant(&state, &auth).await?;
    let grant = state
        .tokens
        .issue_mcp_call_grant(McpCallGrantInput {
            call_id,
            account_id: auth.account_id,
            runtime_id: &runtime.id,
            grant_id: auth.grant_id,
            client_id: &auth.client_id,
            client_name: &auth.client_name,
            tool: &request.tool,
            access: request.access.as_str(),
        })
        .await?;
    Ok(Json(CreateMcpCallResponse {
        call_id,
        runtime_id: runtime.id.clone(),
        runtime_name: runtime.name.clone(),
        grant,
        expires_in: MCP_CALL_GRANT_SECONDS,
    }))
}

pub async fn complete_call(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(call_id): Path<String>,
    Json(request): Json<McpCallOutcomeRequest>,
) -> Result<StatusCode, ApiError> {
    let auth = authenticate_mcp(&headers, &state).await?;
    let not_found = || ApiError::not_found("call_not_found", "The MCP call does not exist.");
    let call_id = Uuid::parse_str(&call_id).map_err(|_| not_found())?;
    if !(0..=MAX_DURATION_MS).contains(&request.duration_ms) {
        return Err(ApiError::bad_request(
            "invalid_duration",
            "The call duration is invalid.",
        ));
    }
    let updated = sqlx::query(
        r#"
        UPDATE mcp_calls
        SET outcome = $4, duration_ms = $5, completed_at = $6
        WHERE id = $1 AND account_id = $2 AND grant_id = $3 AND outcome IS NULL
        "#,
    )
    .bind(call_id)
    .bind(auth.account_id)
    .bind(auth.grant_id)
    .bind(request.outcome.as_str())
    .bind(request.duration_ms as i32)
    .bind(Utc::now())
    .execute(&state.pool)
    .await?
    .rows_affected();
    if updated == 1 {
        return Ok(StatusCode::NO_CONTENT);
    }
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM mcp_calls WHERE id = $1 AND account_id = $2 AND grant_id = $3)",
    )
    .bind(call_id)
    .bind(auth.account_id)
    .bind(auth.grant_id)
    .fetch_one(&state.pool)
    .await?;
    if exists {
        Err(ApiError::conflict(
            "call_already_completed",
            "The MCP call outcome was already recorded.",
        ))
    } else {
        Err(not_found())
    }
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, Utc};

    use super::{resolve_runtime, RuntimeCandidate};

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
}
