use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::RuntimeStore;

/// What Watch and Fix already asked the bound agent to fix on one head.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestWatchDispatchMark {
    #[serde(default)]
    pub head_sha: Option<String>,
    #[serde(default)]
    pub checks_failed: bool,
    #[serde(default)]
    pub conflict: bool,
    #[serde(default)]
    pub thread_ids: Vec<String>,
}

/// Persisted Watch and Fix / Watch, Fix and Merge session for one workspace.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestWatch {
    pub workspace_id: String,
    pub review_number: i64,
    pub mode: String,
    pub checks: bool,
    pub comments: bool,
    pub conflicts: bool,
    #[serde(default)]
    pub tab_id: Option<String>,
    #[serde(default)]
    pub profile_id: Option<String>,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub last_dispatch: Option<PullRequestWatchDispatchMark>,
    #[serde(default)]
    pub last_merged_head_sha: Option<String>,
}

impl PullRequestWatch {
    pub fn validate(&self) -> Result<()> {
        if self.workspace_id.trim().is_empty() {
            bail!("workspaceId is required.");
        }
        if self.review_number <= 0 {
            bail!("reviewNumber must be a positive pull request number.");
        }
        if self.mode != "fix" && self.mode != "fixAndMerge" {
            bail!("mode must be fix or fixAndMerge.");
        }
        if !self.checks && !self.comments && !self.conflicts {
            bail!("Choose at least one of checks, comments, or conflicts.");
        }
        if self
            .tab_id
            .as_ref()
            .is_none_or(|value| value.trim().is_empty())
            && self
                .profile_id
                .as_ref()
                .is_none_or(|value| value.trim().is_empty())
        {
            bail!("A running terminal or an agent profile is required.");
        }
        Ok(())
    }
}

impl RuntimeStore {
    pub async fn list_pull_request_watches(&self) -> Result<Vec<PullRequestWatch>> {
        let rows = sqlx::query(
            "SELECT workspaceId, reviewNumber, mode, checks, comments, conflicts, tabId, \
             profileId, label, lastDispatchJson, lastMergedHeadSha \
             FROM pullRequestWatches ORDER BY workspaceId",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(watch_from_row).collect()
    }

    pub async fn find_pull_request_watch(
        &self,
        workspace_id: &str,
    ) -> Result<Option<PullRequestWatch>> {
        let row = sqlx::query(
            "SELECT workspaceId, reviewNumber, mode, checks, comments, conflicts, tabId, \
             profileId, label, lastDispatchJson, lastMergedHeadSha \
             FROM pullRequestWatches WHERE workspaceId = ?",
        )
        .bind(workspace_id)
        .fetch_optional(self.pool())
        .await?;
        row.map(watch_from_row).transpose()
    }

    pub async fn upsert_pull_request_watch(
        &self,
        watch: PullRequestWatch,
    ) -> Result<PullRequestWatch> {
        watch.validate()?;
        let last_dispatch_json = match &watch.last_dispatch {
            Some(mark) => Some(serde_json::to_string(mark)?),
            None => None,
        };
        sqlx::query(
            "INSERT INTO pullRequestWatches (workspaceId, reviewNumber, mode, checks, comments, \
             conflicts, tabId, profileId, label, lastDispatchJson, lastMergedHeadSha) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(workspaceId) DO UPDATE SET \
             reviewNumber = excluded.reviewNumber, mode = excluded.mode, \
             checks = excluded.checks, comments = excluded.comments, \
             conflicts = excluded.conflicts, tabId = excluded.tabId, \
             profileId = excluded.profileId, label = excluded.label, \
             lastDispatchJson = excluded.lastDispatchJson, \
             lastMergedHeadSha = excluded.lastMergedHeadSha",
        )
        .bind(&watch.workspace_id)
        .bind(watch.review_number)
        .bind(&watch.mode)
        .bind(i64::from(watch.checks))
        .bind(i64::from(watch.comments))
        .bind(i64::from(watch.conflicts))
        .bind(&watch.tab_id)
        .bind(&watch.profile_id)
        .bind(&watch.label)
        .bind(last_dispatch_json)
        .bind(&watch.last_merged_head_sha)
        .execute(self.pool())
        .await?;
        Ok(self
            .find_pull_request_watch(&watch.workspace_id)
            .await?
            .unwrap_or(watch))
    }

    pub async fn remove_pull_request_watch(&self, workspace_id: &str) -> Result<bool> {
        let result = sqlx::query("DELETE FROM pullRequestWatches WHERE workspaceId = ?")
            .bind(workspace_id)
            .execute(self.pool())
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn watch_from_row(row: sqlx::sqlite::SqliteRow) -> Result<PullRequestWatch> {
    let last_dispatch = match row.try_get::<Option<String>, _>("lastDispatchJson")? {
        Some(raw) if !raw.trim().is_empty() => Some(serde_json::from_str(&raw)?),
        _ => None,
    };
    Ok(PullRequestWatch {
        workspace_id: row.try_get("workspaceId")?,
        review_number: row.try_get("reviewNumber")?,
        mode: row.try_get("mode")?,
        checks: row.try_get::<i64, _>("checks")? != 0,
        comments: row.try_get::<i64, _>("comments")? != 0,
        conflicts: row.try_get::<i64, _>("conflicts")? != 0,
        tab_id: row.try_get("tabId")?,
        profile_id: row.try_get("profileId")?,
        label: row.try_get("label")?,
        last_dispatch,
        last_merged_head_sha: row.try_get("lastMergedHeadSha")?,
    })
}
