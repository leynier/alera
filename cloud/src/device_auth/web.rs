use axum::{
    extract::{RawQuery, State},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use sqlx::FromRow;
use subtle::ConstantTimeEq;
use uuid::Uuid;

use crate::{
    api_models::{AccountSummary, ClientKind},
    auth::{
        identity::ensure_client,
        validation::{hash_secret, random_secret},
    },
    mcp_oauth::{
        forms::FormFields,
        pages::{escape, format_time, hidden, provider_buttons, Page, PageError},
    },
    state::AppState,
};

use super::{format_user_code, normalize_user_code};

#[derive(FromRow)]
struct ConfirmRow {
    client_id: String,
    device_name: String,
    account_id: Option<Uuid>,
    consent_token_hash: Option<Vec<u8>>,
    status: String,
    expires_at: DateTime<Utc>,
}

pub async fn page(State(state): State<AppState>, RawQuery(query): RawQuery) -> Response {
    let form = FormFields::parse_query(query.as_deref());
    let Ok(Some(raw_code)) = form.get("user_code") else {
        return entry_page(None);
    };
    let Some(user_code) = normalize_user_code(raw_code) else {
        return entry_page(Some("That code is not valid. Check it and try again."));
    };
    let pending = sqlx::query_as::<_, (Uuid, String)>(
        r#"
        SELECT id, device_name FROM device_authorizations
        WHERE user_code = $1 AND status = 'pending' AND expires_at > $2
        "#,
    )
    .bind(&user_code)
    .bind(Utc::now())
    .fetch_optional(&state.pool)
    .await;
    let (id, device_name) = match pending {
        Ok(Some(row)) => row,
        Ok(None) => return entry_page(Some("That code is not valid or has expired.")),
        Err(error) => return PageError::from(error).into_response(),
    };
    let body = format!(
        "<h1>Sign in to connect a runtime</h1>\
<p>The runtime <strong>{}</strong> is waiting with code <strong>{}</strong>.</p>\
<p class=\"muted\">Sign in with the account this runtime should use.</p>{}",
        escape(&device_name),
        escape(&format_user_code(&user_code)),
        provider_buttons("device", &id.to_string()),
    );
    Page::new("Connect a runtime", body).into_response()
}

fn entry_page(error: Option<&str>) -> Response {
    let error = error
        .map(|message| format!("<p class=\"error\">{}</p>", escape(message)))
        .unwrap_or_default();
    let body = format!(
        "<h1>Connect a runtime</h1>\
<p>Enter the code shown by the runtime that is signing in.</p>{error}\
<form method=\"get\" action=\"/device\">\
<input type=\"text\" name=\"user_code\" autocomplete=\"off\" autocapitalize=\"characters\" \
spellcheck=\"false\" maxlength=\"12\" placeholder=\"ABCD-EFGH\" required>\
<button class=\"button primary\" type=\"submit\">Continue</button></form>"
    );
    Page::new("Connect a runtime", body).into_response()
}

/// Binds the signed-in account to a device request and asks the person to confirm it.
pub async fn begin_confirm(
    state: &AppState,
    device_id: Uuid,
    account: &AccountSummary,
) -> Result<Response, PageError> {
    let consent_token = random_secret("act_");
    let (device_name, user_code) = sqlx::query_as::<_, (String, String)>(
        r#"
        UPDATE device_authorizations
        SET account_id = $2, consent_token_hash = $3
        WHERE id = $1 AND status = 'pending' AND expires_at > $4
        RETURNING device_name, user_code
        "#,
    )
    .bind(device_id)
    .bind(account.id)
    .bind(hash_secret(&consent_token))
    .bind(Utc::now())
    .fetch_optional(&state.pool)
    .await?
    .ok_or_else(PageError::expired)?;
    let existing = sqlx::query_as::<_, (String, DateTime<Utc>)>(
        r#"
        SELECT r.name, r.last_seen_at
        FROM runtimes r JOIN device_authorizations d ON d.client_id = r.id
        WHERE d.id = $1 AND r.transferred_at IS NULL
        "#,
    )
    .bind(device_id)
    .fetch_optional(&state.pool)
    .await?;
    let reconnect = existing
        .map(|(name, last_seen)| {
            format!(
                "<p class=\"error\">This reconnects the existing runtime <strong>{}</strong>, last seen {}. Continue only if you are signing that machine in again.</p>",
                escape(&name),
                escape(&format_time(last_seen))
            )
        })
        .unwrap_or_default();
    let body = format!(
        "<h1>Connect this runtime?</h1>\
<p>Signed in as <strong>{}</strong>.</p>\
<p>The runtime <strong>{}</strong> asked to sign in with code <strong>{}</strong>. \
Continue only if you started this sign-in yourself.</p>{reconnect}\
<form method=\"post\" action=\"/oauth/consent\">{}{}\
<div class=\"row\"><button class=\"button\" type=\"submit\" name=\"action\" value=\"deny\">Deny</button>\
<button class=\"button primary\" type=\"submit\" name=\"action\" value=\"approve\">Connect</button></div></form>",
        escape(&account.email),
        escape(&device_name),
        escape(&format_user_code(&user_code)),
        hidden("device", &device_id.to_string()),
        hidden("consent_token", &consent_token),
    );
    Ok(Page::new("Connect a runtime", body).into_response())
}

pub async fn submit_confirm(state: &AppState, form: &FormFields) -> Result<Response, PageError> {
    let read = |name: &str| {
        form.get(name)
            .map_err(|_| PageError::bad_request("A form field is repeated."))
    };
    let device_id = read("device")?
        .and_then(|value| Uuid::parse_str(value).ok())
        .ok_or_else(PageError::expired)?;
    let consent_token = read("consent_token")?.ok_or_else(PageError::expired)?;
    let approve = match read("action")? {
        Some("approve") => true,
        Some("deny") => false,
        _ => return Err(PageError::bad_request("Choose Connect or Deny.")),
    };
    let now = Utc::now();
    let mut transaction = state.pool.begin().await?;
    let row = sqlx::query_as::<_, ConfirmRow>(
        r#"
        SELECT client_id, device_name, account_id, consent_token_hash, status, expires_at
        FROM device_authorizations
        WHERE id = $1
        FOR UPDATE
        "#,
    )
    .bind(device_id)
    .fetch_optional(&mut *transaction)
    .await?
    .ok_or_else(PageError::expired)?;
    let token_matches = row
        .consent_token_hash
        .as_deref()
        .is_some_and(|hash| bool::from(hash.ct_eq(hash_secret(consent_token).as_slice())));
    let Some(account_id) = row.account_id else {
        return Err(PageError::expired());
    };
    if !token_matches || row.status != "pending" || row.expires_at <= now {
        return Err(PageError::expired());
    }
    if !approve {
        set_status(&mut transaction, device_id, "denied", None).await?;
        transaction.commit().await?;
        return Ok(Page::new(
            "Sign-in denied",
            "<h1>Sign-in denied</h1><p>The runtime was not connected. You can close this window.</p>",
        )
        .into_response());
    }
    let ensured = ensure_client(
        state,
        &mut transaction,
        account_id,
        &row.client_id,
        &row.device_name,
        ClientKind::Runtime,
    )
    .await;
    if let Err(error) = ensured {
        transaction.rollback().await?;
        let mut transaction = state.pool.begin().await?;
        set_status(&mut transaction, device_id, "denied", None).await?;
        transaction.commit().await?;
        return Err(error.into());
    }
    set_status(&mut transaction, device_id, "approved", Some(now)).await?;
    transaction.commit().await?;
    let body = format!(
        "<h1>Runtime connected</h1><p><strong>{}</strong> finishes signing in within a few seconds. You can close this window.</p>",
        escape(&row.device_name)
    );
    Ok(Page::new("Runtime connected", body).into_response())
}

async fn set_status(
    transaction: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    device_id: Uuid,
    status: &str,
    approved_at: Option<DateTime<Utc>>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE device_authorizations
        SET status = $2, approved_at = $3, consent_token_hash = NULL
        WHERE id = $1
        "#,
    )
    .bind(device_id)
    .bind(status)
    .bind(approved_at)
    .execute(&mut **transaction)
    .await?;
    Ok(())
}
