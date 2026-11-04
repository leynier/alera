//! Row mapping and input bounds shared by the chat orchestration stores.

use anyhow::{Context, Result};
use sqlx::sqlite::SqliteRow;
use sqlx::{Row, SqliteConnection};

use super::chat_orchestration_models::*;
use super::parse_timestamp;

pub(super) const TASK_COLUMNS: &str = "sequence, taskId, kind, status, revision, callerScope, \
     parentTaskId, rootTaskId, depth, parentChatId, rootChatId, childChatId, childTurnId, \
     projectId, workspaceId, hostId, targetJson, title, role, brief, notify, launchOptionsJson, resultText, \
     resultTruncated, resultDelivery, errorCode, error, createdAt, updatedAt, cancelRequestedAt, settledAt";

pub(super) fn invalid(message: impl Into<String>) -> anyhow::Error {
    ChatOrchestrationStoreError::Invalid(message.into()).into()
}

pub(super) fn conflict(message: impl Into<String>) -> anyhow::Error {
    ChatOrchestrationStoreError::Conflict(message.into()).into()
}

pub(super) fn not_found(task_id: &str) -> anyhow::Error {
    ChatOrchestrationStoreError::NotFound(task_id.to_string()).into()
}

pub(super) fn require_id(label: &str, value: &str) -> Result<()> {
    if value.trim().is_empty() || value.trim() != value {
        return Err(invalid(format!(
            "{label} must be a non-empty trimmed string"
        )));
    }
    if value.len() > CHAT_ORCHESTRATION_ID_MAX_BYTES {
        return Err(invalid(format!(
            "{label} exceeds {CHAT_ORCHESTRATION_ID_MAX_BYTES} bytes"
        )));
    }
    Ok(())
}

pub(super) fn require_optional_id(label: &str, value: Option<&str>) -> Result<()> {
    value.map_or(Ok(()), |value| require_id(label, value))
}

pub(super) fn require_bounded(label: &str, value: &str, max: usize) -> Result<()> {
    if value.len() > max {
        return Err(invalid(format!("{label} exceeds {max} bytes")));
    }
    Ok(())
}

/// Keeps the leading `max` bytes on a character boundary.
pub(super) fn truncate_utf8(text: &str, max: usize) -> (String, bool) {
    if text.len() <= max {
        return (text.to_string(), false);
    }
    let mut end = max;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    (text[..end].to_string(), true)
}

fn parse_enum<T>(label: &str, value: &str, parse: impl Fn(&str) -> Option<T>) -> Result<T> {
    parse(value).with_context(|| format!("unknown chat orchestration {label}: {value}"))
}

fn optional_timestamp(
    row: &SqliteRow,
    column: &str,
) -> Result<Option<chrono::DateTime<chrono::Utc>>> {
    Ok(row
        .try_get::<Option<String>, _>(column)?
        .map(|value| parse_timestamp(&value)))
}

pub(super) fn task_from_row(row: &SqliteRow) -> Result<ChatOrchestrationTask> {
    let launch_options: Option<String> = row.try_get("launchOptionsJson")?;
    Ok(ChatOrchestrationTask {
        task_id: row.try_get("taskId")?,
        sequence: row.try_get("sequence")?,
        kind: parse_enum(
            "kind",
            row.try_get("kind")?,
            ChatOrchestrationTaskKind::parse,
        )?,
        status: parse_enum(
            "status",
            row.try_get("status")?,
            ChatOrchestrationTaskStatus::parse,
        )?,
        revision: row.try_get("revision")?,
        caller_scope: row.try_get("callerScope")?,
        parent_task_id: row.try_get("parentTaskId")?,
        root_task_id: row.try_get("rootTaskId")?,
        depth: row.try_get("depth")?,
        parent_chat_id: row.try_get("parentChatId")?,
        root_chat_id: row.try_get("rootChatId")?,
        child_chat_id: row.try_get("childChatId")?,
        child_turn_id: row.try_get("childTurnId")?,
        project_id: row.try_get("projectId")?,
        workspace_id: row.try_get("workspaceId")?,
        host_id: row.try_get("hostId")?,
        target: serde_json::from_str(row.try_get("targetJson")?)?,
        title: row.try_get("title")?,
        role: row.try_get("role")?,
        brief: row.try_get("brief")?,
        notify: parse_enum(
            "notify",
            row.try_get("notify")?,
            ChatOrchestrationNotify::parse,
        )?,
        launch_options: launch_options
            .map(|json| serde_json::from_str(&json))
            .transpose()?,
        result_text: row.try_get("resultText")?,
        result_truncated: row.try_get::<i64, _>("resultTruncated")? != 0,
        result_delivery: parse_enum(
            "result delivery",
            row.try_get("resultDelivery")?,
            ChatOrchestrationResultDelivery::parse,
        )?,
        error_code: row.try_get("errorCode")?,
        error: row.try_get("error")?,
        created_at: parse_timestamp(row.try_get("createdAt")?),
        updated_at: parse_timestamp(row.try_get("updatedAt")?),
        cancel_requested_at: optional_timestamp(row, "cancelRequestedAt")?,
        settled_at: optional_timestamp(row, "settledAt")?,
    })
}

pub(super) async fn task_in(
    connection: &mut SqliteConnection,
    task_id: &str,
) -> Result<Option<ChatOrchestrationTask>> {
    let row = sqlx::query(sqlx::AssertSqlSafe(format!(
        "SELECT {TASK_COLUMNS} FROM chatOrchestrationTasks WHERE taskId = ?"
    )))
    .bind(task_id)
    .fetch_optional(&mut *connection)
    .await?;
    row.as_ref().map(task_from_row).transpose()
}

pub(super) async fn require_task_in(
    connection: &mut SqliteConnection,
    task_id: &str,
) -> Result<ChatOrchestrationTask> {
    task_in(connection, task_id)
        .await?
        .ok_or_else(|| not_found(task_id))
}
