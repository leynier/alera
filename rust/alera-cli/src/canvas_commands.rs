use std::io::Read;
use std::time::Duration;

use anyhow::{anyhow, Result};
use serde_json::{json, Value};
use tokio::time::Instant;

use crate::cli::{
    CanvasAction, CanvasCatalogArgs, CanvasCommand, CanvasEventsArgs, CanvasIdentityArgs,
    CanvasPublishArgs, CanvasWaitArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;

const EVENT_POLL_INTERVAL: Duration = Duration::from_millis(250);

pub async fn run(command: CanvasCommand) -> i32 {
    let runtime_dir = crate::runtime_dir(&command.runtime);
    let json_output = command.output.json;
    match command.action {
        CanvasAction::Capabilities => {
            request_and_report(
                &runtime_dir,
                "agentCanvas.capabilities",
                json!({}),
                json_output,
            )
            .await
        }
        CanvasAction::Catalog(args) => run_catalog(runtime_dir, args, json_output).await,
        CanvasAction::Examples => {
            crate::print_value(&examples(), json_output, "Agent Canvas examples ready");
            0
        }
        CanvasAction::Publish(args) => run_publish(runtime_dir, args, json_output).await,
        CanvasAction::Wait(args) => run_wait(runtime_dir, args, json_output).await,
        CanvasAction::Events(args) => run_events(runtime_dir, args, json_output).await,
        CanvasAction::Complete(args) => {
            run_state_change(runtime_dir, args, "complete", json_output).await
        }
        CanvasAction::Close(args) => {
            run_state_change(runtime_dir, args, "close", json_output).await
        }
    }
}

async fn run_catalog(
    runtime_dir: std::path::PathBuf,
    args: CanvasCatalogArgs,
    json_output: bool,
) -> i32 {
    let workspace_id = match workspace_id(args.workspace_id.clone()) {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    request_and_report(
        &runtime_dir,
        "agentCanvas.catalog",
        json!({
            "workspaceId": workspace_id,
            "includeHistory": args.include_history,
        }),
        json_output,
    )
    .await
}

async fn run_publish(
    runtime_dir: std::path::PathBuf,
    args: CanvasPublishArgs,
    json_output: bool,
) -> i32 {
    let workspace_id = match workspace_id(args.workspace_id.clone()) {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    let terminal_session_id = match terminal_session_id(args.terminal_session_id.clone()) {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    let document = match read_document(&args) {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    let payload = json!({
        "workspaceId": workspace_id,
        "terminalSessionId": terminal_session_id,
        "tabId": args.tab_id.or_else(|| std::env::var("ALERA_TAB_ID").ok()),
        "agentType": args.agent_type.or_else(|| std::env::var("ALERA_AGENT_TYPE").ok()),
        "title": args.title,
        "canvasId": args.canvas_id,
        "expectedRevision": args.expected_revision,
        "state": args.state,
        "document": document,
    });
    request_and_report(&runtime_dir, "agentCanvas.publish", payload, json_output).await
}

async fn run_wait(runtime_dir: std::path::PathBuf, args: CanvasWaitArgs, json_output: bool) -> i32 {
    let mut client = match connect(&runtime_dir).await {
        Ok(client) => client,
        Err(error) => return crate::print_error(error),
    };
    let deadline = Instant::now() + Duration::from_millis(args.timeout_ms);
    loop {
        match client
            .request_value(
                "agentCanvas.wait",
                &json!({ "decisionId": args.decision_id }),
            )
            .await
        {
            Ok(value) if value.get("ready").and_then(Value::as_bool) == Some(true) => {
                crate::print_value(&value, json_output, "Agent Canvas decision resolved");
                return 0;
            }
            Ok(value) if Instant::now() >= deadline => {
                let timed_out = json!({
                    "timedOut": true,
                    "cancelled": false,
                    "decision": value.get("decision").cloned().unwrap_or(Value::Null),
                });
                crate::print_value(&timed_out, json_output, "Agent Canvas wait timed out");
                return 1;
            }
            Ok(_) => tokio::time::sleep(EVENT_POLL_INTERVAL).await,
            Err(error) => return crate::print_error(error),
        }
    }
}

async fn run_events(
    runtime_dir: std::path::PathBuf,
    args: CanvasEventsArgs,
    json_output: bool,
) -> i32 {
    let workspace_id = match workspace_id(args.workspace_id) {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    let mut client = match connect(&runtime_dir).await {
        Ok(client) => client,
        Err(error) => return crate::print_error(error),
    };
    let deadline = Instant::now() + Duration::from_millis(args.timeout_ms);
    let mut cursor = args.since.max(0);
    loop {
        let value = match client
            .request_value(
                "agentCanvas.events",
                &json!({
                    "workspaceId": workspace_id,
                    "since": cursor,
                    "limit": args.limit,
                }),
            )
            .await
        {
            Ok(value) => value,
            Err(error) => return crate::print_error(error),
        };
        let events = value
            .get("events")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        if !events.is_empty() {
            for event in &events {
                cursor = event
                    .get("sequence")
                    .and_then(Value::as_i64)
                    .unwrap_or(cursor);
                if json_output {
                    println!(
                        "{}",
                        serde_json::to_string(event).unwrap_or_else(|_| "{}".to_string())
                    );
                } else {
                    println!(
                        "Agent Canvas event {}",
                        event
                            .get("eventType")
                            .and_then(Value::as_str)
                            .unwrap_or("updated")
                    );
                }
            }
            if !args.follow {
                return 0;
            }
        } else if !args.follow {
            crate::print_value(&value, json_output, "No Agent Canvas events");
            return 0;
        }
        if Instant::now() >= deadline {
            return 0;
        }
        tokio::time::sleep(EVENT_POLL_INTERVAL).await;
    }
}

async fn run_state_change(
    runtime_dir: std::path::PathBuf,
    args: CanvasIdentityArgs,
    operation: &str,
    json_output: bool,
) -> i32 {
    let mut client = match connect(&runtime_dir).await {
        Ok(client) => client,
        Err(error) => return crate::print_error(error),
    };
    let canvas_id = match resolve_canvas_id(&mut client, args).await {
        Ok(value) => value,
        Err(error) => return crate::print_error(error),
    };
    let request_type = format!("agentCanvas.{operation}");
    match client
        .request_value(&request_type, &json!({ "canvasId": canvas_id }))
        .await
    {
        Ok(value) => {
            crate::print_value(&value, json_output, &format!("Agent Canvas {operation}d"));
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn request_and_report(
    runtime_dir: &std::path::Path,
    request_type: &str,
    payload: Value,
    json_output: bool,
) -> i32 {
    let mut client = match connect(runtime_dir).await {
        Ok(client) => client,
        Err(error) => return crate::print_error(error),
    };
    match client.request_value(request_type, &payload).await {
        Ok(value) => {
            crate::print_value(&value, json_output, "Agent Canvas request completed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn connect(runtime_dir: &std::path::Path) -> Result<RuntimeHostRpcClient> {
    RuntimeHostRpcClient::connect_or_start_agent_canvas(runtime_dir).await
}

async fn resolve_canvas_id(
    client: &mut RuntimeHostRpcClient,
    args: CanvasIdentityArgs,
) -> Result<String> {
    if let Some(canvas_id) = args.canvas_id {
        return Ok(canvas_id);
    }
    let workspace_id = workspace_id(args.workspace_id)?;
    let terminal_session_id = terminal_session_id(args.terminal_session_id)?;
    let value = client
        .request_value(
            "agentCanvas.catalog",
            &json!({ "workspaceId": workspace_id, "includeHistory": true }),
        )
        .await?;
    value
        .get("canvases")
        .and_then(Value::as_array)
        .and_then(|canvases| {
            canvases.iter().find_map(|canvas| {
                (canvas.get("terminalSessionId").and_then(Value::as_str)
                    == Some(terminal_session_id.as_str()))
                .then(|| canvas.get("id").and_then(Value::as_str).map(str::to_string))
                .flatten()
            })
        })
        .ok_or_else(|| anyhow!("no Agent Canvas exists for this terminal identity"))
}

fn workspace_id(value: Option<String>) -> Result<String> {
    value
        .or_else(|| std::env::var("ALERA_WORKSPACE_ID").ok())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| anyhow!("--workspace-id is required (or set ALERA_WORKSPACE_ID)."))
}

fn terminal_session_id(value: Option<String>) -> Result<String> {
    value
        .or_else(|| std::env::var("ALERA_TERMINAL_SESSION_ID").ok())
        .or_else(|| std::env::var("ALERA_TERMINAL_HANDLE").ok())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            anyhow!("--terminal-session-id is required (or run inside an Alera terminal).")
        })
}

fn read_document(args: &CanvasPublishArgs) -> Result<Value> {
    let bytes = if let Some(path) = &args.file {
        std::fs::read(path)?
    } else if args.stdin {
        let mut bytes = Vec::new();
        std::io::stdin().read_to_end(&mut bytes)?;
        bytes
    } else if let Some(document) = &args.document {
        document.as_bytes().to_vec()
    } else {
        return Err(anyhow!("publish requires --file, --stdin, or --document."));
    };
    if let Ok(value) = serde_json::from_slice::<Value>(&bytes) {
        return Ok(value);
    }
    let messages = bytes
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.iter().all(u8::is_ascii_whitespace))
        .map(serde_json::from_slice::<Value>)
        .collect::<Result<Vec<_>, _>>()?;
    if messages.is_empty() {
        return Err(anyhow!("publish input did not contain JSON."));
    }
    Ok(json!({ "version": 1, "components": messages }))
}

fn examples() -> Value {
    json!({
        "name": "Agent Canvas",
        "version": 1,
        "components": [
            {"type": "AgentRunHeader", "props": {"title": "Review workspace", "agentType": "codex", "status": "live"}},
            {"type": "TaskProgress", "props": {"label": "Validation", "completed": 2, "total": 3}},
            {"type": "Notice", "props": {"tone": "info", "text": "Validation is still running."}},
        ]
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_lines_become_one_document() {
        let args = CanvasPublishArgs {
            workspace_id: None,
            terminal_session_id: None,
            tab_id: None,
            agent_type: None,
            title: None,
            canvas_id: None,
            expected_revision: None,
            state: None,
            file: None,
            stdin: false,
            document: Some("{\"type\":\"Notice\"}\n{\"type\":\"TaskProgress\"}".to_string()),
        };
        let document = read_document(&args).unwrap();
        assert_eq!(document["components"].as_array().unwrap().len(), 2);
    }
}
