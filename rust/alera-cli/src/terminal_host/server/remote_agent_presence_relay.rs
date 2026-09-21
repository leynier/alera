//! Agent status for terminals whose agent runs on another host.
//!
//! A remote terminal is an `ssh -tt` proxy on the hub and a PTY session on the
//! satellite, and both carry the same session, tab and workspace ids. The
//! agent's hooks fire on the satellite. A satellite that advertises
//! `remoteAgentHookRelayV1` re-publishes each hook as `agentHookEvent`, and the
//! hub feeds it to the same `handle_agent_hook_event` a local hook reaches, so
//! status, titles, native session ids for resume, orchestration readiness and
//! push all run once, on the hub, with the hub's settings.
//!
//! What a live event stream cannot cover is the time the link was down, so
//! when a link attaches the hub reads the satellite's presence list and
//! mirrors it. An older satellite publishes no hooks; for it the same read
//! runs on every payload-free `agentPresenceChanged`, which keeps status
//! working without titles.

use std::collections::HashSet;

use serde_json::{json, Value};

use super::{ServerActor, ServerCommand};
use crate::agent_status::AgentHookEvent;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::host_link::HostLinkState;
use crate::terminal_host::protocol::RUNTIME_HOST_REMOTE_AGENT_HOOK_RELAY_CAPABILITY;

const AGENT_PRESENCE_CHANGED: &str = "agentPresenceChanged";
pub(super) const AGENT_HOOK_EVENT: &str = "agentHookEvent";

/// The wire form of a hook, as a satellite publishes it to local clients.
pub(super) fn hook_event_payload(event: &AgentHookEvent) -> Value {
    json!({
        "terminalSessionId": event.terminal_session_id,
        "workspaceId": event.workspace_id,
        "tabId": event.tab_id,
        "agentType": event.agent_type,
        "eventName": event.event_name,
        "payload": event.payload,
    })
}

fn hook_event_from_payload(payload: &Value) -> Option<AgentHookEvent> {
    let text = |key: &str| {
        payload
            .get(key)
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
    };
    Some(AgentHookEvent {
        terminal_session_id: text("terminalSessionId").filter(|id| !id.is_empty())?,
        workspace_id: text("workspaceId")?,
        tab_id: text("tabId")?,
        agent_type: text("agentType")?,
        payload: payload.get("payload").cloned().unwrap_or(Value::Null),
        event_name: text("eventName"),
    })
}

impl ServerActor {
    /// Reads the satellite's presence list on a spawned task: the actor never
    /// waits on a link.
    pub(super) fn start_remote_agent_presence_sync(&self, host_id: &str) {
        let links = self.host_links.clone();
        let inbox = self.inbox.clone();
        let host_id = host_id.to_string();
        tokio::spawn(async move {
            let result = async {
                let link = links.link(&host_id).await?;
                link.request_with_timeout(
                    "agentPresence.list",
                    json!({}),
                    crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
                )
                .await
            }
            .await;
            let _ = inbox.send(ServerCommand::RemoteAgentPresenceListed { host_id, result });
        });
    }

    pub(super) fn relay_host_link_event(&self, host_id: &str, event_name: &str, payload: &Value) {
        match event_name {
            AGENT_HOOK_EVENT => {
                // `handle_agent_hook_event` only accepts a hook whose session,
                // tab and workspace match a session this runtime owns, which is
                // what keeps a satellite from reporting for anything but the
                // terminals the hub proxies to it.
                if let Some(event) = hook_event_from_payload(payload) {
                    let _ = self.inbox.send(ServerCommand::AgentHookEvent { event });
                }
            }
            AGENT_PRESENCE_CHANGED if !self.satellite_relays_hooks(host_id) => {
                self.start_remote_agent_presence_sync(host_id);
            }
            _ => {}
        }
    }

    fn satellite_relays_hooks(&self, host_id: &str) -> bool {
        match self.host_links.state(host_id) {
            HostLinkState::Attached { attachment } => attachment
                .runtime_capabilities
                .iter()
                .any(|capability| capability == RUNTIME_HOST_REMOTE_AGENT_HOOK_RELAY_CAPABILITY),
            _ => false,
        }
    }

    /// A remote terminal only reports status while its host is linked, so
    /// starting one opens the link. Failure is not the terminal's problem: the
    /// PTY travels on its own channel.
    pub(super) fn ensure_host_link_for_remote_terminal(&self, host_id: &str) {
        let links = self.host_links.clone();
        let host_id = host_id.to_string();
        tokio::spawn(async move {
            if let Err(error) = links.link(&host_id).await {
                tracing::warn!(
                    target: "host_link",
                    host_id,
                    "remote terminal started without a host link, agent status will not relay: {}",
                    error.wire_message()
                );
            }
        });
    }

    pub(super) async fn finish_remote_agent_presence_sync(
        &mut self,
        host_id: String,
        result: HostResult<Value>,
    ) {
        let items = match result {
            Ok(Value::Array(items)) => items,
            Ok(_) => return,
            Err(error) => {
                tracing::warn!(
                    target: "host_link",
                    host_id,
                    "could not read agent status from the remote host: {}",
                    error.wire_message()
                );
                return;
            }
        };
        let owned = self.sessions_on_host(&host_id).await;
        let entries = relayed_entries(&items, &owned, |handle| {
            self.agent_presence.get(handle).is_some()
        });
        if entries.is_empty() {
            return;
        }
        let _ = self
            .orchestration_agent_status(&json!({ "entries": entries }))
            .await;
    }

    /// The hub sessions whose workspace lives on `host_id`.
    async fn sessions_on_host(&self, host_id: &str) -> HashSet<String> {
        let mut owned = HashSet::new();
        let mut hosts = std::collections::HashMap::<String, bool>::new();
        for (session_id, session) in &self.sessions {
            let on_host = match hosts.get(&session.workspace_id) {
                Some(on_host) => *on_host,
                None => {
                    let on_host = self
                        .runtime_store
                        .find_workspace(&session.workspace_id)
                        .await
                        .ok()
                        .flatten()
                        .is_some_and(|workspace| workspace.host_id == host_id);
                    hosts.insert(session.workspace_id.clone(), on_host);
                    on_host
                }
            };
            if on_host {
                owned.insert(session_id.clone());
            }
        }
        owned
    }
}

/// The `orchestration.agentStatus` entries that bring the hub in line with the
/// satellite: one per reported session the hub proxies, and a removal for every
/// proxied session the hub still shows but the satellite no longer reports.
/// Sessions the hub does not proxy are ignored, because a satellite also serves
/// its own clients.
fn relayed_entries(
    items: &[Value],
    owned: &HashSet<String>,
    has_presence: impl Fn(&str) -> bool,
) -> Vec<Value> {
    let mut reported = HashSet::new();
    let mut entries = Vec::new();
    for item in items {
        let Some(handle) = item.get("handle").and_then(Value::as_str) else {
            continue;
        };
        if !owned.contains(handle) || item.get("agentState").is_none_or(Value::is_null) {
            continue;
        }
        reported.insert(handle.to_string());
        entries.push(json!({
            "terminalSessionId": handle,
            "state": item.get("agentState"),
            "agentType": item.get("agentType"),
            "stateStartedAt": item.get("stateStartedAt"),
            "updatedAt": item.get("updatedAt"),
            "prompt": item.get("prompt"),
            "toolName": item.get("toolName"),
            "toolInput": item.get("toolInput"),
            "lastAssistantMessage": item.get("lastAssistantMessage"),
            "interrupted": item.get("interrupted"),
        }));
    }
    let mut stale: Vec<&String> = owned
        .iter()
        .filter(|handle| !reported.contains(*handle) && has_presence(handle))
        .collect();
    stale.sort();
    for handle in stale {
        entries.push(json!({ "terminalSessionId": handle, "removed": true }));
    }
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn owned(handles: &[&str]) -> HashSet<String> {
        handles.iter().map(|handle| handle.to_string()).collect()
    }

    #[test]
    fn a_published_hook_survives_the_wire() {
        let event = AgentHookEvent {
            terminal_session_id: "session".into(),
            workspace_id: "workspace".into(),
            tab_id: "tab".into(),
            agent_type: "claude".into(),
            payload: json!({"hook_event_name": "Stop", "session_id": "native-1"}),
            event_name: Some("Stop".into()),
        };
        let decoded = hook_event_from_payload(&hook_event_payload(&event)).unwrap();
        assert_eq!(decoded.terminal_session_id, "session");
        assert_eq!(decoded.workspace_id, "workspace");
        assert_eq!(decoded.tab_id, "tab");
        assert_eq!(decoded.agent_type, "claude");
        assert_eq!(decoded.event_name.as_deref(), Some("Stop"));
        assert_eq!(decoded.payload["session_id"], "native-1");
        assert!(hook_event_from_payload(&json!({"terminalSessionId": ""})).is_none());
        assert!(hook_event_from_payload(&json!({"agentType": "claude"})).is_none());
    }

    #[tokio::test]
    async fn a_relayed_hook_enters_the_same_pipeline_as_a_local_one() {
        use super::super::checkout_buffer_guards_tests::fixture;

        let (_root, mut actor) = fixture().await;
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox;
        let published = json!({
            "terminalSessionId": "proxied", "workspaceId": "task", "tabId": "tab",
            "agentType": "claude", "eventName": "UserPromptSubmit",
            "payload": {"prompt": "fix the build"},
        });

        actor.relay_host_link_event("ssh", AGENT_HOOK_EVENT, &published);
        actor.relay_host_link_event("ssh", AGENT_HOOK_EVENT, &json!({"agentType": "claude"}));
        actor.relay_host_link_event("ssh", "workspacesChanged", &json!({}));

        let Some(ServerCommand::AgentHookEvent { event }) = commands.recv().await else {
            panic!("the hook must reach the actor's hook handler");
        };
        assert_eq!(event.terminal_session_id, "proxied");
        assert_eq!(event.payload["prompt"], "fix the build");
        assert!(
            commands.try_recv().is_err(),
            "malformed hooks and unrelated events are not relayed"
        );
    }

    #[test]
    fn relays_only_the_sessions_the_hub_proxies() {
        let items = vec![
            json!({"handle": "mine", "agentType": "claude", "agentState": "working",
                "stateStartedAt": "2026-09-21T10:00:00Z", "prompt": "fix it"}),
            json!({"handle": "satellite-only", "agentType": "codex", "agentState": "done"}),
            json!({"handle": "idle", "agentType": null, "agentState": null}),
        ];
        let entries = relayed_entries(&items, &owned(&["mine", "idle"]), |_| false);
        assert_eq!(entries.len(), 1, "{entries:?}");
        assert_eq!(entries[0]["terminalSessionId"], "mine");
        assert_eq!(entries[0]["state"], "working");
        assert_eq!(entries[0]["agentType"], "claude");
        assert_eq!(entries[0]["prompt"], "fix it");
    }

    #[test]
    fn a_status_the_satellite_dropped_is_removed_on_the_hub() {
        let items = vec![json!({"handle": "a", "agentType": "claude", "agentState": "waiting"})];
        let entries = relayed_entries(&items, &owned(&["a", "b", "c"]), |handle| handle == "b");
        assert_eq!(entries.len(), 2, "{entries:?}");
        assert_eq!(
            entries[1],
            json!({"terminalSessionId": "b", "removed": true})
        );
    }

    #[tokio::test]
    async fn the_hub_mirrors_a_satellite_status_under_the_shared_session_id() {
        use super::super::checkout_buffer_guards_tests::fixture;
        use crate::terminal_host::session::Session;

        let (_root, mut actor) = fixture().await;
        let mut remote = actor
            .runtime_store
            .find_workspace("task")
            .await
            .unwrap()
            .unwrap();
        remote.host_id = "ssh".into();
        actor.runtime_store.upsert_workspace(remote).await.unwrap();
        for (session_id, workspace_id) in [("proxied", "task"), ("local", "sibling")] {
            let mut session = Session::driver_test_stub(session_id, 80, 24);
            session.workspace_id = workspace_id.into();
            session.tab_id = format!("{session_id}-tab");
            actor.sessions.insert(session_id.into(), session);
        }
        let listed = json!([
            {"handle": "proxied", "agentType": "claude", "agentState": "waiting",
                "stateStartedAt": "2026-09-21T10:00:00Z", "toolName": "Bash"},
            {"handle": "local", "agentType": "codex", "agentState": "working"},
        ]);

        actor
            .finish_remote_agent_presence_sync("ssh".into(), Ok(listed))
            .await;

        let mirrored = actor.agent_presence.get("proxied").expect("status relayed");
        assert_eq!(mirrored.agent_type, "claude");
        assert_eq!(mirrored.state.as_str(), "waiting");
        assert_eq!(mirrored.tool_name.as_deref(), Some("Bash"));
        assert!(
            actor.agent_presence.get("local").is_none(),
            "a session on another host is not this satellite's to report"
        );

        actor
            .finish_remote_agent_presence_sync("ssh".into(), Ok(json!([])))
            .await;
        assert!(actor.agent_presence.get("proxied").is_none());
    }

    #[test]
    fn nothing_to_say_when_the_hosts_already_agree() {
        assert!(relayed_entries(&[], &owned(&["a"]), |_| false).is_empty());
        assert!(relayed_entries(&[], &owned(&[]), |_| true).is_empty());
    }
}
