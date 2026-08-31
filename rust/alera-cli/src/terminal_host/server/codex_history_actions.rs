//! Forks use complete native history, never a client's paginated projection.

use super::codex_app_server::CodexAppServer;
use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

pub(super) fn turn_complete(turn: &Value) -> bool {
    matches!(
        turn.get("status").and_then(Value::as_str),
        Some("completed" | "interrupted" | "failed")
    )
}

pub(super) async fn read_turns(server: &CodexAppServer, thread_id: &str) -> HostResult<Vec<Value>> {
    let mut turns = Vec::new();
    let mut paginated_items = false;
    let mut cursor = None;
    let mut seen = std::collections::HashSet::new();
    loop {
        let mut params = json!({"threadId": thread_id, "limit": 100, "sortDirection": "asc", "itemsView": "full"});
        if let Some(cursor) = &cursor {
            params["cursor"] = json!(cursor);
        }
        if paginated_items {
            params["itemsView"] = json!("summary");
        }
        let response = match server.request("thread/turns/list", params.clone()).await {
            Ok(response) => response,
            Err(error)
                if !paginated_items
                    && error.wire_message().to_lowercase().contains("paginated") =>
            {
                paginated_items = true;
                params["itemsView"] = json!("summary");
                server.request("thread/turns/list", params).await?
            }
            Err(error) if turns.is_empty() && unsupported(&error) => {
                let read = server
                    .request(
                        "thread/read",
                        json!({"threadId": thread_id, "includeTurns": true}),
                    )
                    .await?;
                return read
                    .pointer("/thread/turns")
                    .and_then(Value::as_array)
                    .cloned()
                    .ok_or_else(|| HostError::state("Complete Codex history is unavailable."));
            }
            Err(error) => return Err(error),
        };
        let page = response
            .get("data")
            .or_else(|| response.get("turns"))
            .and_then(Value::as_array)
            .ok_or_else(|| HostError::state("Codex returned an invalid history page."))?;
        turns.extend(page.iter().cloned());
        cursor = response
            .get("nextCursor")
            .and_then(Value::as_str)
            .map(str::to_string);
        let Some(next) = &cursor else {
            if paginated_items {
                hydrate_paginated_items(server, thread_id, &mut turns).await?;
            }
            return Ok(turns);
        };
        if !seen.insert(next.clone()) || turns.len() > 100_000 {
            return Err(HostError::state(
                "Codex history pagination could not be completed safely.",
            ));
        }
    }
}

pub(super) fn unsupported(error: &HostError) -> bool {
    let message = error.wire_message().to_lowercase();
    message.contains("method not found")
        || message.contains("unknown variant")
        || message.contains("unknown method")
        || message.contains("-32601")
}

async fn hydrate_paginated_items(
    server: &CodexAppServer,
    thread_id: &str,
    turns: &mut [Value],
) -> HostResult<()> {
    let mut cursor = None;
    let mut seen = std::collections::HashSet::new();
    let mut items_by_turn: std::collections::HashMap<String, Vec<Value>> =
        std::collections::HashMap::new();
    let mut count = 0;
    loop {
        let mut params = json!({"threadId":thread_id,"limit":100,"sortDirection":"asc"});
        if let Some(cursor) = &cursor {
            params["cursor"] = json!(cursor);
        }
        let response = server.request("thread/items/list", params).await?;
        let items = response["data"]
            .as_array()
            .ok_or_else(|| HostError::state("Codex returned an invalid items page."))?;
        for entry in items {
            let id = entry["turnId"]
                .as_str()
                .ok_or_else(|| HostError::state("Codex history item has no turn identity."))?;
            let item = entry
                .get("item")
                .ok_or_else(|| HostError::state("Codex history item is unavailable."))?;
            items_by_turn
                .entry(id.into())
                .or_default()
                .push(item.clone());
        }
        count += items.len();
        cursor = response["nextCursor"].as_str().map(str::to_string);
        let Some(next) = &cursor else {
            break;
        };
        if !seen.insert(next.clone()) || count > 1_000_000 {
            return Err(HostError::state(
                "Codex item pagination could not be completed safely.",
            ));
        }
    }
    for turn in turns {
        let items = items_by_turn
            .remove(turn["id"].as_str().unwrap_or_default())
            .unwrap_or_default();
        turn["items"] = json!(items);
        turn["itemsView"] = json!("full");
    }
    Ok(())
}
