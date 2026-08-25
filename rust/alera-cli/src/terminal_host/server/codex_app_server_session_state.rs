//! Ephemeral state scoped to one Codex app-server process.
//!
//! Flutter controllers are intentionally disposable. This state lets a new
//! controller reopen a tab once without resuming the same Codex thread again,
//! and keeps catalogue requests cheap without retaining per-tab UI listeners.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde_json::Value;
use tokio::sync::{oneshot, Mutex};

use super::codex_app_server::CodexAppServer;
use crate::terminal_host::host_error::{HostError, HostResult};

const MAX_CACHED_CATALOGUES: usize = 64;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct CodexThreadHydration {
    pub(super) thread_id: String,
    pub(super) cwd: String,
    pub(super) tab_revision_millis: i64,
    pub(super) history_next_cursor: Option<String>,
}

impl CodexThreadHydration {
    fn matches(&self, thread_id: &str, cwd: &str, tab_revision: DateTime<Utc>) -> bool {
        self.thread_id == thread_id
            && self.cwd == cwd
            && self.tab_revision_millis == tab_revision.timestamp_millis()
    }
}

#[derive(Default)]
pub(super) struct CodexAppServerSessionState {
    hydrated_tabs: Mutex<HashMap<String, CodexThreadHydration>>,
    catalogue_responses: Mutex<HashMap<String, Value>>,
    realtime_transcripts: Mutex<HashMap<String, oneshot::Sender<HostResult<String>>>>,
}

impl CodexAppServerSessionState {
    async fn take_thread_hydration(
        &self,
        tab_id: &str,
        thread_id: &str,
        cwd: &str,
        tab_revision: DateTime<Utc>,
    ) -> Option<CodexThreadHydration> {
        let hydration = self.hydrated_tabs.lock().await.remove(tab_id)?;
        hydration
            .matches(thread_id, cwd, tab_revision)
            .then_some(hydration)
    }

    async fn cache_catalogue(&self, key: String, value: Value) {
        let mut responses = self.catalogue_responses.lock().await;
        if !responses.contains_key(&key) && responses.len() >= MAX_CACHED_CATALOGUES {
            if let Some(evicted) = responses.keys().next().cloned() {
                responses.remove(&evicted);
            }
        }
        responses.insert(key, value);
    }

    async fn refresh_thread_hydration_revision(
        &self,
        tab_id: &str,
        thread_id: &str,
        cwd: &str,
        tab_revision: DateTime<Utc>,
        retained_history_window: bool,
    ) {
        let mut hydrated_tabs = self.hydrated_tabs.lock().await;
        let Some(hydration) = hydrated_tabs.get_mut(tab_id) else {
            return;
        };
        if hydration.thread_id != thread_id || hydration.cwd != cwd {
            return;
        }
        if retained_history_window {
            hydration.tab_revision_millis = tab_revision.timestamp_millis();
        } else {
            hydrated_tabs.remove(tab_id);
        }
    }

    async fn invalidate_catalogues(&self, prefix: &str) {
        self.catalogue_responses
            .lock()
            .await
            .retain(|key, _| !key.starts_with(prefix));
    }

    pub(super) async fn begin_realtime_transcript(
        &self,
        thread_id: &str,
    ) -> oneshot::Receiver<HostResult<String>> {
        let (sender, receiver) = oneshot::channel();
        self.realtime_transcripts
            .lock()
            .await
            .insert(thread_id.to_string(), sender);
        receiver
    }

    pub(super) async fn remove_realtime_transcript(&self, thread_id: &str) {
        self.realtime_transcripts.lock().await.remove(thread_id);
    }

    pub(super) async fn consume_realtime_message(&self, message: &Value) -> bool {
        let thread_id = message
            .pointer("/params/threadId")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty());
        let Some(thread_id) = thread_id else {
            return false;
        };
        let method = message.get("method").and_then(Value::as_str);
        let mut transcripts = self.realtime_transcripts.lock().await;
        if !transcripts.contains_key(thread_id) {
            return false;
        }
        let result = match method {
            Some("thread/realtime/transcript/done")
                if message.pointer("/params/role").and_then(Value::as_str) == Some("user") =>
            {
                let text = message
                    .pointer("/params/text")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|value| !value.is_empty())
                    .map(str::to_string)
                    .ok_or_else(|| HostError::state("Codex returned no transcription"));
                Some(text)
            }
            Some("thread/realtime/error") => Some(Err(HostError::state(
                message
                    .pointer("/params/message")
                    .and_then(Value::as_str)
                    .unwrap_or("Codex realtime dictation failed"),
            ))),
            Some("thread/realtime/closed") => Some(Err(HostError::state(
                "Codex realtime dictation closed before returning a transcript",
            ))),
            _ => None,
        };
        if let Some(result) = result {
            if let Some(sender) = transcripts.remove(thread_id) {
                let _ = sender.send(result);
            }
        }
        true
    }
}

impl CodexAppServer {
    pub(super) async fn take_thread_hydration(
        &self,
        tab_id: &str,
        thread_id: &str,
        cwd: &str,
        tab_revision: DateTime<Utc>,
    ) -> Option<CodexThreadHydration> {
        self.session_state
            .take_thread_hydration(tab_id, thread_id, cwd, tab_revision)
            .await
    }

    pub(super) async fn record_thread_hydration(
        &self,
        tab_id: &str,
        thread_id: &str,
        cwd: &str,
        tab_revision: DateTime<Utc>,
        history_next_cursor: Option<String>,
    ) {
        self.session_state.hydrated_tabs.lock().await.insert(
            tab_id.to_string(),
            CodexThreadHydration {
                thread_id: thread_id.to_string(),
                cwd: cwd.to_string(),
                tab_revision_millis: tab_revision.timestamp_millis(),
                history_next_cursor,
            },
        );
    }

    pub(super) async fn refresh_thread_hydration_revision(
        &self,
        tab_id: &str,
        thread_id: &str,
        cwd: &str,
        tab_revision: DateTime<Utc>,
        retained_history_window: bool,
    ) {
        self.session_state
            .refresh_thread_hydration_revision(
                tab_id,
                thread_id,
                cwd,
                tab_revision,
                retained_history_window,
            )
            .await;
    }

    pub(super) async fn forget_thread_hydration(&self, tab_id: &str) {
        self.session_state.hydrated_tabs.lock().await.remove(tab_id);
    }

    pub(super) async fn clear_thread_hydrations(&self) {
        self.session_state.hydrated_tabs.lock().await.clear();
    }

    pub(super) async fn cached_catalogue(&self, key: &str) -> Option<Value> {
        self.session_state
            .catalogue_responses
            .lock()
            .await
            .get(key)
            .cloned()
    }

    pub(super) async fn cache_catalogue(&self, key: String, value: Value) {
        self.session_state.cache_catalogue(key, value).await;
    }

    pub(super) async fn invalidate_catalogues(&self, prefix: &str) {
        self.session_state.invalidate_catalogues(prefix).await;
    }
}

#[cfg(test)]
mod tests {
    use super::{CodexAppServerSessionState, CodexThreadHydration, MAX_CACHED_CATALOGUES};
    use chrono::{Duration, Timelike, Utc};
    use serde_json::json;

    #[tokio::test]
    async fn hydration_is_consumed_once_and_requires_the_same_identity() {
        let state = CodexAppServerSessionState::default();
        let tab_revision = Utc::now().with_nanosecond(123_456_789).unwrap();
        state.hydrated_tabs.lock().await.insert(
            "tab-1".to_string(),
            CodexThreadHydration {
                thread_id: "thread-1".to_string(),
                cwd: "/workspace".to_string(),
                tab_revision_millis: tab_revision.timestamp_millis(),
                history_next_cursor: Some("older".to_string()),
            },
        );

        let hydration = state
            .take_thread_hydration("tab-1", "thread-1", "/workspace", tab_revision)
            .await
            .unwrap();
        assert_eq!(hydration.history_next_cursor.as_deref(), Some("older"));
        assert!(state
            .take_thread_hydration(
                "tab-1",
                "thread-1",
                "/workspace",
                tab_revision.with_nanosecond(123_000_000).unwrap(),
            )
            .await
            .is_none());

        state.hydrated_tabs.lock().await.insert(
            "tab-1".to_string(),
            CodexThreadHydration {
                thread_id: "thread-1".to_string(),
                cwd: "/workspace".to_string(),
                tab_revision_millis: tab_revision.timestamp_millis(),
                history_next_cursor: Some("older".to_string()),
            },
        );
        assert!(state
            .take_thread_hydration(
                "tab-1",
                "thread-1",
                "/workspace",
                tab_revision + Duration::seconds(1),
            )
            .await
            .is_none());
    }

    #[tokio::test]
    async fn live_revision_refresh_preserves_or_invalidates_the_history_cursor() {
        let state = CodexAppServerSessionState::default();
        let first_revision = Utc::now();
        let next_revision = first_revision + Duration::seconds(1);
        state.hydrated_tabs.lock().await.insert(
            "tab-1".to_string(),
            CodexThreadHydration {
                thread_id: "thread-1".to_string(),
                cwd: "/workspace".to_string(),
                tab_revision_millis: first_revision.timestamp_millis(),
                history_next_cursor: Some("older".to_string()),
            },
        );

        state
            .refresh_thread_hydration_revision(
                "tab-1",
                "thread-1",
                "/workspace",
                next_revision,
                true,
            )
            .await;
        let refreshed = state
            .take_thread_hydration("tab-1", "thread-1", "/workspace", next_revision)
            .await
            .unwrap();
        assert_eq!(refreshed.history_next_cursor.as_deref(), Some("older"));

        state.hydrated_tabs.lock().await.insert(
            "tab-1".to_string(),
            CodexThreadHydration {
                thread_id: "thread-1".to_string(),
                cwd: "/workspace".to_string(),
                tab_revision_millis: next_revision.timestamp_millis(),
                history_next_cursor: Some("older".to_string()),
            },
        );

        state
            .refresh_thread_hydration_revision(
                "tab-1",
                "thread-1",
                "/workspace",
                next_revision + Duration::seconds(1),
                false,
            )
            .await;
        assert!(state.hydrated_tabs.lock().await.get("tab-1").is_none());
    }

    #[tokio::test]
    async fn catalogue_invalidation_is_scoped_by_prefix() {
        let state = CodexAppServerSessionState::default();
        state.catalogue_responses.lock().await.extend([
            ("skills:/workspace".to_string(), json!({"skills": []})),
            ("apps:thread-1".to_string(), json!({"apps": []})),
            ("models".to_string(), json!({"models": []})),
        ]);
        state.invalidate_catalogues("skills:").await;

        let entries = state.catalogue_responses.lock().await;
        assert!(!entries.contains_key("skills:/workspace"));
        assert!(entries.contains_key("apps:thread-1"));
        assert!(entries.contains_key("models"));
    }

    #[tokio::test]
    async fn catalogue_cache_has_a_fixed_upper_bound() {
        let state = CodexAppServerSessionState::default();
        for index in 0..=MAX_CACHED_CATALOGUES {
            state
                .cache_catalogue(format!("apps:{index}"), json!({"apps": []}))
                .await;
        }

        let responses = state.catalogue_responses.lock().await;
        assert_eq!(responses.len(), MAX_CACHED_CATALOGUES);
    }

    #[tokio::test]
    async fn realtime_user_transcript_completes_the_matching_waiter() {
        let state = CodexAppServerSessionState::default();
        let transcript = state.begin_realtime_transcript("thread-dictation").await;

        assert!(
            state
                .consume_realtime_message(&json!({
                    "method": "thread/realtime/transcript/done",
                    "params": {
                        "threadId": "thread-dictation",
                        "role": "user",
                        "text": "hello from Codex",
                    }
                }))
                .await
        );
        assert_eq!(
            transcript.await.unwrap().unwrap(),
            "hello from Codex".to_string()
        );
    }

    #[tokio::test]
    async fn unrelated_realtime_messages_are_not_consumed() {
        let state = CodexAppServerSessionState::default();
        assert!(
            !state
                .consume_realtime_message(&json!({
                    "method": "thread/realtime/transcript/done",
                    "params": {
                        "threadId": "ordinary-thread",
                        "role": "user",
                        "text": "hello",
                    }
                }))
                .await
        );
    }
}
