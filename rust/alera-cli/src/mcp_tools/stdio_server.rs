//! `alera mcp serve`: the catalog as a local MCP server over stdio.
//!
//! Messages are newline-delimited JSON-RPC. Calls run concurrently, and a
//! `notifications/cancelled` stops the matching child process.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot};

use super::subscriptions::{listed_resources, resolve, Subscriptions};
use super::{catalog, find_tool, run_tool, CallOrigin, ToolExecution, ToolSpec};
use crate::mcp_settings::McpAccess;

pub(crate) const PROTOCOL_VERSIONS: &[&str] = &["2025-11-25", "2025-06-18", "2025-03-26"];
pub(crate) const INSTRUCTIONS: &str = "Alera runs coding agents in workspaces (Git worktrees) and orchestrates them. Start with list_projects, list_workspaces, and list_agent_profiles. Use start_agent_workspace or delegate_task to start work, then wait_for_task, read_terminal, or ask_agent with wait_for_reply to follow it. Waits return after at most 50 seconds; call them again to keep waiting.";
const MAX_CONCURRENT_CALLS: usize = 4;

type Pending = Arc<Mutex<HashMap<String, oneshot::Sender<()>>>>;

/// Serves the catalog up to `access`: `read` lists only reading tools, `full`
/// adds execution tools, and `admin` adds administrative ones.
pub(crate) async fn serve_stdio(execution: ToolExecution, access: McpAccess) -> anyhow::Result<()> {
    let mut origin = CallOrigin::local(&Value::Null);
    let (output, mut outgoing) = mpsc::channel::<Value>(64);
    let pending: Pending = Arc::default();
    let writer_pending = pending.clone();
    let writer = tokio::spawn(async move {
        let mut stdout = tokio::io::stdout();
        while let Some(message) = outgoing.recv().await {
            let mut line = serde_json::to_vec(&message).unwrap_or_default();
            line.push(b'\n');
            if stdout.write_all(&line).await.is_err() || stdout.flush().await.is_err() {
                // A closed stdout is a disconnect, like stdin reaching EOF.
                cancel_all(&writer_pending);
                break;
            }
        }
    });
    let permits = Arc::new(tokio::sync::Semaphore::new(MAX_CONCURRENT_CALLS));
    let mut subscriptions = Subscriptions::new(execution.runtime_dir.clone(), output.clone());
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Some(line) = lines.next_line().await? {
        if output.is_closed() {
            break;
        }
        if line.trim().is_empty() {
            continue;
        }
        let message: Value = match serde_json::from_str(&line) {
            Ok(message) => message,
            Err(_) => {
                let _ = output.send(error(Value::Null, -32700, "Parse error")).await;
                continue;
            }
        };
        let id = message.get("id").cloned();
        let method = message["method"].as_str().unwrap_or_default().to_owned();
        let params = message.get("params").cloned().unwrap_or(Value::Null);
        let Some(id) = id else {
            if method == "notifications/cancelled" {
                let key = params["requestId"].to_string();
                if let Some(cancel) = pending.lock().ok().and_then(|mut map| map.remove(&key)) {
                    let _ = cancel.send(());
                }
            }
            continue;
        };
        match method.as_str() {
            "initialize" => {
                origin = CallOrigin::local(&params["clientInfo"]);
                let _ = output.send(success(id, initialize_result(&params))).await;
            }
            "ping" => {
                let _ = output.send(success(id, json!({}))).await;
            }
            "resources/list" => {
                let resources = json!({ "resources": listed_resources() });
                let _ = output.send(success(id, resources)).await;
            }
            "resources/read" => {
                let uri = params["uri"].as_str().unwrap_or_default().to_owned();
                let response = match resolve(&uri) {
                    Some((resource, arguments)) => match find_tool(resource.tool) {
                        Some(tool) => {
                            let result =
                                run_tool(&execution, &tool, &arguments, &origin, None).await;
                            if result.is_error {
                                error(id, -32603, &result.text)
                            } else {
                                success(
                                    id,
                                    json!({ "contents": [{
                                        "uri": uri,
                                        "mimeType": "application/json",
                                        "text": result.text,
                                    }]}),
                                )
                            }
                        }
                        None => error(id, -32002, &format!("Resource not found: {uri}")),
                    },
                    None => error(id, -32002, &format!("Resource not found: {uri}")),
                };
                let _ = output.send(response).await;
            }
            "resources/subscribe" => {
                let uri = params["uri"].as_str().unwrap_or_default();
                let response = if subscriptions.subscribe(uri) {
                    success(id, json!({}))
                } else {
                    error(id, -32002, &format!("Resource not found: {uri}"))
                };
                let _ = output.send(response).await;
            }
            "resources/unsubscribe" => {
                subscriptions.unsubscribe(params["uri"].as_str().unwrap_or_default());
                let _ = output.send(success(id, json!({}))).await;
            }
            "tools/list" => {
                let tools = visible_tools(access)
                    .iter()
                    .map(listed_tool)
                    .collect::<Vec<_>>();
                let _ = output.send(success(id, json!({ "tools": tools }))).await;
            }
            "tools/call" => {
                let name = params["name"].as_str().unwrap_or_default().to_owned();
                let Some(tool) = find_tool(&name).filter(|tool| access.allows(tool.access)) else {
                    let _ = output
                        .send(error(id, -32602, &format!("Unknown tool: {name}")))
                        .await;
                    continue;
                };
                let (cancel, cancelled) = oneshot::channel();
                let key = id.to_string();
                if let Ok(mut map) = pending.lock() {
                    map.insert(key.clone(), cancel);
                }
                let output = output.clone();
                let execution = execution.clone();
                let origin = origin.clone().with_call_id(key.trim_matches('"'));
                let pending = pending.clone();
                let permits = permits.clone();
                tokio::spawn(async move {
                    let mut cancelled = cancelled;
                    // A call cancelled while queued must never start its command.
                    let _permit = tokio::select! {
                        biased;
                        _ = &mut cancelled => return,
                        permit = permits.acquire_owned() => permit,
                    };
                    if cancelled.try_recv().is_ok() {
                        return;
                    }
                    let arguments = params.get("arguments").cloned().unwrap_or(Value::Null);
                    let result =
                        run_tool(&execution, &tool, &arguments, &origin, Some(cancelled)).await;
                    let still_pending = pending
                        .lock()
                        .ok()
                        .and_then(|mut map| map.remove(&key))
                        .is_some();
                    if still_pending {
                        let _ = output.send(success(id, result.to_mcp())).await;
                    }
                });
            }
            _ => {
                let _ = output
                    .send(error(id, -32601, &format!("Method not found: {method}")))
                    .await;
            }
        }
    }
    // The client is gone: stop running calls and keep queued ones from
    // starting, since nobody can receive their results.
    cancel_all(&pending);
    drop(subscriptions);
    drop(output);
    let _ = writer.await;
    Ok(())
}

fn cancel_all(pending: &Pending) {
    if let Ok(mut map) = pending.lock() {
        for (_, cancel) in map.drain() {
            let _ = cancel.send(());
        }
    }
}

fn visible_tools(access: McpAccess) -> Vec<ToolSpec> {
    catalog()
        .into_iter()
        .filter(|tool| access.allows(tool.access))
        .collect()
}

pub(crate) fn negotiate_version(requested: Option<&str>) -> &'static str {
    requested
        .and_then(|requested| {
            PROTOCOL_VERSIONS
                .iter()
                .find(|version| **version == requested)
        })
        .copied()
        .unwrap_or(PROTOCOL_VERSIONS[0])
}

fn initialize_result(params: &Value) -> Value {
    json!({
        "protocolVersion": negotiate_version(params["protocolVersion"].as_str()),
        "capabilities": {
            "tools": { "listChanged": false },
            "resources": { "subscribe": true, "listChanged": false },
        },
        "serverInfo": {
            "name": "alera",
            "title": "Alera",
            "version": crate::terminal_host::runtime_build_info::version(),
        },
        "instructions": INSTRUCTIONS,
    })
}

fn listed_tool(tool: &ToolSpec) -> Value {
    let mut value = tool.to_json();
    if let Some(object) = value.as_object_mut() {
        object.remove("access");
        object.remove("timeoutSeconds");
    }
    value
}

fn success(id: Value, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

fn error(id: Value, code: i64, message: &str) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } })
}
