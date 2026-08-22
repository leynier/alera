use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_app_server::CodexAppServer;
use super::codex_state::{latest_turn_page, older_turn_page, CodexTurnHistoryPage};

const APP_SERVER_HISTORY_CURSOR_PREFIX: &str = "alera-app-server-history:";
const MAX_CACHED_THREAD_HISTORIES: usize = 4;
const MAX_CACHED_THREAD_HISTORY_BYTES: usize = 8 * 1024 * 1024;

struct CachedThreadHistory {
    pages: HashMap<String, Arc<CodexTurnHistoryPage>>,
    limit: usize,
    bytes: usize,
}

#[derive(Debug, Deserialize, Serialize)]
struct AppServerHistoryCursor {
    page_cursor: Option<String>,
    local_cursor: Option<String>,
    #[serde(default)]
    next_page_cursor: Option<String>,
    #[serde(default)]
    inclusive_turn_id: Option<String>,
}

#[derive(Default)]
pub(super) struct ThreadHistoryCache {
    entries: HashMap<String, CachedThreadHistory>,
    order: VecDeque<String>,
    total_bytes: usize,
}

impl ThreadHistoryCache {
    fn get(
        &self,
        thread_id: &str,
        cursor: &str,
        limit: usize,
    ) -> Option<Arc<CodexTurnHistoryPage>> {
        let entry = self.entries.get(thread_id)?;
        if entry.limit != limit.max(1) {
            return None;
        }
        entry.pages.get(cursor).cloned()
    }
    fn cursor_is_reusable(&self, thread_id: &str, cursor: &str, limit: usize) -> bool {
        self.get(thread_id, cursor, limit).is_some()
            || decode_history_cursor(cursor).is_ok_and(|decoded| decoded.page_cursor.is_some())
    }
    fn insert(
        &mut self,
        thread_id: &str,
        response: &Value,
        limit: usize,
        page_cursor: Option<&str>,
        next_page_cursor: Option<&str>,
        inclusive_turn_id: Option<&str>,
    ) -> Option<CodexTurnHistoryPage> {
        let limit = limit.max(1);
        let mut latest = latest_turn_page(response, limit)?;
        let mut cursor = latest.next_cursor.clone();
        latest.next_cursor = history_continuation_cursor(
            page_cursor,
            cursor.as_deref(),
            next_page_cursor,
            inclusive_turn_id,
        );
        self.remove(thread_id);
        let mut pages = Vec::<(String, CodexTurnHistoryPage, usize)>::new();
        let mut seen = HashSet::new();
        let mut bytes = 0_usize;
        let mut truncated = false;
        while let Some(local_cursor) = cursor.take() {
            if !seen.insert(local_cursor.clone()) {
                truncated = true;
                break;
            }
            let Ok((page, next_local_cursor)) = project_local_history_page(
                response,
                &local_cursor,
                limit,
                page_cursor,
                next_page_cursor,
                inclusive_turn_id,
            ) else {
                truncated = true;
                break;
            };
            let Ok(page_bytes) = encoded_history_page_bytes(&page) else {
                truncated = true;
                break;
            };
            if bytes.saturating_add(page_bytes) > MAX_CACHED_THREAD_HISTORY_BYTES {
                truncated = true;
                break;
            }
            bytes = bytes.saturating_add(page_bytes);
            let cache_cursor = encode_history_cursor(AppServerHistoryCursor {
                page_cursor: page_cursor.map(str::to_string),
                local_cursor: Some(local_cursor),
                next_page_cursor: next_page_cursor.map(str::to_string),
                inclusive_turn_id: inclusive_turn_id.map(str::to_string),
            });
            pages.push((cache_cursor, page, page_bytes));
            cursor = next_local_cursor;
        }
        if truncated && page_cursor.is_none() {
            if let Some((_, page, _)) = pages.last_mut() {
                page.next_cursor = None;
            } else {
                latest.next_cursor = None;
            }
        }
        if !pages.is_empty() {
            self.order.retain(|value| value != thread_id);
            self.order.push_back(thread_id.to_string());
            self.total_bytes = self.total_bytes.saturating_add(bytes);
            self.entries.insert(
                thread_id.to_string(),
                CachedThreadHistory {
                    pages: pages
                        .into_iter()
                        .map(|(cursor, page, _)| (cursor, Arc::new(page)))
                        .collect(),
                    limit,
                    bytes,
                },
            );
            while self.entries.len() > MAX_CACHED_THREAD_HISTORIES
                || self.total_bytes > MAX_CACHED_THREAD_HISTORY_BYTES
            {
                if let Some(oldest) = self.order.pop_front() {
                    self.remove(&oldest);
                }
            }
        }
        Some(latest)
    }

    fn remove(&mut self, thread_id: &str) {
        if let Some(entry) = self.entries.remove(thread_id) {
            self.total_bytes = self.total_bytes.saturating_sub(entry.bytes);
        }
        self.order.retain(|value| value != thread_id);
    }
}
impl CodexAppServer {
    pub(super) async fn history_cursor_is_reusable(
        &self,
        thread_id: &str,
        cursor: Option<&str>,
        limit: usize,
    ) -> bool {
        let Some(cursor) = cursor else { return true };
        self.thread_history
            .lock()
            .await
            .cursor_is_reusable(thread_id, cursor, limit)
    }

    pub(super) async fn project_resumed_thread_history(
        &self,
        thread_id: &str,
        response: &Value,
        limit: usize,
    ) -> HostResult<Option<CodexTurnHistoryPage>> {
        let Some(mut history_response) = resume_history_response(response) else {
            return Ok(None);
        };
        let (next_page_cursor, inclusive_turn_id) = resumed_history_continuation(response);
        let mut next_page_cursor = next_page_cursor.map(str::to_string);
        if let Some(boundary_turns) = resumed_history_boundary_turns(response) {
            let (turns, cursor) = self
                .complete_review_boundary(
                    thread_id,
                    boundary_turns,
                    next_page_cursor,
                    inclusive_turn_id,
                )
                .await;
            history_response = history_response_from_descending_turns(&turns);
            next_page_cursor = cursor;
        }
        Ok(self.thread_history.lock().await.insert(
            thread_id,
            &history_response,
            limit,
            None,
            next_page_cursor.as_deref(),
            inclusive_turn_id,
        ))
    }

    pub(super) async fn load_thread_history_page(
        &self,
        thread_id: &str,
        cursor: &str,
        limit: usize,
    ) -> HostResult<CodexTurnHistoryPage> {
        if let Some(cached) = self
            .thread_history
            .lock()
            .await
            .get(thread_id, cursor, limit)
        {
            return Ok(cached.as_ref().clone());
        }
        let decoded = decode_history_cursor(cursor).map_err(HostError::format)?;
        let page_cursor = native_page_cursor(&decoded).map_err(HostError::state)?;
        let request_limit = limit
            .max(1)
            .saturating_add(1)
            .saturating_add(usize::from(decoded.inclusive_turn_id.is_some()));
        let response = self
            .request(
                "thread/turns/list",
                json!({
                    "threadId": thread_id,
                    "limit": request_limit,
                    "sortDirection": "desc",
                    "itemsView": "full",
                    "cursor": page_cursor,
                }),
            )
            .await?;
        let turns = response
            .get("data")
            .and_then(Value::as_array)
            .cloned()
            .ok_or_else(|| HostError::state("Codex thread history is unavailable."))?;
        let next_page_cursor = response
            .get("nextCursor")
            .and_then(Value::as_str)
            .map(str::to_string);
        let (turns, next_page_cursor) = self
            .complete_review_boundary(thread_id, turns, next_page_cursor, None)
            .await;
        let response = json!({
            "data": turns,
            "nextCursor": next_page_cursor,
        });
        let history_response =
            turns_list_history_response(&response, decoded.inclusive_turn_id.as_deref())
                .ok_or_else(|| HostError::state("Codex thread history is unavailable."))?;
        let next_page_cursor = response
            .get("nextCursor")
            .and_then(Value::as_str)
            .map(str::to_string);
        let first = self.thread_history.lock().await.insert(
            thread_id,
            &history_response,
            limit,
            Some(page_cursor),
            next_page_cursor.as_deref(),
            None,
        );
        let Some(local_cursor) = decoded.local_cursor.as_deref() else {
            return first.ok_or_else(|| HostError::state("Codex thread history is unavailable."));
        };
        project_local_history_page(
            &history_response,
            local_cursor,
            limit,
            Some(page_cursor),
            next_page_cursor.as_deref(),
            None,
        )
        .map(|(page, _)| page)
        .map_err(HostError::format)
    }

    async fn complete_review_boundary(
        &self,
        thread_id: &str,
        turns: Vec<Value>,
        next_cursor: Option<String>,
        inclusive_turn_id: Option<&str>,
    ) -> (Vec<Value>, Option<String>) {
        let Some(next_cursor) = next_cursor else {
            return (turns, None);
        };
        let Some(cursor) = review_boundary_cursor(&turns, Some(&next_cursor)) else {
            return (turns, Some(next_cursor));
        };
        let cursor = cursor.to_string();
        let response = match self
            .request(
                "thread/turns/list",
                json!({
                    "threadId": thread_id,
                    "limit": review_boundary_fetch_limit(inclusive_turn_id),
                    "sortDirection": "desc",
                    "itemsView": "full",
                    "cursor": cursor,
                }),
            )
            .await
        {
            Ok(response) => Some(response),
            Err(error) => {
                tracing::warn!(
                    target: "codex_app_server",
                    "Codex review history boundary could not be completed: {error}"
                );
                None
            }
        };
        merge_review_boundary_response(turns, next_cursor, response.as_ref())
    }
}

fn merge_review_boundary_response(
    mut turns: Vec<Value>,
    next_cursor: String,
    response: Option<&Value>,
) -> (Vec<Value>, Option<String>) {
    let Some(response) = response else {
        return (turns, Some(next_cursor));
    };
    let Some(older_turns) = response.get("data").and_then(Value::as_array) else {
        return (turns, Some(next_cursor));
    };
    let known_ids = turns
        .iter()
        .filter_map(|turn| turn.get("id").and_then(Value::as_str))
        .map(str::to_string)
        .collect::<HashSet<_>>();
    turns.extend(
        older_turns
            .iter()
            .filter(|turn| {
                turn.get("id")
                    .and_then(Value::as_str)
                    .is_none_or(|id| !known_ids.contains(id))
            })
            .cloned(),
    );
    (
        turns,
        response
            .get("nextCursor")
            .and_then(Value::as_str)
            .map(str::to_string),
    )
}

fn review_boundary_fetch_limit(inclusive_turn_id: Option<&str>) -> usize {
    1 + usize::from(inclusive_turn_id.is_some())
}

fn review_boundary_cursor<'a>(turns: &[Value], next_cursor: Option<&'a str>) -> Option<&'a str> {
    next_cursor.filter(|_| {
        turns.last().is_some_and(
            super::codex_state::codex_review_transition::history_turn_may_be_review_worker,
        )
    })
}

fn history_continuation_cursor(
    page_cursor: Option<&str>,
    local_cursor: Option<&str>,
    next_page_cursor: Option<&str>,
    inclusive_turn_id: Option<&str>,
) -> Option<String> {
    if let Some(local_cursor) = local_cursor {
        return Some(encode_history_cursor(AppServerHistoryCursor {
            page_cursor: page_cursor.map(str::to_string),
            local_cursor: Some(local_cursor.to_string()),
            next_page_cursor: next_page_cursor.map(str::to_string),
            inclusive_turn_id: inclusive_turn_id.map(str::to_string),
        }));
    }
    next_page_cursor.map(|next_page_cursor| {
        encode_history_cursor(AppServerHistoryCursor {
            page_cursor: Some(next_page_cursor.to_string()),
            local_cursor: None,
            next_page_cursor: None,
            inclusive_turn_id: inclusive_turn_id.map(str::to_string),
        })
    })
}

fn project_local_history_page(
    response: &Value,
    local_cursor: &str,
    limit: usize,
    page_cursor: Option<&str>,
    next_page_cursor: Option<&str>,
    inclusive_turn_id: Option<&str>,
) -> Result<(CodexTurnHistoryPage, Option<String>), &'static str> {
    let mut page = older_turn_page(response, local_cursor, limit)?;
    let next_local_cursor = page.next_cursor.clone();
    page.next_cursor = history_continuation_cursor(
        page_cursor,
        next_local_cursor.as_deref(),
        next_page_cursor,
        inclusive_turn_id,
    );
    Ok((page, next_local_cursor))
}

fn encode_history_cursor(cursor: AppServerHistoryCursor) -> String {
    format!(
        "{APP_SERVER_HISTORY_CURSOR_PREFIX}{}",
        serde_json::to_string(&cursor).expect("history cursor is serializable")
    )
}

fn decode_history_cursor(cursor: &str) -> Result<AppServerHistoryCursor, &'static str> {
    let encoded = cursor
        .strip_prefix(APP_SERVER_HISTORY_CURSOR_PREFIX)
        .ok_or("Codex history cursor is invalid.")?;
    serde_json::from_str(encoded).map_err(|_| "Codex history cursor is invalid.")
}

fn native_page_cursor(cursor: &AppServerHistoryCursor) -> Result<&str, &'static str> {
    cursor
        .page_cursor
        .as_deref()
        .ok_or("Codex history cursor expired. Reload the conversation and try again.")
}

fn resume_history_response(response: &Value) -> Option<Value> {
    if let Some(initial_turns) = response
        .pointer("/initialTurnsPage/data")
        .and_then(Value::as_array)
    {
        return Some(history_response_from_descending_turns(initial_turns));
    }
    thread_read_history_response(response)
}

fn resumed_history_boundary_turns(response: &Value) -> Option<Vec<Value>> {
    if let Some(initial_turns) = response
        .pointer("/initialTurnsPage/data")
        .and_then(Value::as_array)
    {
        return Some(initial_turns.clone());
    }
    response
        .pointer("/thread/turns")
        .and_then(Value::as_array)
        .map(|turns| turns.iter().rev().cloned().collect())
}

fn resumed_history_continuation(response: &Value) -> (Option<&str>, Option<&str>) {
    if let Some(cursor) = response
        .pointer("/initialTurnsPage/nextCursor")
        .and_then(Value::as_str)
    {
        return (Some(cursor), None);
    }
    (
        response.get("turnsBackwardsCursor").and_then(Value::as_str),
        response
            .pointer("/thread/turns/0/id")
            .and_then(Value::as_str),
    )
}

fn turns_list_history_response(response: &Value, inclusive_turn_id: Option<&str>) -> Option<Value> {
    let turns = response.get("data")?.as_array()?;
    let turns = turns
        .iter()
        .filter(|turn| turn.get("id").and_then(Value::as_str) != inclusive_turn_id)
        .cloned()
        .collect::<Vec<_>>();
    Some(history_response_from_descending_turns(&turns))
}

fn history_response_from_descending_turns(turns: &[Value]) -> Value {
    let turns = turns.iter().rev().cloned().collect::<Vec<_>>();
    json!({"thread": {"turns": turns}})
}

fn thread_read_history_response(response: &Value) -> Option<Value> {
    let turns = response.pointer("/thread/turns")?.as_array()?.clone();
    Some(json!({"thread": {"turns": turns}}))
}

fn encoded_history_page_bytes(page: &CodexTurnHistoryPage) -> serde_json::Result<usize> {
    serde_json::to_vec(&json!({
        "snapshot": &page.snapshot,
        "turns": &page.turns,
        "nextCursor": &page.next_cursor,
    }))
    .map(|encoded| encoded.len())
}

#[cfg(test)]
#[path = "codex_app_server_history_tests.rs"]
mod tests;
