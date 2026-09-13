use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::{format_timestamp, parse_timestamp, RuntimeStore};

/// The issue a workspace was created for. The URL is the source of truth:
/// `provider`, `repository` and `number` are only set when a provider
/// recognized it, and `title`/`state` cache the last successful fetch so the
/// sidebar renders without a network call. `fetch_error` keeps the last
/// failure, cleared by the next successful fetch.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LinkedIssue {
    pub workspace_id: String,
    pub url: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub repository: Option<String>,
    #[serde(default)]
    pub number: Option<i64>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub state: Option<String>,
    #[serde(default)]
    pub state_label: Option<String>,
    #[serde(default)]
    pub fetched_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub fetch_error: Option<String>,
    pub linked_at: DateTime<Utc>,
}

impl RuntimeStore {
    pub async fn list_linked_issues(&self) -> Result<Vec<LinkedIssue>> {
        let rows = sqlx::query(
            "SELECT workspaceId, url, provider, repository, number, title, state, stateLabel, \
             fetchedAt, fetchError, linkedAt FROM linkedIssues ORDER BY workspaceId",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(linked_issue_from_row).collect()
    }

    pub async fn find_linked_issue(&self, workspace_id: &str) -> Result<Option<LinkedIssue>> {
        let row = sqlx::query(
            "SELECT workspaceId, url, provider, repository, number, title, state, stateLabel, \
             fetchedAt, fetchError, linkedAt FROM linkedIssues WHERE workspaceId = ?",
        )
        .bind(workspace_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(linked_issue_from_row).transpose()
    }

    pub async fn upsert_linked_issue(&self, issue: LinkedIssue) -> Result<LinkedIssue> {
        sqlx::query(
            "INSERT INTO linkedIssues (workspaceId, url, provider, repository, number, title, \
             state, stateLabel, fetchedAt, fetchError, linkedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(workspaceId) DO UPDATE SET \
             url = excluded.url, provider = excluded.provider, \
             repository = excluded.repository, number = excluded.number, \
             title = excluded.title, state = excluded.state, \
             stateLabel = excluded.stateLabel, fetchedAt = excluded.fetchedAt, \
             fetchError = excluded.fetchError, linkedAt = excluded.linkedAt",
        )
        .bind(&issue.workspace_id)
        .bind(&issue.url)
        .bind(&issue.provider)
        .bind(&issue.repository)
        .bind(issue.number)
        .bind(&issue.title)
        .bind(&issue.state)
        .bind(&issue.state_label)
        .bind(issue.fetched_at.map(format_timestamp))
        .bind(&issue.fetch_error)
        .bind(format_timestamp(issue.linked_at))
        .execute(self.pool())
        .await?;
        // Read back so callers see timestamps at the stored precision.
        Ok(self
            .find_linked_issue(&issue.workspace_id)
            .await?
            .unwrap_or(issue))
    }

    /// Returns whether a link existed.
    pub async fn remove_linked_issue(&self, workspace_id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM linkedIssues WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn linked_issue_from_row(row: sqlx::sqlite::SqliteRow) -> Result<LinkedIssue> {
    Ok(LinkedIssue {
        workspace_id: row.try_get("workspaceId")?,
        url: row.try_get("url")?,
        provider: row.try_get("provider")?,
        repository: row.try_get("repository")?,
        number: row.try_get("number")?,
        title: row.try_get("title")?,
        state: row.try_get("state")?,
        state_label: row.try_get("stateLabel")?,
        fetched_at: row
            .try_get::<Option<String>, _>("fetchedAt")?
            .as_deref()
            .map(parse_timestamp),
        fetch_error: row.try_get("fetchError")?,
        linked_at: parse_timestamp(row.try_get::<String, _>("linkedAt")?.as_str()),
    })
}
