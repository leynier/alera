use axum::{
    body::Bytes,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use sqlx::FromRow;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::{
    accounts::load_account_summary,
    api_models::AccountSummary,
    auth::validation::{hash_secret, random_secret},
    device_auth,
    mcp_models::{McpAccess, SCOPE_EXECUTE, SCOPE_READ},
    state::AppState,
};

use super::{
    authorize::{redirect_host, ClientRedirect},
    forms::FormFields,
    grants::{create_grant_with_code, GrantSpec},
    pages::{escape, form_action_source, format_time, hidden, Page, PageError},
};

#[derive(FromRow)]
struct ConsentRequestRow {
    client_id: String,
    client_name: String,
    redirect_uri: String,
    state: Option<String>,
    code_challenge: String,
    scope: String,
    resource: Option<String>,
    account_id: Option<Uuid>,
    consent_token_hash: Option<Vec<u8>>,
    expires_at: DateTime<Utc>,
    completed_at: Option<DateTime<Utc>>,
}

#[derive(FromRow)]
struct RuntimeChoice {
    id: String,
    name: String,
    last_seen_at: DateTime<Utc>,
    mcp_access: String,
}

struct ConsentView<'a> {
    request_id: Uuid,
    consent_token: &'a str,
    client_id: &'a str,
    client_name: &'a str,
    redirect_uri: &'a str,
    scope: &'a str,
    account: &'a AccountSummary,
}

/// Binds the signed-in account to the authorization request and shows the consent page.
pub async fn begin(
    state: &AppState,
    request_id: Uuid,
    account: &AccountSummary,
) -> Result<Response, PageError> {
    let consent_token = random_secret("act_");
    let row = sqlx::query_as::<_, (String, String, String, String)>(
        r#"
        UPDATE mcp_authorization_requests r
        SET account_id = $2, consent_token_hash = $3
        FROM mcp_clients c
        WHERE r.id = $1 AND c.id = r.client_id
          AND r.completed_at IS NULL AND r.expires_at > $4
        RETURNING c.client_name, r.redirect_uri, r.scope, r.client_id
        "#,
    )
    .bind(request_id)
    .bind(account.id)
    .bind(hash_secret(&consent_token))
    .bind(Utc::now())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(PageError::expired)?;
    render(
        state,
        &ConsentView {
            request_id,
            consent_token: &consent_token,
            client_id: &row.3,
            client_name: &row.0,
            redirect_uri: &row.1,
            scope: &row.2,
            account,
        },
        None,
    )
    .await
}

async fn render(
    state: &AppState,
    view: &ConsentView<'_>,
    error: Option<&str>,
) -> Result<Response, PageError> {
    let runtimes = sqlx::query_as::<_, RuntimeChoice>(
        r#"
        SELECT id, name, last_seen_at, mcp_access
        FROM runtimes
        WHERE account_id = $1 AND transferred_at IS NULL
        ORDER BY LOWER(name), id
        "#,
    )
    .bind(view.account.id)
    .fetch_all(&state.pool)
    .await?;
    let mut runtime_rows = String::new();
    for runtime in &runtimes {
        let access = runtime.mcp_access.parse().unwrap_or(McpAccess::Off);
        let status = match access {
            McpAccess::Off => "MCP Control off",
            McpAccess::Read => "MCP read only",
            McpAccess::Full => "MCP full access",
        };
        runtime_rows.push_str(&format!(
            "<label><input type=\"checkbox\" name=\"runtime\" value=\"{}\"{}><span>{}<span class=\"muted\">Last seen {}, {}</span></span></label>",
            escape(&runtime.id),
            if access == McpAccess::Off { "" } else { " checked" },
            escape(&runtime.name),
            format_time(runtime.last_seen_at),
            status
        ));
    }
    if runtimes.is_empty() {
        runtime_rows.push_str("<p class=\"muted\">No runtimes are signed in to this account yet. Choose all runtimes to include the ones you add later.</p>");
    }
    let execute = if view
        .scope
        .split_whitespace()
        .any(|scope| scope == SCOPE_EXECUTE)
    {
        "<fieldset><legend>Permissions</legend><label><input type=\"checkbox\" name=\"execute\" value=\"1\" checked><span>Run commands and change workspaces (mcp:execute). Without it the client can only read.</span></label></fieldset>"
    } else {
        ""
    };
    let error = error
        .map(|message| format!("<p class=\"error\">{}</p>", escape(message)))
        .unwrap_or_default();
    let body = format!(
        "<h1>Allow {client} to use Alera?</h1>\
<p>Signed in as <strong>{email}</strong>.</p>{origin}{error}\
<form method=\"post\" action=\"/oauth/consent\">{request}{token}\
<fieldset><legend>Runtimes</legend>\
<label><input type=\"checkbox\" name=\"all_runtimes\" value=\"1\"><span>All runtimes, including ones added later</span></label>\
{runtime_rows}</fieldset>{execute}\
<p class=\"muted\">MCP Control must also be on in each runtime. You will return to {host}.</p>\
<div class=\"row\"><button class=\"button\" type=\"submit\" name=\"action\" value=\"deny\">Deny</button>\
<button class=\"button primary\" type=\"submit\" name=\"action\" value=\"approve\">Allow</button></div></form>",
        client = escape(view.client_name),
        origin = client_origin_notice(view.client_id, view.redirect_uri),
        email = escape(&view.account.email),
        request = hidden("request", &view.request_id.to_string()),
        token = hidden("consent_token", view.consent_token),
        host = escape(&redirect_host(view.redirect_uri)),
    );
    Ok(Page::new("Allow access to Alera", body)
        .with_form_target(form_action_source(view.redirect_uri))
        .into_response())
}

pub async fn submit(State(state): State<AppState>, body: Bytes) -> Response {
    let form = FormFields::parse(&body);
    let result = if form.get("device").ok().flatten().is_some() {
        device_auth::submit_confirm(&state, &form).await
    } else {
        submit_consent(&state, &form).await
    };
    match result {
        Ok(response) => response,
        Err(error) => error.into_response(),
    }
}

async fn submit_consent(state: &AppState, form: &FormFields) -> Result<Response, PageError> {
    let read = |name: &str| {
        form.get(name)
            .map_err(|_| PageError::bad_request("A consent field is repeated."))
    };
    let request_id = read("request")?
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or_else(PageError::expired)?;
    let consent_token = read("consent_token")?.ok_or_else(PageError::expired)?;
    let approve = match read("action")? {
        Some("approve") => true,
        Some("deny") => false,
        _ => return Err(PageError::bad_request("Choose Allow or Deny.")),
    };
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let request = sqlx::query_as::<_, ConsentRequestRow>(
        r#"
        SELECT r.client_id, c.client_name, r.redirect_uri, r.state, r.code_challenge,
               r.scope, r.resource, r.account_id, r.consent_token_hash, r.expires_at,
               r.completed_at
        FROM mcp_authorization_requests r
        JOIN mcp_clients c ON c.id = r.client_id
        WHERE r.id = $1
        FOR UPDATE OF r
        "#,
    )
    .bind(request_id)
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(PageError::expired)?;
    let token_matches = request
        .consent_token_hash
        .as_deref()
        .is_some_and(|hash| bool::from(hash.ct_eq(hash_secret(consent_token).as_slice())));
    let Some(account_id) = request.account_id else {
        return Err(PageError::expired());
    };
    if !token_matches || request.completed_at.is_some() || request.expires_at <= now {
        return Err(PageError::expired());
    }
    if !state.config.mcp.enabled {
        return Err(PageError::new(
            StatusCode::NOT_FOUND,
            "Not available",
            "Remote MCP is not available right now.",
        ));
    }
    let redirect = ClientRedirect {
        redirect_uri: &request.redirect_uri,
        state: request.state.as_deref(),
        issuer: &state.config.issuer,
    };
    if !approve {
        mark_completed(&mut transaction, request_id, now).await?;
        transaction.commit().await?;
        return Ok(redirect.error("access_denied", "The person denied the request."));
    }

    let all_runtimes = form.flag("all_runtimes");
    let mut runtime_ids: Vec<String> = form
        .all("runtime")
        .into_iter()
        .map(ToOwned::to_owned)
        .collect();
    runtime_ids.sort();
    runtime_ids.dedup();
    let selection_error = if !all_runtimes && runtime_ids.is_empty() {
        Some("Choose at least one runtime, or all runtimes.")
    } else {
        let owned = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(*) FROM runtimes
            WHERE account_id = $1 AND id = ANY($2) AND transferred_at IS NULL
            "#,
        )
        .bind(account_id)
        .bind(&runtime_ids)
        .fetch_one(&mut *transaction)
        .await?;
        (owned != runtime_ids.len() as i64)
            .then_some("A selected runtime is no longer available. Choose again.")
    };
    if let Some(message) = selection_error {
        transaction.rollback().await?;
        let account = load_account_summary(&state.pool, account_id).await?;
        let view = ConsentView {
            request_id,
            consent_token,
            client_id: &request.client_id,
            client_name: &request.client_name,
            redirect_uri: &request.redirect_uri,
            scope: &request.scope,
            account: &account,
        };
        return render(state, &view, Some(message)).await;
    }

    let execute_requested = request
        .scope
        .split_whitespace()
        .any(|scope| scope == SCOPE_EXECUTE);
    let scopes = if execute_requested && form.flag("execute") {
        format!("{SCOPE_READ} {SCOPE_EXECUTE}")
    } else {
        SCOPE_READ.to_owned()
    };
    let runtime_ids = if all_runtimes {
        Vec::new()
    } else {
        runtime_ids
    };
    let code = create_grant_with_code(
        &mut transaction,
        GrantSpec {
            account_id,
            client_id: &request.client_id,
            client_name: &request.client_name,
            redirect_uri: &request.redirect_uri,
            code_challenge: &request.code_challenge,
            resource: request.resource.as_deref(),
            scopes: &scopes,
            all_runtimes,
            runtime_ids: &runtime_ids,
        },
    )
    .await?;
    mark_completed(&mut transaction, request_id, now).await?;
    transaction.commit().await?;
    Ok(redirect.send(&[("code", &code)]))
}

async fn mark_completed(
    transaction: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    request_id: Uuid,
    now: DateTime<Utc>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE mcp_authorization_requests SET completed_at = $2, consent_token_hash = NULL WHERE id = $1",
    )
    .bind(request_id)
    .bind(now)
    .execute(&mut **transaction)
    .await?;
    Ok(())
}

/// Client names are self-asserted, so the page says who actually published the
/// client and flags a redirect that leaves that publisher.
fn client_origin_notice(client_id: &str, redirect_uri: &str) -> String {
    let redirect = redirect_host(redirect_uri);
    match url::Url::parse(client_id)
        .ok()
        .filter(|url| url.scheme() == "https")
        .and_then(|url| url.host_str().map(str::to_owned))
    {
        Some(publisher) if publisher == redirect => format!(
            "<p class=\"muted\">Published by {}.</p>",
            escape(&publisher)
        ),
        Some(publisher) => format!(
            "<p class=\"error\">Published by {} but returns to {}. Continue only if you trust both.</p>",
            escape(&publisher),
            escape(&redirect)
        ),
        None => format!(
            "<p class=\"muted\">This client registered itself, so Alera has not verified its name. It returns to {}.</p>",
            escape(&redirect)
        ),
    }
}
