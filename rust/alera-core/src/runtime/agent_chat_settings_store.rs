//! Shared revision and receipt boundaries for host-owned chat settings.

use anyhow::Result;
use serde_json::Value;
use sqlx::SqliteConnection;

use super::agent_chat_receipts::{check_receipt_in, insert_receipt_in, require_receipt};
use super::agent_chat_secrets::reject_secret_fields;
use super::{
    AgentChatReceipt, AgentChatReceiptCheck, AgentChatSettingsOutcome, AgentChatStoreError,
    AGENT_CHAT_SETTINGS_MAX_BYTES,
};

pub(super) async fn revision_in(connection: &mut SqliteConnection, domain: &str) -> Result<i64> {
    Ok(
        sqlx::query_scalar("SELECT revision FROM agentChatSettingsRevisions WHERE domain = ?")
            .bind(domain)
            .fetch_optional(&mut *connection)
            .await?
            .unwrap_or(0),
    )
}

pub(super) async fn admit_in(
    connection: &mut SqliteConnection,
    domain: &str,
    expected_revision: i64,
    receipt: &AgentChatReceipt,
) -> Result<Option<AgentChatSettingsOutcome>> {
    require_receipt(receipt)?;
    match check_receipt_in(
        connection,
        &receipt.caller_scope,
        &receipt.request_id,
        &receipt.digest,
    )
    .await?
    {
        AgentChatReceiptCheck::Replay(value) => {
            return Ok(Some(AgentChatSettingsOutcome::Replay(value)))
        }
        AgentChatReceiptCheck::Conflict => {
            return Ok(Some(AgentChatSettingsOutcome::ReceiptConflict))
        }
        AgentChatReceiptCheck::New => {}
    }
    let revision = revision_in(connection, domain).await?;
    if expected_revision != revision {
        return Ok(Some(AgentChatSettingsOutcome::RevisionConflict {
            revision,
        }));
    }
    Ok(None)
}

pub(super) fn bounded_json(value: &Value) -> Result<String> {
    let json = serde_json::to_string(value)?;
    if json.len() > AGENT_CHAT_SETTINGS_MAX_BYTES {
        anyhow::bail!(AgentChatStoreError::Invalid(
            "agent chat settings exceed the byte budget".into()
        ));
    }
    Ok(json)
}

pub(super) async fn advance_revision_in(
    connection: &mut SqliteConnection,
    domain: &str,
    expected_revision: i64,
) -> Result<i64> {
    let next = expected_revision.checked_add(1).ok_or_else(|| {
        AgentChatStoreError::Invalid("agent chat settings revision exhausted".into())
    })?;
    sqlx::query(
        "INSERT INTO agentChatSettingsRevisions (domain, revision) VALUES (?, ?) \
         ON CONFLICT(domain) DO UPDATE SET revision = excluded.revision",
    )
    .bind(domain)
    .bind(next)
    .execute(&mut *connection)
    .await?;
    Ok(next)
}

pub(super) async fn finish_in(
    connection: &mut SqliteConnection,
    response: Value,
    receipt: &AgentChatReceipt,
) -> Result<AgentChatSettingsOutcome> {
    bounded_json(&response)?;
    reject_secret_fields("settings response", &response)?;
    let stored = AgentChatReceipt {
        caller_scope: receipt.caller_scope.clone(),
        request_id: receipt.request_id.clone(),
        digest: receipt.digest.clone(),
        receipt: response.clone(),
    };
    insert_receipt_in(connection, None, None, &stored).await?;
    Ok(AgentChatSettingsOutcome::Applied(response))
}
