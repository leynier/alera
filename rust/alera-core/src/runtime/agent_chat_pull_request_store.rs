//! Pull requests linked to an agent chat (`chatOrchestrationPullRequestsV1`).
//! Additive beside the per-workspace `linkedReviews` and
//! `pullRequestWatches`, which keep their own meaning: a chat may link several
//! pull requests, in any repository, and watch some of them.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;

use super::RuntimeStore;

pub(super) const AGENT_CHAT_PULL_REQUEST_SCHEMA: &[&str] = &[
    "CREATE TABLE IF NOT EXISTS agentChatPullRequests (
        chatId TEXT NOT NULL,
        provider TEXT NOT NULL,
        number INTEGER NOT NULL,
        url TEXT NOT NULL,
        repository TEXT,
        watching INTEGER NOT NULL DEFAULT 0,
        watchStateJson TEXT,
        linkedAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        PRIMARY KEY (chatId, url)
    )",
    "CREATE INDEX IF NOT EXISTS agentChatPullRequestsWatching
        ON agentChatPullRequests (watching)",
    "CREATE TRIGGER IF NOT EXISTS agentChatPullRequestsChatDeleted
     AFTER DELETE ON agentChatSessions BEGIN
        DELETE FROM agentChatPullRequests WHERE chatId = OLD.chatId;
    END",
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatPullRequest {
    pub chat_id: String,
    pub provider: String,
    pub number: i64,
    pub url: String,
    #[serde(default)]
    pub repository: Option<String>,
    pub watching: bool,
    /// What the watch already told the chat; opaque to the store.
    #[serde(default)]
    pub watch_state: Option<Value>,
    pub linked_at: String,
    pub updated_at: String,
}

const COLUMNS: &str = "chatId, provider, number, url, repository, watching, watchStateJson, \
                       linkedAt, updatedAt";

fn from_row(row: &sqlx::sqlite::SqliteRow) -> Result<AgentChatPullRequest> {
    let state: Option<String> = row.try_get("watchStateJson")?;
    Ok(AgentChatPullRequest {
        chat_id: row.try_get("chatId")?,
        provider: row.try_get("provider")?,
        number: row.try_get("number")?,
        url: row.try_get("url")?,
        repository: row.try_get("repository")?,
        watching: row.try_get::<i64, _>("watching")? != 0,
        watch_state: state.and_then(|text| serde_json::from_str(&text).ok()),
        linked_at: row.try_get("linkedAt")?,
        updated_at: row.try_get("updatedAt")?,
    })
}

fn now() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

impl RuntimeStore {
    /// Links `url` to `chat_id`; `true` with the row when it was already
    /// linked, which leaves the row as it was.
    pub async fn link_agent_chat_pull_request(
        &self,
        chat_id: &str,
        provider: &str,
        number: i64,
        url: &str,
        repository: Option<&str>,
    ) -> Result<(AgentChatPullRequest, bool)> {
        if let Some(existing) = self.agent_chat_pull_request(chat_id, url).await? {
            return Ok((existing, true));
        }
        let now = now();
        sqlx::query(
            "INSERT INTO agentChatPullRequests (chatId, provider, number, url, repository, \
             watching, watchStateJson, linkedAt, updatedAt) VALUES (?, ?, ?, ?, ?, 0, NULL, ?, ?) \
             ON CONFLICT(chatId, url) DO NOTHING",
        )
        .bind(chat_id)
        .bind(provider)
        .bind(number)
        .bind(url)
        .bind(repository)
        .bind(&now)
        .bind(&now)
        .execute(self.pool())
        .await?;
        let row = self
            .agent_chat_pull_request(chat_id, url)
            .await?
            .ok_or_else(|| anyhow::anyhow!("The pull request link was not saved."))?;
        Ok((row, false))
    }

    pub async fn agent_chat_pull_request(
        &self,
        chat_id: &str,
        url: &str,
    ) -> Result<Option<AgentChatPullRequest>> {
        let row = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {COLUMNS} FROM agentChatPullRequests WHERE chatId = ? AND url = ?"
        )))
        .bind(chat_id)
        .bind(url)
        .fetch_optional(self.pool())
        .await?;
        row.as_ref().map(from_row).transpose()
    }

    /// Whether a link was removed.
    pub async fn unlink_agent_chat_pull_request(&self, chat_id: &str, url: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM agentChatPullRequests WHERE chatId = ? AND url = ?")
            .bind(chat_id)
            .bind(url)
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_agent_chat_pull_requests(
        &self,
        chat_id: &str,
    ) -> Result<Vec<AgentChatPullRequest>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {COLUMNS} FROM agentChatPullRequests WHERE chatId = ? ORDER BY linkedAt, url"
        )))
        .bind(chat_id)
        .fetch_all(self.pool())
        .await?;
        rows.iter().map(from_row).collect()
    }

    pub async fn list_watched_agent_chat_pull_requests(&self) -> Result<Vec<AgentChatPullRequest>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {COLUMNS} FROM agentChatPullRequests WHERE watching = 1 ORDER BY chatId, url"
        )))
        .fetch_all(self.pool())
        .await?;
        rows.iter().map(from_row).collect()
    }

    /// Starts or stops a watch with its state; `false` when `url` is not
    /// linked to `chat_id`.
    pub async fn set_agent_chat_pull_request_watch(
        &self,
        chat_id: &str,
        url: &str,
        watching: bool,
        watch_state: Option<&Value>,
    ) -> Result<bool> {
        let state = watch_state.map(Value::to_string);
        let result = sqlx::query(
            "UPDATE agentChatPullRequests SET watching = ?, watchStateJson = ?, updatedAt = ? \
             WHERE chatId = ? AND url = ?",
        )
        .bind(i64::from(watching))
        .bind(state)
        .bind(now())
        .bind(chat_id)
        .bind(url)
        .execute(self.pool())
        .await?;
        Ok(result.rows_affected() > 0)
    }
}
