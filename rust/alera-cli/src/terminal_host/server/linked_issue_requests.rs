//! `linkedIssue.*` and `issue.fetch`.
//!
//! Reads and removal run on the actor. Fetching shells out to a forge CLI that
//! can take seconds, so `issue.fetch`, `linkedIssue.link` and
//! `linkedIssue.refresh` run on a task and report back through the inbox.

use serde_json::{json, Value};

use crate::issue_tracking::{fetch_issue_url, SystemForgeCliRunner};
use crate::linked_issue_service::{
    link_workspace_issue, persist_issue_link, refresh_linked_issue, refresh_workspace_issue,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};

impl ServerActor {
    pub(super) async fn linked_issue_request(
        &mut self,
        client_id: u64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        match verb {
            "linkedIssue.list" => {
                let items = self
                    .runtime_store
                    .list_linked_issues()
                    .await
                    .map_err(state_error)?;
                Ok(json!({ "items": items }))
            }
            "linkedIssue.find" => {
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let issue = self
                    .runtime_store
                    .find_linked_issue(&workspace_id)
                    .await
                    .map_err(state_error)?;
                serde_json::to_value(issue).map_err(state_error)
            }
            "linkedIssue.remove" => {
                let workspace_id = require_string_key(payload, "workspaceId")?;
                let removed = self
                    .runtime_store
                    .remove_linked_issue(&workspace_id)
                    .await
                    .map_err(state_error)?;
                if removed {
                    self.broadcast_linked_issues_changed(Some(&workspace_id));
                }
                Ok(json!({ "removed": removed }))
            }
            _ => Err(HostError::format("Unknown linked issue request.")),
        }
    }

    pub(super) fn start_linked_issue_request(
        &self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<()> {
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        let task = match verb {
            "issue.fetch" => LinkedIssueTask::Fetch {
                url: require_string_key(payload, "url")?,
            },
            "linkedIssue.link" => LinkedIssueTask::Link {
                workspace_id: require_string_key(payload, "workspaceId")?,
                url: require_string_key(payload, "url")?,
            },
            "linkedIssue.refresh" => LinkedIssueTask::Refresh {
                workspace_id: require_string_key(payload, "workspaceId")?,
            },
            _ => return Err(HostError::format("Unknown linked issue request.")),
        };
        tokio::spawn(async move {
            let runner = SystemForgeCliRunner;
            let result = match task {
                LinkedIssueTask::Fetch { url } => fetch_issue_url(&url, &runner)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))
                    .and_then(|issue| serde_json::to_value(issue).map_err(state_error)),
                LinkedIssueTask::Link { workspace_id, url } => {
                    let changed = inbox.clone();
                    let outcome =
                        link_workspace_issue(&store, &workspace_id, &url, &runner, |_| {
                            let _ = changed.send(ServerCommand::LinkedIssuesChanged {
                                workspace_id: workspace_id.clone(),
                            });
                        })
                        .await;
                    finish_outcome(&inbox, &workspace_id, outcome)
                }
                LinkedIssueTask::Refresh { workspace_id } => {
                    let outcome = refresh_workspace_issue(&store, &workspace_id, &runner).await;
                    finish_outcome(&inbox, &workspace_id, outcome)
                }
            };
            let _ = inbox.send(ServerCommand::LinkedIssueRequestFinished {
                client_id,
                request_id,
                result,
            });
        });
        Ok(())
    }

    pub(super) fn handle_linked_issue_request_finished(
        &self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }
}

enum LinkedIssueTask {
    Fetch { url: String },
    Link { workspace_id: String, url: String },
    Refresh { workspace_id: String },
}

fn finish_outcome(
    inbox: &tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    workspace_id: &str,
    outcome: anyhow::Result<crate::linked_issue_service::LinkedIssueOutcome>,
) -> HostResult<Value> {
    let outcome = outcome.map_err(state_error)?;
    let _ = inbox.send(ServerCommand::LinkedIssuesChanged {
        workspace_id: workspace_id.to_string(),
    });
    Ok(outcome.to_json())
}

fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

/// Links the issue a `workspace.createManaged` request named, once the
/// workspace exists. A failure never fails the creation: the worktree is
/// already on disk and the user can link the issue again.
pub(super) async fn link_created_workspace_issue(
    store: &alera_core::runtime::RuntimeStore,
    inbox: &tokio::sync::mpsc::UnboundedSender<ServerCommand>,
    workspace_id: &str,
    url: &str,
) {
    let record = match persist_issue_link(store, workspace_id, url).await {
        Ok(record) => record,
        Err(error) => {
            tracing::warn!(%error, "could not link the issue of a new workspace");
            return;
        }
    };
    let _ = inbox.send(ServerCommand::LinkedIssuesChanged {
        workspace_id: workspace_id.to_string(),
    });
    if record.provider.is_none() {
        return;
    }
    if refresh_linked_issue(store, record, &SystemForgeCliRunner)
        .await
        .is_ok()
    {
        let _ = inbox.send(ServerCommand::LinkedIssuesChanged {
            workspace_id: workspace_id.to_string(),
        });
    }
}
