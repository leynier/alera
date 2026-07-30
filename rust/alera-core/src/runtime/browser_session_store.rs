use anyhow::Result;
use sqlx::Row;

use super::browser_privacy::{
    browser_url_allows_title_persistence, browser_url_for_persistence, normalize_browser_title,
    sanitize_browser_tab_payload,
};
use super::{
    format_timestamp, parse_timestamp, BrowserClosedTab, BrowserHistoryEntry, RuntimeStore,
    RuntimeStoreError,
};

const HISTORY_COLUMNS: &str =
    "id, profileId, workspaceId, tabId, url, title, visitCount, visitedAt";
const CLOSED_TAB_COLUMNS: &str = "id, profileId, workspaceId, url, title, payloadJson, closedAt";
const MAX_LIST_LIMIT: i64 = 1_000;

impl RuntimeStore {
    pub async fn record_browser_history(
        &self,
        entry: BrowserHistoryEntry,
    ) -> Result<BrowserHistoryEntry> {
        let mut entry = normalize_history(entry)?;
        let mut tx = self.pool().begin().await?;
        let existing = sqlx::query(
            "SELECT id, visitCount FROM browserHistory WHERE profileId = ? AND url = ? LIMIT 1",
        )
        .bind(&entry.profile_id)
        .bind(&entry.url)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(existing) = existing {
            entry.id = existing.try_get("id")?;
            entry.visit_count = existing.try_get::<i64, _>("visitCount")?.saturating_add(1);
            sqlx::query(
                "UPDATE browserHistory SET workspaceId = ?, tabId = ?, title = ?, \
                 visitCount = ?, visitedAt = ? WHERE id = ?",
            )
            .bind(&entry.workspace_id)
            .bind(&entry.tab_id)
            .bind(&entry.title)
            .bind(entry.visit_count)
            .bind(format_timestamp(entry.visited_at))
            .bind(&entry.id)
            .execute(&mut *tx)
            .await?;
        } else {
            sqlx::query(
                "INSERT INTO browserHistory \
                 (id, profileId, workspaceId, tabId, url, title, visitCount, visitedAt) \
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(&entry.id)
            .bind(&entry.profile_id)
            .bind(&entry.workspace_id)
            .bind(&entry.tab_id)
            .bind(&entry.url)
            .bind(&entry.title)
            .bind(entry.visit_count)
            .bind(format_timestamp(entry.visited_at))
            .execute(&mut *tx)
            .await?;
        }
        sqlx::query(
            "DELETE FROM browserHistory WHERE profileId = ? AND id NOT IN \
             (SELECT id FROM browserHistory WHERE profileId = ? \
              ORDER BY visitedAt DESC LIMIT 200)",
        )
        .bind(&entry.profile_id)
        .bind(&entry.profile_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(entry)
    }

    pub async fn list_browser_history(
        &self,
        profile_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<BrowserHistoryEntry>> {
        let limit = normalized_limit(limit);
        let rows = if let Some(profile_id) = profile_id {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {HISTORY_COLUMNS} FROM browserHistory \
                 WHERE profileId = ? ORDER BY visitedAt DESC LIMIT ?"
            )))
            .bind(profile_id.trim())
            .bind(limit)
            .fetch_all(self.pool())
            .await?
        } else {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {HISTORY_COLUMNS} FROM browserHistory \
                 ORDER BY visitedAt DESC LIMIT ?"
            )))
            .bind(limit)
            .fetch_all(self.pool())
            .await?
        };
        rows.into_iter().map(browser_history_from_row).collect()
    }

    pub async fn clear_browser_history(&self, profile_id: Option<&str>) -> Result<u64> {
        let result = if let Some(profile_id) = profile_id {
            sqlx::query("DELETE FROM browserHistory WHERE profileId = ?")
                .bind(profile_id.trim())
                .execute(self.pool())
                .await?
        } else {
            sqlx::query("DELETE FROM browserHistory")
                .execute(self.pool())
                .await?
        };
        Ok(result.rows_affected())
    }

    pub async fn record_closed_browser_tab(
        &self,
        tab: BrowserClosedTab,
    ) -> Result<BrowserClosedTab> {
        let tab = normalize_closed_tab(tab)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "INSERT INTO browserClosedTabs \
             (id, profileId, workspaceId, url, title, payloadJson, closedAt) \
             VALUES (?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET profileId = excluded.profileId, \
             workspaceId = excluded.workspaceId, url = excluded.url, \
             title = excluded.title, payloadJson = excluded.payloadJson, \
             closedAt = excluded.closedAt",
        )
        .bind(&tab.id)
        .bind(&tab.profile_id)
        .bind(&tab.workspace_id)
        .bind(&tab.url)
        .bind(&tab.title)
        .bind(serde_json::to_string(&tab.payload)?)
        .bind(format_timestamp(tab.closed_at))
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "DELETE FROM browserClosedTabs WHERE id NOT IN \
             (SELECT id FROM browserClosedTabs ORDER BY closedAt DESC LIMIT 10)",
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(tab)
    }

    pub async fn list_closed_browser_tabs(
        &self,
        profile_id: Option<&str>,
        limit: i64,
    ) -> Result<Vec<BrowserClosedTab>> {
        let limit = normalized_limit(limit);
        let rows = if let Some(profile_id) = profile_id {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {CLOSED_TAB_COLUMNS} FROM browserClosedTabs \
                 WHERE profileId = ? ORDER BY closedAt DESC LIMIT ?"
            )))
            .bind(profile_id.trim())
            .bind(limit)
            .fetch_all(self.pool())
            .await?
        } else {
            sqlx::query(sqlx::AssertSqlSafe(format!(
                "SELECT {CLOSED_TAB_COLUMNS} FROM browserClosedTabs \
                 ORDER BY closedAt DESC LIMIT ?"
            )))
            .bind(limit)
            .fetch_all(self.pool())
            .await?
        };
        rows.into_iter().map(closed_browser_tab_from_row).collect()
    }

    pub async fn remove_closed_browser_tab(&self, id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM browserClosedTabs WHERE id = ?")
            .bind(id.trim())
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn normalize_history(mut entry: BrowserHistoryEntry) -> Result<BrowserHistoryEntry> {
    entry.id = required(&entry.id, "browser history id")?;
    entry.profile_id = required(&entry.profile_id, "browser profile id")?;
    let title_may_persist = browser_url_allows_title_persistence(&entry.url);
    entry.url = safe_url(&entry.url)?;
    entry.title = if title_may_persist {
        normalize_browser_title(&entry.title)
    } else {
        String::new()
    };
    entry.visit_count = entry.visit_count.max(1);
    entry.workspace_id = optional(entry.workspace_id);
    entry.tab_id = optional(entry.tab_id);
    Ok(entry)
}

fn normalize_closed_tab(mut tab: BrowserClosedTab) -> Result<BrowserClosedTab> {
    tab.id = required(&tab.id, "closed browser tab id")?;
    tab.profile_id = required(&tab.profile_id, "browser profile id")?;
    tab.workspace_id = required(&tab.workspace_id, "workspace id")?;
    tab.url = safe_url(&tab.url)?;
    tab.title = normalize_browser_title(&tab.title);
    if tab.payload.is_null() {
        tab.payload = serde_json::json!({});
    }
    sanitize_browser_tab_payload("browser", &mut tab.payload);
    Ok(tab)
}

fn safe_url(value: &str) -> Result<String> {
    let value = required(value, "browser URL")?;
    browser_url_for_persistence(&value).ok_or_else(|| {
        RuntimeStoreError::Message("browser URL cannot be persisted".to_string()).into()
    })
}

fn required(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        anyhow::bail!(RuntimeStoreError::Message(format!("{label} is required")));
    }
    Ok(value.to_string())
}

fn optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn normalized_limit(limit: i64) -> i64 {
    limit.clamp(1, MAX_LIST_LIMIT)
}

fn browser_history_from_row(row: sqlx::sqlite::SqliteRow) -> Result<BrowserHistoryEntry> {
    Ok(BrowserHistoryEntry {
        id: row.try_get("id")?,
        profile_id: row.try_get("profileId")?,
        workspace_id: row.try_get("workspaceId")?,
        tab_id: row.try_get("tabId")?,
        url: row.try_get("url")?,
        title: row.try_get("title")?,
        visit_count: row.try_get("visitCount")?,
        visited_at: parse_timestamp(row.try_get::<String, _>("visitedAt")?.as_str()),
    })
}

fn closed_browser_tab_from_row(row: sqlx::sqlite::SqliteRow) -> Result<BrowserClosedTab> {
    let payload_json: String = row.try_get("payloadJson")?;
    Ok(BrowserClosedTab {
        id: row.try_get("id")?,
        profile_id: row.try_get("profileId")?,
        workspace_id: row.try_get("workspaceId")?,
        url: row.try_get("url")?,
        title: row.try_get("title")?,
        payload: serde_json::from_str(&payload_json).unwrap_or_else(|_| serde_json::json!({})),
        closed_at: parse_timestamp(row.try_get::<String, _>("closedAt")?.as_str()),
    })
}
