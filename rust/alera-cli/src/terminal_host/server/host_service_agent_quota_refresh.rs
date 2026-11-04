//! Usage-limit quota refreshes. When a chat turn fails on a usage limit, the
//! host refetches that provider's quota so the cached snapshot and every
//! client see the limit before the cache expires. One refresh runs at a time,
//! and it waits behind client fetches already in flight, which may have read
//! the usage from before the limit.

use std::collections::BTreeSet;

use alera_provider_protocol::FailureClass;
use serde_json::{json, Value};

use crate::agent_quota::fetch_agent_quotas;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;
use crate::terminal_host::server::agent_chat_runtime::wire::ChatTurn;
use crate::terminal_host::server::agent_chat_runtime::ChatRuntimeEvent;

use super::super::{ServerActor, ServerCommand};
use super::{merge_quota_snapshots, upsert_quota_snapshot};

/// Client ids start at 1, so 0 marks the host's own refresh.
pub(super) const HOST_REFRESH_CLIENT_ID: u64 = 0;

/// A refresh to start: its generation and the quota providers it fetches.
#[derive(Debug, PartialEq, Eq)]
pub(super) struct RefreshStart {
    pub(super) generation: i64,
    pub(super) providers: Vec<String>,
}

/// Usage refreshes of the cached snapshot.
#[derive(Debug, Default)]
pub(super) struct UsageRefresh {
    generation: i64,
    running: Option<i64>,
    /// Providers the next refresh fetches.
    queued: BTreeSet<String>,
    /// `(client, request)` of each client fetch in flight.
    client_fetches: BTreeSet<(u64, i64)>,
}

impl UsageRefresh {
    /// Queues `provider`; a burst of limits shares one refresh.
    pub(super) fn request(&mut self, provider: &str) -> Option<RefreshStart> {
        self.queued.insert(provider.to_owned());
        self.next()
    }

    pub(super) fn client_fetch_started(&mut self, client_id: u64, request_id: i64) {
        self.client_fetches.insert((client_id, request_id));
    }

    pub(super) fn client_fetch_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
    ) -> Option<RefreshStart> {
        self.client_fetches.remove(&(client_id, request_id));
        self.next()
    }

    pub(super) fn finished(&mut self, generation: i64) -> Option<RefreshStart> {
        if self.running == Some(generation) {
            self.running = None;
        }
        self.next()
    }

    fn next(&mut self) -> Option<RefreshStart> {
        if self.running.is_some() || !self.client_fetches.is_empty() || self.queued.is_empty() {
            return None;
        }
        self.generation += 1;
        self.running = Some(self.generation);
        Some(RefreshStart {
            generation: self.generation,
            providers: std::mem::take(&mut self.queued).into_iter().collect(),
        })
    }
}

impl ServerActor {
    /// Refreshes the quota of each provider whose turn this commit failed on a
    /// usage limit.
    pub(in crate::terminal_host::server) fn refresh_agent_quotas_after_usage_limit(
        &mut self,
        event: &ChatRuntimeEvent,
    ) {
        for start in self.queue_agent_quota_refreshes(event) {
            self.spawn_agent_quota_refresh(start);
        }
    }

    pub(super) fn queue_agent_quota_refreshes(
        &mut self,
        event: &ChatRuntimeEvent,
    ) -> Vec<RefreshStart> {
        let providers = usage_limited_providers(event);
        // Without a cached snapshot, the next request fetches fresh quotas.
        let Some(cache) = self.agent_quota_cache.as_mut() else {
            return Vec::new();
        };
        providers
            .into_iter()
            .filter(|provider| {
                cache.snapshot["snapshots"]
                    .as_array()
                    .is_some_and(|snapshots| snapshots.iter().any(|s| s["provider"] == *provider))
            })
            .filter_map(|provider| cache.refresh.request(provider))
            .collect()
    }

    pub(super) fn spawn_agent_quota_refresh(&self, start: RefreshStart) {
        let Some(environment_signature) = self
            .agent_quota_cache
            .as_ref()
            .map(|cache| cache.environment_signature)
        else {
            return;
        };
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                let settings = store
                    .agent_quota_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                fetch_agent_quotas(json!({
                    "providers": start.providers,
                    "claudeDefaultEnabled": settings.claude_default_enabled,
                    "claudeProfiles": settings.claude_profiles,
                    "environmentNames": settings.environment,
                    "allowCliFallback": false,
                }))
                .await
                .map_err(|error| HostError::state(error.to_string()))
            }
            .await;
            let _ = inbox
                .send_wait(ServerCommand::AgentQuotaFinished {
                    client_id: HOST_REFRESH_CLIENT_ID,
                    request_id: start.generation,
                    environment_signature,
                    result,
                })
                .await;
        });
    }

    pub(super) fn handle_agent_quota_refresh_finished(
        &mut self,
        generation: i64,
        result: HostResult<Value>,
    ) {
        if let Some(start) = self.apply_agent_quota_refresh(generation, result) {
            self.spawn_agent_quota_refresh(start);
        }
    }

    /// Merges a refresh into the cached snapshot, keeping its age: the other
    /// providers were not fetched again.
    pub(super) fn apply_agent_quota_refresh(
        &mut self,
        generation: i64,
        result: HostResult<Value>,
    ) -> Option<RefreshStart> {
        let cache = self.agent_quota_cache.as_mut()?;
        let refreshed = result.is_ok();
        if let Ok(fresh) = result {
            let fresh = merge_quota_snapshots(&cache.snapshot, fresh);
            for snapshot in fresh["snapshots"].as_array().into_iter().flatten() {
                cache.snapshot = upsert_quota_snapshot(Some(&cache.snapshot), snapshot.clone());
            }
        }
        let next = cache.refresh.finished(generation);
        if refreshed {
            self.broadcast_authenticated(event("agentQuotasChanged", json!({})));
        }
        next
    }
}

/// Quota providers of the turns in a commit that failed on a usage limit.
fn usage_limited_providers(event: &ChatRuntimeEvent) -> BTreeSet<&'static str> {
    let ChatRuntimeEvent::Changed { delta, .. } = event else {
        return BTreeSet::new();
    };
    delta["turns"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|turn| serde_json::from_value::<ChatTurn>(turn.clone()).ok())
        .filter(|turn| {
            turn.status == "failed" && turn.failure_class == Some(FailureClass::UsageLimit)
        })
        .filter_map(|turn| quota_provider(&turn.provider))
        .collect()
}

/// The quota snapshot provider whose usage a chat provider spends.
fn quota_provider(chat_provider: &str) -> Option<&'static str> {
    Some(match chat_provider {
        "claudeAgent" => "claude",
        "codex" => "codex",
        "cursor" => "cursor",
        "grok" => "grok",
        "opencode" => "opencode",
        "antigravity" => "antigravity",
        _ => return None,
    })
}
