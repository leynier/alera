//! Linking an issue to a workspace, shared by the runtime host verbs and the
//! `alera workspace issue` commands when no host is running.
//!
//! The URL is persisted before anything touches the network, so a link
//! survives a missing CLI, a signed-out forge or a tracker Alera cannot read.
//! The fetch only fills in the cached title and state.

use alera_core::runtime::{LinkedIssue, RuntimeStore};
use anyhow::{anyhow, Result};
use chrono::Utc;
use serde_json::{json, Value};

use crate::issue_tracking::{
    fetch_issue, parse_issue_reference, ForgeCliRunner, IssueDetails, IssueFetchError,
};

/// What a link or refresh produced: the stored record, the fresh issue when
/// the fetch worked, and why it did not otherwise.
#[derive(Debug, Clone)]
pub struct LinkedIssueOutcome {
    pub linked_issue: LinkedIssue,
    pub issue: Option<IssueDetails>,
    pub fetch_error: Option<IssueFetchError>,
}

impl LinkedIssueOutcome {
    pub fn to_json(&self) -> Value {
        json!({
            "linkedIssue": self.linked_issue,
            "issue": self.issue,
            "fetchError": self.fetch_error.as_ref().map(IssueFetchError::to_json),
        })
    }
}

/// Validates [url] and stores it as the workspace's linked issue without
/// fetching anything. Relinking the same URL keeps the cached metadata.
pub async fn persist_issue_link(
    store: &RuntimeStore,
    workspace_id: &str,
    url: &str,
) -> Result<LinkedIssue> {
    if store.find_workspace(workspace_id).await?.is_none() {
        return Err(anyhow!("Workspace not found: {workspace_id}"));
    }
    let reference = parse_issue_reference(url).map_err(|error| anyhow!(error.to_string()))?;
    if let Some(existing) = store.find_linked_issue(workspace_id).await? {
        if existing.url == reference.url {
            return Ok(existing);
        }
    }
    let record = LinkedIssue {
        workspace_id: workspace_id.to_string(),
        url: reference.url,
        provider: reference
            .provider
            .map(|provider| provider.wire_name().to_string()),
        repository: reference.repository,
        number: reference.number,
        title: None,
        state: None,
        state_label: None,
        fetched_at: None,
        fetch_error: None,
        linked_at: Utc::now(),
    };
    store.upsert_linked_issue(record).await
}

/// Fetches the issue behind [record] and caches the result. The write is
/// skipped when the link changed or disappeared while the fetch ran, so a
/// slow forge cannot resurrect an unlinked issue.
pub async fn refresh_linked_issue(
    store: &RuntimeStore,
    record: LinkedIssue,
    runner: &dyn ForgeCliRunner,
) -> Result<LinkedIssueOutcome> {
    let reference =
        parse_issue_reference(&record.url).map_err(|error| anyhow!(error.to_string()))?;
    if reference.provider.is_none() {
        let fetch_error = fetch_issue(&reference, runner).await.err();
        return Ok(LinkedIssueOutcome {
            linked_issue: record,
            issue: None,
            fetch_error,
        });
    }
    let fetched = fetch_issue(&reference, runner).await;
    let current = store.find_linked_issue(&record.workspace_id).await?;
    let Some(current) = current.filter(|current| current.url == record.url) else {
        return Ok(LinkedIssueOutcome {
            linked_issue: record,
            issue: fetched.as_ref().ok().cloned(),
            fetch_error: fetched.err(),
        });
    };
    let (updated, issue, fetch_error) = match fetched {
        Ok(issue) => (
            LinkedIssue {
                title: Some(issue.title.clone()).filter(|title| !title.is_empty()),
                state: Some(issue.state.wire_name().to_string()),
                state_label: issue.state_label.clone(),
                number: Some(issue.number),
                repository: issue.repository.clone().or(current.repository.clone()),
                fetched_at: Some(Utc::now()),
                fetch_error: None,
                ..current
            },
            Some(issue),
            None,
        ),
        Err(error) => (
            LinkedIssue {
                fetch_error: Some(error.to_string()),
                ..current
            },
            None,
            Some(error),
        ),
    };
    let linked_issue = store.upsert_linked_issue(updated).await?;
    Ok(LinkedIssueOutcome {
        linked_issue,
        issue,
        fetch_error,
    })
}

/// Persists the link, reports it through [on_persisted] (the host broadcasts
/// there), then fetches and caches the metadata.
pub async fn link_workspace_issue(
    store: &RuntimeStore,
    workspace_id: &str,
    url: &str,
    runner: &dyn ForgeCliRunner,
    on_persisted: impl FnOnce(&LinkedIssue),
) -> Result<LinkedIssueOutcome> {
    let record = persist_issue_link(store, workspace_id, url).await?;
    on_persisted(&record);
    refresh_linked_issue(store, record, runner).await
}

pub async fn refresh_workspace_issue(
    store: &RuntimeStore,
    workspace_id: &str,
    runner: &dyn ForgeCliRunner,
) -> Result<LinkedIssueOutcome> {
    let record = store
        .find_linked_issue(workspace_id)
        .await?
        .ok_or_else(|| anyhow!("Workspace {workspace_id} has no linked issue"))?;
    refresh_linked_issue(store, record, runner).await
}

#[cfg(test)]
#[path = "linked_issue_service_tests.rs"]
mod tests;
