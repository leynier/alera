//! `pullRequest.agentDispatch`: Restack and Fix Failed Checks, with their
//! prompts kept here as the single source the desktop, mobile, the CLI, and
//! MCP share (`pullRequestAgentDispatchV1`). Without a target the request only
//! answers the prompt, so a client can keep its own agent picker; with a
//! `tabId`, `handle`, or `profileId` the runtime delivers it.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::requests::{
    optional_string_key, require_string_key, terminal_session_id_from_tab,
};
use super::super::ServerActor;

/// Rewrites local history since the merge base without pushing. The prompt
/// may reach a shell as a launch argument, so it avoids backticks and other
/// characters a shell would expand, and names no files, SHAs, or messages.
const RESTACK_PROMPT: &str = "Refactor all committed and uncommitted changes since the merge base into logical, easy-to-review commits. Inspect the complete diff first, then reorder, split, squash, and edit commits as needed. Preserve the final tree and behavior. Do not push.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DispatchKind {
    Restack,
    FixFailedChecks,
}

impl DispatchKind {
    pub(crate) fn parse(value: &str) -> HostResult<Self> {
        match value {
            "restack" => Ok(Self::Restack),
            "fixFailedChecks" => Ok(Self::FixFailedChecks),
            other => Err(HostError::format(format!(
                "kind must be restack or fixFailedChecks, not {other}."
            ))),
        }
    }

    fn wire(self) -> &'static str {
        match self {
            Self::Restack => "restack",
            Self::FixFailedChecks => "fixFailedChecks",
        }
    }

    fn title(self) -> &'static str {
        match self {
            Self::Restack => "Restack Changes",
            Self::FixFailedChecks => "Fix Failed Checks",
        }
    }
}

/// The prompt for [kind]. Check names and logs stay out of the failed-checks
/// prompt so the agent reads the current CI state itself.
pub(crate) fn agent_dispatch_prompt(kind: DispatchKind, review_number: Option<i64>) -> String {
    match (kind, review_number) {
        (DispatchKind::Restack, _) => RESTACK_PROMPT.to_string(),
        (DispatchKind::FixFailedChecks, Some(number)) => {
            format!("Pull request #{number} checks failed. Please fix them.")
        }
        (DispatchKind::FixFailedChecks, None) => {
            "The pull request checks failed. Please fix them.".to_string()
        }
    }
}

impl ServerActor {
    pub(in crate::terminal_host::server) async fn pull_request_agent_dispatch(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_auth(client_id)?;
        let workspace_id = require_string_key(payload, "workspaceId")?;
        let kind = DispatchKind::parse(&require_string_key(payload, "kind")?)?;
        let workspace = self
            .runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::format("Workspace not found."))?;
        let number = match payload.get("number").and_then(Value::as_i64) {
            Some(number) if number > 0 => Some(number),
            Some(_) => return Err(HostError::format("number must be a positive integer.")),
            None => self
                .runtime_store
                .find_linked_review(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .filter(|review| !review.dismissed)
                .and_then(|review| review.number),
        };
        if kind == DispatchKind::FixFailedChecks && number.is_none() {
            return Err(HostError::format(
                "Link or open a pull request for this workspace first, or pass its number.",
            ));
        }
        let prompt = agent_dispatch_prompt(kind, number);
        let mut result = json!({
            "workspaceId": workspace.id,
            "kind": kind.wire(),
            "number": number,
            "title": kind.title(),
            "prompt": prompt,
            "dispatched": false,
        });
        let tab_id = optional_string_key(payload, "tabId");
        let handle = optional_string_key(payload, "handle");
        let profile_id = optional_string_key(payload, "profileId");
        if tab_id.is_none() && handle.is_none() && profile_id.is_none() {
            return Ok(result);
        }
        if let Some(session_id) = self
            .running_dispatch_session(&workspace.id, tab_id.as_deref(), handle.as_deref())
            .await?
        {
            if !self.agent_presence.is_injection_ready(&session_id) {
                return Err(HostError::state(
                    "The agent in that terminal is busy. Try again when it is idle, or choose a profile.",
                ));
            }
            self.queue_orchestration_paste(&session_id, &prompt, Vec::new(), true)?;
            result["dispatched"] = json!(true);
            result["target"] = json!({ "terminalHandle": session_id, "openedNewTab": false });
            return Ok(result);
        }
        let Some(profile_id) = profile_id else {
            return Err(HostError::state(
                "The chosen agent terminal is not running. Choose a running agent or a profile.",
            ));
        };
        let launched = self
            .launch_agent_profile(
                None,
                &json!({"workspaceId": workspace.id, "profileId": profile_id, "prompt": prompt}),
            )
            .await?;
        result["dispatched"] = json!(true);
        result["target"] = json!({
            "profileId": profile_id,
            "tabId": launched["tab"]["id"].as_str().or(launched["tabId"].as_str()),
            "openedNewTab": true,
        });
        Ok(result)
    }

    /// The running terminal a tab or handle names in [workspace_id].
    async fn running_dispatch_session(
        &self,
        workspace_id: &str,
        tab_id: Option<&str>,
        handle: Option<&str>,
    ) -> HostResult<Option<String>> {
        let session_id = match (handle, tab_id) {
            (Some(handle), _) => Some(handle.to_string()),
            (None, Some(tab_id)) => {
                let tab = self
                    .runtime_store
                    .find_workspace_tab(tab_id)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?
                    .ok_or_else(|| HostError::format("Terminal tab not found."))?;
                if tab.workspace_id != workspace_id {
                    return Err(HostError::format(
                        "Terminal tab does not belong to this workspace.",
                    ));
                }
                terminal_session_id_from_tab(&tab)
            }
            (None, None) => None,
        };
        let Some(session_id) = session_id else {
            return Ok(None);
        };
        match self.sessions.get(&session_id) {
            Some(session) if session.workspace_id != workspace_id => Err(HostError::format(
                "Terminal handle does not belong to this workspace.",
            )),
            Some(session) if session.running() => Ok(Some(session_id)),
            _ => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prompts_match_the_desktop_and_avoid_shell_expansion() {
        let restack = agent_dispatch_prompt(DispatchKind::Restack, Some(4));
        assert!(restack.starts_with("Refactor all committed and uncommitted changes"));
        assert!(restack.ends_with("Do not push."));
        assert_eq!(
            agent_dispatch_prompt(DispatchKind::FixFailedChecks, Some(42)),
            "Pull request #42 checks failed. Please fix them."
        );
        for prompt in [
            restack,
            agent_dispatch_prompt(DispatchKind::FixFailedChecks, None),
        ] {
            assert!(!prompt.contains('`') && !prompt.contains('$'));
        }
        assert!(DispatchKind::parse("rebase").is_err());
    }
}
