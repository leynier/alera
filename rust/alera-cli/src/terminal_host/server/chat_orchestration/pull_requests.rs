//! Pull requests linked to a chat (`chatOrchestrationPullRequestsV1`):
//! `linkPullRequest`, `unlinkPullRequest`, `listPullRequests` and
//! `watchPullRequest`. A bound agent acts on its own chat or a chat it
//! delegated; a delegated child links but never watches.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::authorization::{require_lineage_for_chat, OrchestrationCaller};
use super::service::ChatOrchestrationService;

pub(crate) const CHILD_CANNOT_WATCH: &str = "This chat is a delegated child, so it cannot watch pull requests. Its parent chat owns the pull request: finish your task and report back instead.";
const CHILD_NEXT: &str =
    "End your reply with: PR <full URL>, head <SHA>, checks and reviews <state>.";

/// A pull request named by its web URL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PullRequestRef {
    pub provider: &'static str,
    pub repository: String,
    pub number: i64,
    pub url: String,
}

/// GitHub `/<owner>/<repo>/pull/<n>`, GitLab `/<group>/<repo>/-/merge_requests/<n>`
/// and Azure DevOps `/<org>/<project>/_git/<repo>/pullrequest/<n>`.
pub(crate) fn parse_pull_request_url(raw: &str) -> HostResult<PullRequestRef> {
    let invalid = || HostError::format("This is not a recognised pull request URL.");
    let parsed = url::Url::parse(raw.trim()).map_err(|_| invalid())?;
    if !matches!(parsed.scheme(), "https" | "http") || parsed.host_str().is_none() {
        return Err(invalid());
    }
    let segments: Vec<&str> = parsed
        .path_segments()
        .map(|segments| segments.filter(|segment| !segment.is_empty()).collect())
        .unwrap_or_default();
    let number_at = |index: usize| {
        segments
            .get(index)
            .and_then(|text| text.parse::<i64>().ok())
            .filter(|number| *number > 0)
    };
    let found = |provider, repository: String, number: i64, tail: usize| {
        let mut url = parsed.clone();
        url.set_query(None);
        url.set_fragment(None);
        url.set_path(&segments[..tail].join("/"));
        PullRequestRef {
            provider,
            repository,
            number,
            url: url.to_string(),
        }
    };
    if let Some(at) = segments
        .iter()
        .position(|segment| *segment == "merge_requests")
    {
        if at >= 3 && segments[at - 1] == "-" {
            if let Some(number) = number_at(at + 1) {
                return Ok(found(
                    "gitlab",
                    segments[..at - 1].join("/"),
                    number,
                    at + 2,
                ));
            }
        }
    }
    if let Some(at) = segments
        .iter()
        .position(|segment| *segment == "pullrequest")
    {
        if at >= 3 && segments[at - 2] == "_git" {
            if let Some(number) = number_at(at + 1) {
                let repository = format!("{}/{}", segments[..at - 2].join("/"), segments[at - 1]);
                return Ok(found("azureDevOps", repository, number, at + 2));
            }
        }
    }
    if segments.len() >= 4 && segments[2] == "pull" {
        if let Some(number) = number_at(3) {
            return Ok(found(
                "github",
                format!("{}/{}", segments[0], segments[1]),
                number,
                4,
            ));
        }
    }
    Err(invalid())
}

fn target(caller: &OrchestrationCaller, chat_id: Option<&str>) -> HostResult<String> {
    super::titles::title_target(caller, chat_id)
}

fn state_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

impl ChatOrchestrationService {
    /// Whether `chat_id` is a delegated child, by its lineage or an open task.
    pub(super) async fn is_child_chat(&self, chat_id: &str) -> HostResult<bool> {
        if self
            .store
            .active_chat_orchestration_task_for_child(chat_id)
            .await
            .map_err(state_error)?
            .is_some()
        {
            return Ok(true);
        }
        let snapshot = self.runtime.snapshot(chat_id).await?;
        Ok(snapshot["lineage"]["parentChatId"].is_string())
    }

    pub(super) async fn link_pull_request(
        &self,
        chat_id: Option<String>,
        url: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat_id = target(caller, chat_id.as_deref())?;
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        self.runtime.snapshot(&chat_id).await?;
        let pull_request = parse_pull_request_url(url)?;
        let (_, already) = self
            .store
            .link_agent_chat_pull_request(
                &chat_id,
                pull_request.provider,
                pull_request.number,
                &pull_request.url,
                Some(&pull_request.repository),
            )
            .await
            .map_err(state_error)?;
        let mut result = json!({
            "chatId": chat_id,
            "provider": pull_request.provider,
            "repository": pull_request.repository,
            "number": pull_request.number,
            "url": pull_request.url,
            "alreadyLinked": already,
        });
        if self.is_child_chat(&chat_id).await? {
            result["next"] = json!(CHILD_NEXT);
        }
        Ok(result)
    }

    pub(super) async fn unlink_pull_request(
        &self,
        chat_id: Option<String>,
        url: &str,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat_id = target(caller, chat_id.as_deref())?;
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let pull_request = parse_pull_request_url(url)?;
        let was_linked = self
            .store
            .unlink_agent_chat_pull_request(&chat_id, &pull_request.url)
            .await
            .map_err(state_error)?;
        Ok(json!({
            "chatId": chat_id,
            "provider": pull_request.provider,
            "repository": pull_request.repository,
            "number": pull_request.number,
            "url": pull_request.url,
            "wasLinked": was_linked,
        }))
    }

    pub(super) async fn list_pull_requests(
        &self,
        chat_id: Option<String>,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat_id = target(caller, chat_id.as_deref())?;
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let rows = self
            .store
            .list_agent_chat_pull_requests(&chat_id)
            .await
            .map_err(state_error)?;
        let pull_requests: Vec<Value> = rows
            .into_iter()
            .map(|row| {
                json!({
                    "provider": row.provider,
                    "repository": row.repository,
                    "number": row.number,
                    "url": row.url,
                    "watching": row.watching,
                    "linkedAt": row.linked_at,
                })
            })
            .collect();
        Ok(json!({"chatId": chat_id, "pullRequests": pull_requests}))
    }

    /// Watches (linking first when needed) or stops watching a pull request.
    pub(super) async fn watch_pull_request(
        &self,
        chat_id: Option<String>,
        url: &str,
        watching: bool,
        caller: &OrchestrationCaller,
    ) -> HostResult<Value> {
        let chat_id = target(caller, chat_id.as_deref())?;
        require_lineage_for_chat(caller, &self.store, &chat_id).await?;
        let pull_request = parse_pull_request_url(url)?;
        if watching && self.is_child_chat(&chat_id).await? {
            return Err(HostError::conflict(
                "childCannotWatch",
                CHILD_CANNOT_WATCH,
                json!({}),
            ));
        }
        let existing = self
            .store
            .agent_chat_pull_request(&chat_id, &pull_request.url)
            .await
            .map_err(state_error)?;
        let was_watching = existing.as_ref().is_some_and(|row| row.watching);
        if watching && existing.is_none() {
            self.link_pull_request(Some(chat_id.clone()), url, caller)
                .await?;
        }
        if existing.is_some() || watching {
            let state = if watching && !was_watching {
                Some(
                    crate::terminal_host::server::chat_pull_request_notices::start_state(
                        existing.as_ref().and_then(|row| row.watch_state.as_ref()),
                        None,
                    ),
                )
            } else {
                existing.as_ref().and_then(|row| row.watch_state.clone())
            };
            self.store
                .set_agent_chat_pull_request_watch(
                    &chat_id,
                    &pull_request.url,
                    watching,
                    state.as_ref(),
                )
                .await
                .map_err(state_error)?;
        }
        Ok(json!({
            "chatId": chat_id,
            "provider": pull_request.provider,
            "repository": pull_request.repository,
            "number": pull_request.number,
            "url": pull_request.url,
            "watching": watching,
            "wasWatching": was_watching,
        }))
    }
}
