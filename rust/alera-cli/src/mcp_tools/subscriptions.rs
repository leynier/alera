//! Resources a local MCP client can read and subscribe to.
//!
//! `alera mcp serve` lists a few resources that mirror polling tools. A client
//! that subscribes to one gets `notifications/resources/updated` when the
//! runtime reports a change, then reads it again. The listener connects to
//! the runtime only while some resource is subscribed, so an idle server never
//! keeps the runtime awake.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use crate::runtime_host_client::RuntimeHostRpcClient;

pub(crate) struct ResourceSpec {
    pub(crate) uri: &'static str,
    pub(crate) name: &'static str,
    pub(crate) description: &'static str,
    /// The tool whose result is the resource's content.
    pub(crate) tool: &'static str,
    /// Runtime events that change the resource.
    pub(crate) events: &'static [&'static str],
}

pub(crate) const RESOURCES: &[ResourceSpec] = &[
    ResourceSpec {
        uri: "alera://events",
        name: "Runtime Events",
        description: "The runtime event journal: inbox replies, agent states, tasks, runs, and workspace starts. Read alera://events?after=<cursor> for what is new.",
        tool: "list_events",
        events: &[
            "runtimeEventsAppended",
            "promptWorkspaceOperationsChanged",
            "inboxChanged",
            "orchestrationBoardChanged",
        ],
    },
    ResourceSpec {
        uri: "alera://workspace-starts",
        name: "Workspace Starts",
        description: "Recent New Workspace from Prompt operations and their status.",
        tool: "list_workspace_starts",
        events: &["promptWorkspaceOperationsChanged"],
    },
    ResourceSpec {
        uri: "alera://inbox",
        name: "MCP Inbox",
        description: "Question threads asked through ask_agent, with their replies.",
        tool: "list_inbox_threads",
        events: &["inboxChanged"],
    },
];

const RECONNECT_DELAY: Duration = Duration::from_secs(3);

/// The resource and tool arguments a `resources/read` URI names.
pub(crate) fn resolve(uri: &str) -> Option<(&'static ResourceSpec, Value)> {
    let (base, query) = uri.split_once('?').unwrap_or((uri, ""));
    let resource = RESOURCES.iter().find(|resource| resource.uri == base)?;
    let mut arguments = json!({});
    for pair in query.split('&').filter(|pair| !pair.is_empty()) {
        let (key, value) = pair.split_once('=')?;
        match (resource.tool, key) {
            ("list_events", "after") => arguments["after"] = json!(value.parse::<u64>().ok()?),
            _ => return None,
        }
    }
    Some((resource, arguments))
}

pub(crate) fn listed_resources() -> Vec<Value> {
    RESOURCES
        .iter()
        .map(|resource| {
            json!({
                "uri": resource.uri,
                "name": resource.name,
                "description": resource.description,
                "mimeType": "application/json",
            })
        })
        .collect()
}

/// Subscribed URIs and the listener that serves them.
pub(crate) struct Subscriptions {
    runtime_dir: PathBuf,
    output: mpsc::Sender<Value>,
    uris: Arc<Mutex<HashSet<String>>>,
    listener: Option<JoinHandle<()>>,
}

impl Subscriptions {
    pub(crate) fn new(runtime_dir: PathBuf, output: mpsc::Sender<Value>) -> Self {
        Self {
            runtime_dir,
            output,
            uris: Arc::default(),
            listener: None,
        }
    }

    pub(crate) fn subscribe(&mut self, uri: &str) -> bool {
        if resolve(uri).is_none() {
            return false;
        }
        if let Ok(mut uris) = self.uris.lock() {
            uris.insert(uri.split('?').next().unwrap_or(uri).to_owned());
        }
        if self.listener.as_ref().is_none_or(JoinHandle::is_finished) {
            self.listener = Some(tokio::spawn(listen(
                self.runtime_dir.clone(),
                self.uris.clone(),
                self.output.clone(),
            )));
        }
        true
    }

    pub(crate) fn unsubscribe(&mut self, uri: &str) {
        let empty = self.uris.lock().map_or(true, |mut uris| {
            uris.remove(uri.split('?').next().unwrap_or(uri));
            uris.is_empty()
        });
        if empty {
            if let Some(listener) = self.listener.take() {
                listener.abort();
            }
        }
    }
}

impl Drop for Subscriptions {
    fn drop(&mut self) {
        if let Some(listener) = self.listener.take() {
            listener.abort();
        }
    }
}

/// The URIs a runtime event updates among those subscribed.
pub(crate) fn updated_uris(event: &str, subscribed: &HashSet<String>) -> Vec<&'static str> {
    RESOURCES
        .iter()
        .filter(|resource| resource.events.contains(&event) && subscribed.contains(resource.uri))
        .map(|resource| resource.uri)
        .collect()
}

async fn listen(
    runtime_dir: PathBuf,
    uris: Arc<Mutex<HashSet<String>>>,
    output: mpsc::Sender<Value>,
) {
    loop {
        if let Ok(Some(client)) = RuntimeHostRpcClient::connect(&runtime_dir).await {
            // The write half stays open: closing it would end the session.
            let (mut lines, _writer, _) = client.into_terminal_transport();
            while let Ok(Some(line)) = lines.next_line().await {
                let Ok(frame) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                let Some(event) = frame.get("event").and_then(Value::as_str) else {
                    continue;
                };
                let targets = match uris.lock() {
                    Ok(subscribed) => updated_uris(event, &subscribed),
                    Err(_) => return,
                };
                for uri in targets {
                    let notification = json!({
                        "jsonrpc": "2.0",
                        "method": "notifications/resources/updated",
                        "params": { "uri": uri },
                    });
                    if output.send(notification).await.is_err() {
                        return;
                    }
                }
            }
        }
        tokio::time::sleep(RECONNECT_DELAY).await;
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use serde_json::json;

    use super::{resolve, updated_uris, RESOURCES};
    use crate::mcp_tools::find_tool;

    #[test]
    fn every_resource_reads_through_an_existing_reading_tool() {
        for resource in RESOURCES {
            let tool = find_tool(resource.tool).expect("resource tool exists");
            assert_eq!(
                tool.access,
                crate::mcp_tools::ToolAccess::Read,
                "{}",
                resource.uri
            );
        }
    }

    #[test]
    fn uris_resolve_with_their_query() {
        let (resource, arguments) = resolve("alera://events?after=42").unwrap();
        assert_eq!(resource.tool, "list_events");
        assert_eq!(arguments, json!({ "after": 42 }));
        assert!(resolve("alera://events?before=1").is_none());
        assert!(resolve("alera://unknown").is_none());
    }

    #[test]
    fn events_update_only_subscribed_resources() {
        let subscribed: HashSet<String> = ["alera://inbox".to_owned()].into();
        assert_eq!(
            updated_uris("inboxChanged", &subscribed),
            vec!["alera://inbox"]
        );
        assert!(updated_uris("promptWorkspaceOperationsChanged", &subscribed).is_empty());
    }
}
