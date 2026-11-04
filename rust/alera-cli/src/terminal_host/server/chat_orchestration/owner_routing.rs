//! Scheduled tasks and pull request links of a chat on another host. They
//! live on the host that owns the chat: that host runs the automation that
//! posts into the chat, and reads the pull request in the chat's checkout.
//! So a person (or an agent in the chat's lineage) on this host reaches them
//! through the owner, after this host checks what only it knows (the
//! delegation ledger), and the owner answers as it would for a local person.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::authorization::{require_lineage_for_chat, OrchestrationCaller};
use super::models::{OrchestrationRequest, PullRequestAction};
use super::pull_requests::CHILD_CANNOT_WATCH;
use super::service::ChatOrchestrationService;

/// The verbs whose data lives with the chat's host.
pub(crate) fn is_owner_scoped_verb(verb: &str) -> bool {
    matches!(
        verb,
        "scheduleTask"
            | "listScheduledTasks"
            | "deleteScheduledTask"
            | "runScheduledTaskNow"
            | "linkPullRequest"
            | "unlinkPullRequest"
            | "listPullRequests"
            | "watchPullRequest"
            | "unwatchPullRequest"
    )
}

/// The capability the owner must advertise for `verb`.
pub(crate) fn owner_scoped_capability(verb: &str) -> Option<(&'static str, &'static str)> {
    match verb {
        "scheduleTask" | "listScheduledTasks" | "deleteScheduledTask" | "runScheduledTaskNow" => {
            Some((
                crate::chat_schedule_commands::SCHEDULES_CAPABILITY,
                "Scheduled tasks",
            ))
        }
        "linkPullRequest" | "unlinkPullRequest" | "listPullRequests" | "watchPullRequest"
        | "unwatchPullRequest" => Some((
            crate::chat_pull_request_commands::PULL_REQUESTS_CAPABILITY,
            "Chat pull requests",
        )),
        _ => None,
    }
}

/// The error an owner that predates `verb` answers with.
pub(crate) fn unsupported_on_host(verb: &str) -> HostError {
    let (capability, feature) =
        owner_scoped_capability(verb).unwrap_or(("chatOrchestrationV1", "This request"));
    HostError::conflict(
        "unsupported",
        format!(
            "{feature} are not supported on this host. Update Alera on the host that owns the chat."
        ),
        json!({"capability": capability}),
    )
}

impl ChatOrchestrationService {
    /// Answers an owner-scoped verb from the chat's host when another host
    /// owns the chat; `None` handles it here.
    pub(super) async fn route_to_chat_owner(
        &self,
        verb: &str,
        payload: &Value,
        request: &OrchestrationRequest,
        caller: &OrchestrationCaller,
    ) -> HostResult<Option<Value>> {
        let bound = caller.bound.as_ref().map(|bound| bound.chat_id.clone());
        let chat_id = match request {
            OrchestrationRequest::PullRequest { chat_id, .. } => chat_id.clone().or(bound),
            OrchestrationRequest::ScheduleTask(input) => bound.or(input.chat_id.clone()),
            OrchestrationRequest::ListScheduledTasks { chat_id, .. }
            | OrchestrationRequest::DeleteScheduledTask { chat_id, .. }
            | OrchestrationRequest::RunScheduledTaskNow { chat_id, .. } => {
                bound.or(chat_id.clone())
            }
            _ => None,
        };
        let Some(chat_id) = chat_id else {
            return Ok(None);
        };
        if !self.runtime.is_remote_chat(&chat_id).await? {
            return Ok(None);
        }
        let mut child_link = false;
        match request {
            OrchestrationRequest::PullRequest { action, .. } => {
                require_lineage_for_chat(caller, &self.store, &chat_id).await?;
                let child = self.is_child_chat(&chat_id).await?;
                if *action == PullRequestAction::Watch && child {
                    return Err(HostError::conflict(
                        "childCannotWatch",
                        CHILD_CANNOT_WATCH,
                        json!({}),
                    ));
                }
                child_link = *action == PullRequestAction::Link && child;
            }
            OrchestrationRequest::ListScheduledTasks { .. } => {}
            _ => self.require_not_child(caller).await?,
        }
        let mut forwarded = payload.clone();
        if let Some(fields) = forwarded.as_object_mut() {
            fields.insert("chatId".into(), json!(chat_id));
        }
        let mut response = self
            .runtime
            .forward_to_owner(&chat_id, verb, forwarded, caller.ctx.clone())
            .await?;
        if child_link {
            response["next"] = json!(super::pull_requests::CHILD_NEXT);
        }
        Ok(Some(response))
    }
}
