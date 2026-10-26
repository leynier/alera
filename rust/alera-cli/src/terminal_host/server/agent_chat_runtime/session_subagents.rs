//! A provider-native sub-agent read as its own transcript, and stopped on its
//! own. The sub-agent's items live in the parent chat, linked to the call that
//! started it through `normalized.parentItemId`; reading one collects that
//! call's descendants, so a sub-agent's own sub-agents come with it.

use std::collections::{HashMap, HashSet};
use std::time::Duration;

use alera_provider_protocol::ProviderError;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::conflict;
use super::session::ChatSession;
use super::session_snapshot::HISTORY_MAX_ITEMS;

/// How many of the chat's latest rows a read scans for the sub-agent's work.
pub(crate) const SUBAGENT_SCAN_ITEMS: usize = 4_000;
const STOP_TIMEOUT: Duration = Duration::from_secs(10);

fn parent_of(item: &Value) -> Option<&str> {
    item.pointer("/normalized/parentItemId")
        .and_then(Value::as_str)
}

fn item_id(item: &Value) -> Option<&str> {
    item.get("itemId").and_then(Value::as_str)
}

/// The items under `call`, at any depth, in the order given. Continuation
/// rows (`<id>:segment:...`) follow the item they continue.
pub(crate) fn subagent_descendants(call: &str, items: &[Value]) -> Vec<Value> {
    let parents: HashMap<&str, &str> = items
        .iter()
        .filter_map(|item| Some((item_id(item)?, parent_of(item)?)))
        .collect();
    let mut included: HashSet<&str> = HashSet::new();
    for item in items {
        let Some(mut current) = item_id(item) else {
            continue;
        };
        let mut seen = HashSet::new();
        while let Some(parent) = parents.get(current) {
            if *parent == call {
                included.insert(item_id(item).unwrap_or_default());
                break;
            }
            if !seen.insert(*parent) {
                break;
            }
            current = parent;
        }
    }
    items
        .iter()
        .filter(|item| {
            let Some(id) = item_id(item) else {
                return false;
            };
            included.contains(id)
                || id
                    .split_once(":segment:")
                    .is_some_and(|(head, _)| included.contains(head))
        })
        .cloned()
        .collect()
}

fn not_a_subagent() -> HostError {
    conflict("notSubagent", "The item did not start a sub-agent.")
}

impl ChatSession {
    async fn subagent_call(&mut self, item_id: &str) -> HostResult<Value> {
        let call = self
            .deps
            .store
            .agent_chat_item(&self.header.chat_id, item_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| conflict("itemNotFound", "The item no longer exists."))?;
        Ok(call)
    }

    /// `agentChat.subagent`: the call that started a sub-agent and every item
    /// under it among the chat's latest [`SUBAGENT_SCAN_ITEMS`] rows.
    pub(super) async fn subagent_transcript(&mut self, item_id: &str) -> HostResult<Value> {
        self.flush()
            .await
            .map_err(|error| HostError::state(format!("The chat could not be saved: {error}")))?;
        let call = self.subagent_call(item_id).await?;
        let mut pages: Vec<Vec<Value>> = Vec::new();
        let mut scanned = 0usize;
        let mut before = i64::MAX;
        let mut truncated = false;
        loop {
            let page = self
                .deps
                .store
                .agent_chat_history(&self.header.chat_id, before, HISTORY_MAX_ITEMS as i64)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            scanned += page.items.len();
            pages.push(page.items);
            match page.history_before {
                Some(next) if scanned < SUBAGENT_SCAN_ITEMS => before = next,
                Some(_) => {
                    truncated = true;
                    break;
                }
                None => break,
            }
        }
        let items: Vec<Value> = pages.into_iter().rev().flatten().collect();
        let descendants = subagent_descendants(item_id, &items);
        if descendants.is_empty() && call.pointer("/normalized/subagent").is_none() {
            return Err(not_a_subagent());
        }
        Ok(json!({
            "chatId": self.header.chat_id,
            "call": call,
            "items": descendants,
            "truncated": truncated,
        }))
    }

    /// `agentChat.stopSubagent`: stops the running sub-agent the call
    /// started. Its task events then settle the call as `stopped`.
    pub(super) async fn stop_subagent(&mut self, item_id: &str) -> HostResult<Value> {
        self.load_item(item_id).await;
        let subagent = self
            .items
            .get(item_id)
            .and_then(|item| item.normalized.get("subagent"))
            .cloned()
            .ok_or_else(not_a_subagent)?;
        if subagent.get("status").and_then(Value::as_str) != Some("running") {
            return Err(conflict(
                "subagentNotRunning",
                "The sub-agent is no longer running.",
            ));
        }
        let task_id = subagent
            .get("taskId")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| {
                conflict(
                    "unsupported",
                    "The provider has not identified this sub-agent yet.",
                )
            })?;
        let provider = self.provider.as_mut().ok_or_else(|| {
            conflict(
                "subagentNotRunning",
                "The agent session that ran the sub-agent has ended.",
            )
        })?;
        match tokio::time::timeout(STOP_TIMEOUT, provider.stop_subagent(&task_id)).await {
            Ok(Ok(())) => Ok(json!({"stopped": true, "itemId": item_id})),
            Ok(Err(ProviderError::Unsupported(_))) => Err(conflict(
                "unsupported",
                "This chat's provider cannot stop a single sub-agent.",
            )),
            Ok(Err(ProviderError::InvalidState(_) | ProviderError::Closed)) => Err(conflict(
                "subagentNotRunning",
                "The sub-agent is no longer running.",
            )),
            Ok(Err(error)) => {
                tracing::warn!(chat_id = %self.header.chat_id, error = %error, "stopping a sub-agent failed");
                Err(HostError::state("The sub-agent could not be stopped."))
            }
            Err(_) => Err(HostError::state("The sub-agent did not stop in time.")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(id: &str, parent: Option<&str>) -> Value {
        match parent {
            Some(parent) => json!({"itemId": id, "normalized": {"parentItemId": parent}}),
            None => json!({"itemId": id, "normalized": {}}),
        }
    }

    #[test]
    fn descendants_follow_nested_calls_and_continuations_in_order() {
        let items = vec![
            item("call", None),
            item("a", Some("call")),
            item("other", None),
            item("nested-call", Some("call")),
            item("b", Some("nested-call")),
            item("b:segment:text:1", None),
            item("stranger", Some("elsewhere")),
        ];
        let ids: Vec<_> = subagent_descendants("call", &items)
            .iter()
            .map(|item| item["itemId"].as_str().unwrap().to_owned())
            .collect();
        assert_eq!(ids, ["a", "nested-call", "b", "b:segment:text:1"]);
    }

    #[test]
    fn a_cycle_in_parent_links_does_not_hang() {
        let items = vec![item("x", Some("y")), item("y", Some("x"))];
        assert!(subagent_descendants("call", &items).is_empty());
    }
}
