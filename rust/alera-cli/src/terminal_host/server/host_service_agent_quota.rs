use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::agent_quota::{consume_codex_reset_credit, fetch_agent_quotas, fetch_claude_tui};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

#[path = "host_service_agent_quota_refresh.rs"]
mod refresh;
#[cfg(test)]
#[path = "host_service_agent_quota_refresh_tests.rs"]
mod refresh_tests;

use refresh::{UsageRefresh, HOST_REFRESH_CLIENT_ID};

const AGENT_QUOTA_CACHE_TTL: Duration = Duration::from_secs(15 * 60);

/// The host's last quota snapshot and the usage refreshes that update it.
pub(super) struct AgentQuotaCache {
    fetched_at: Instant,
    environment_signature: u64,
    snapshot: Value,
    refresh: UsageRefresh,
}

impl ServerActor {
    pub(super) fn start_agent_quota_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let force_refresh = payload
            .get("forceRefresh")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let environment_values = payload
            .get("environmentValues")
            .cloned()
            .unwrap_or_else(|| json!({}));
        let environment_signature = quota_environment_signature(&environment_values);
        if !force_refresh {
            if let Some(cache) = &self.agent_quota_cache {
                if cache.environment_signature == environment_signature
                    && cache.fetched_at.elapsed() < AGENT_QUOTA_CACHE_TTL
                {
                    self.client_write(client_id, ok_response(request_id, cache.snapshot.clone()));
                    return Ok(());
                }
            }
        }
        if let Some(cache) = self.agent_quota_cache.as_mut() {
            cache.refresh.client_fetch_started(client_id, request_id);
        }
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                let settings = store
                    .agent_quota_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let providers = if settings.enabled_providers.is_empty() {
                    vec!["__none__".to_string()]
                } else {
                    settings.enabled_providers
                };
                let quota_payload = json!({
                    "providers": providers,
                    "claudeDefaultEnabled": settings.claude_default_enabled,
                    "claudeProfiles": settings.claude_profiles,
                    "environmentNames": settings.environment,
                    "environmentValues": environment_values,
                    "allowCliFallback": false,
                });
                fetch_agent_quotas(quota_payload)
                    .await
                    .map_err(|error| HostError::state(error.to_string()))
            }
            .await;
            let _ = inbox
                .send_wait(ServerCommand::AgentQuotaFinished {
                    client_id,
                    request_id,
                    environment_signature,
                    result,
                })
                .await;
        });
        Ok(())
    }

    pub(super) fn start_agent_quota_claude_tui_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let account_id = required_non_blank(payload, "accountId")?;
        let environment_signature = self
            .agent_quota_cache
            .as_ref()
            .map(|cache| cache.environment_signature)
            .unwrap_or(0);
        let store = self.runtime_store.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = async {
                let settings = store
                    .agent_quota_settings()
                    .await
                    .map_err(|error| HostError::state(error.to_string()))?;
                let display_name = if account_id == "default" {
                    "Default".to_string()
                } else {
                    settings
                        .claude_profiles
                        .iter()
                        .find(|profile| profile.profile == account_id)
                        .map(|profile| profile.alias.clone())
                        .unwrap_or_else(|| account_id.clone())
                };
                let snapshot_value = fetch_claude_tui(&account_id, &display_name).await;
                Ok(json!({
                    "snapshot": snapshot_value.clone(),
                    "snapshots": [snapshot_value],
                    "environment": {},
                }))
            }
            .await;
            let _ = inbox
                .send_wait(ServerCommand::AgentQuotaClaudeTuiFinished {
                    client_id,
                    request_id,
                    environment_signature,
                    result,
                })
                .await;
        });
        Ok(())
    }

    pub(super) fn start_agent_quota_codex_reset_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) {
        let environment_signature = self
            .agent_quota_cache
            .as_ref()
            .map(|cache| cache.environment_signature)
            .unwrap_or(0);
        let store = self.runtime_store.clone();
        let payload = payload.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = consume_codex_reset_credit(&store, payload)
                .await
                .map_err(|error| HostError::state(error.to_string()));
            let _ = inbox
                .send_wait(ServerCommand::AgentQuotaCodexResetFinished {
                    client_id,
                    request_id,
                    environment_signature,
                    result,
                })
                .await;
        });
    }

    pub(super) fn handle_agent_quota_claude_tui_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(fresh) => {
                let Some(snapshot) = fresh.get("snapshot").cloned() else {
                    self.client_write(
                        client_id,
                        error_response(
                            request_id,
                            &HostError::state("Claude TUI response missing snapshot."),
                        ),
                    );
                    return;
                };
                let merged = upsert_quota_snapshot(
                    self.cached_agent_quotas(environment_signature),
                    snapshot,
                );
                self.store_agent_quotas(environment_signature, merged.clone());
                self.client_write(
                    client_id,
                    ok_response(
                        request_id,
                        json!({
                            "snapshot": fresh.get("snapshot").cloned().unwrap_or(Value::Null),
                            "snapshots": merged.get("snapshots").cloned().unwrap_or(json!([])),
                            "environment": merged.get("environment").cloned().unwrap_or(json!({})),
                        }),
                    ),
                );
                self.broadcast_authenticated(event("agentQuotasChanged", json!({})));
            }
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
    }

    pub(super) fn handle_agent_quota_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    ) {
        if client_id == HOST_REFRESH_CLIENT_ID {
            self.handle_agent_quota_refresh_finished(request_id, result);
            return;
        }
        let next_refresh = self
            .agent_quota_cache
            .as_mut()
            .and_then(|cache| cache.refresh.client_fetch_finished(client_id, request_id));
        match result {
            Ok(fresh) => {
                let merged = self
                    .cached_agent_quotas(environment_signature)
                    .map(|cached| merge_quota_snapshots(cached, fresh.clone()))
                    .unwrap_or(fresh);
                self.store_agent_quotas(environment_signature, merged.clone());
                self.client_write(client_id, ok_response(request_id, merged));
                self.broadcast_authenticated(event("agentQuotasChanged", json!({})));
            }
            Err(error) => match self.cached_agent_quotas(environment_signature) {
                Some(cached) => self.client_write(
                    client_id,
                    ok_response(
                        request_id,
                        mark_quota_payload_stale(cached, &error.wire_message()),
                    ),
                ),
                None => self.client_write(client_id, error_response(request_id, &error)),
            },
        }
        if let Some(start) = next_refresh {
            self.spawn_agent_quota_refresh(start);
        }
    }

    pub(super) fn handle_agent_quota_codex_reset_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        environment_signature: u64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(mut payload) => {
                if let Some(snapshot) = payload.get("snapshot").cloned() {
                    let merged = upsert_quota_snapshot(
                        self.cached_agent_quotas(environment_signature),
                        snapshot,
                    );
                    self.store_agent_quotas(environment_signature, merged.clone());
                    if let Some(object) = payload.as_object_mut() {
                        object.insert(
                            "snapshots".to_string(),
                            merged
                                .get("snapshots")
                                .cloned()
                                .unwrap_or_else(|| json!([])),
                        );
                    }
                }
                self.client_write(client_id, ok_response(request_id, payload));
                self.broadcast_authenticated(event("agentQuotasChanged", json!({})));
            }
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
            }
        }
    }
}

impl ServerActor {
    /// The cached snapshot, when it was fetched with the same environment.
    fn cached_agent_quotas(&self, environment_signature: u64) -> Option<&Value> {
        self.agent_quota_cache
            .as_ref()
            .filter(|cache| cache.environment_signature == environment_signature)
            .map(|cache| &cache.snapshot)
    }

    /// Caches a fresh snapshot; usage refreshes in flight keep their state.
    fn store_agent_quotas(&mut self, environment_signature: u64, snapshot: Value) {
        let refresh = self
            .agent_quota_cache
            .take()
            .map(|cache| cache.refresh)
            .unwrap_or_default();
        self.agent_quota_cache = Some(AgentQuotaCache {
            fetched_at: Instant::now(),
            environment_signature,
            snapshot,
            refresh,
        });
    }
}

fn quota_environment_signature(value: &Value) -> u64 {
    let normalized = value
        .as_object()
        .map(|values| {
            let mut entries = values
                .iter()
                .filter_map(|(name, value)| value.as_str().map(|value| (name, value)))
                .collect::<Vec<_>>();
            entries.sort_unstable();
            entries
        })
        .unwrap_or_default();
    let mut hasher = DefaultHasher::new();
    normalized.hash(&mut hasher);
    hasher.finish()
}

fn merge_quota_snapshots(cached: &Value, mut fresh: Value) -> Value {
    let previous = cached
        .get("snapshots")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let Some(snapshots) = fresh.get_mut("snapshots").and_then(Value::as_array_mut) else {
        return fresh;
    };
    for snapshot in snapshots {
        if snapshot.get("status").and_then(Value::as_str) == Some("ok") {
            continue;
        }
        let provider = snapshot.get("provider");
        let account_id = snapshot.get("accountId");
        let Some(old) = previous.iter().find(|candidate| {
            candidate.get("provider") == provider && candidate.get("accountId") == account_id
        }) else {
            continue;
        };
        let error = snapshot.get("error").cloned().unwrap_or(Value::Null);
        *snapshot = old.clone();
        if let Some(object) = snapshot.as_object_mut() {
            object.insert("status".to_string(), json!("stale"));
            object.insert("error".to_string(), error);
        }
    }
    fresh
}

fn upsert_quota_snapshot(cached: Option<&Value>, snapshot: Value) -> Value {
    let mut base = cached.cloned().unwrap_or_else(|| {
        json!({
            "snapshots": [],
            "environment": {},
        })
    });
    let provider = snapshot.get("provider").cloned();
    let account_id = snapshot.get("accountId").cloned();
    if let Some(snapshots) = base.get_mut("snapshots").and_then(Value::as_array_mut) {
        if let Some(index) = snapshots.iter().position(|candidate| {
            candidate.get("provider") == provider.as_ref()
                && candidate.get("accountId") == account_id.as_ref()
        }) {
            snapshots[index] = snapshot;
        } else {
            snapshots.push(snapshot);
        }
    }
    base
}

fn mark_quota_payload_stale(cached: &Value, error: &str) -> Value {
    let mut value = cached.clone();
    if let Some(snapshots) = value.get_mut("snapshots").and_then(Value::as_array_mut) {
        for snapshot in snapshots {
            if let Some(object) = snapshot.as_object_mut() {
                object.insert("status".to_string(), json!("stale"));
                object.insert("error".to_string(), json!(error));
            }
        }
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failed_provider_keeps_previous_snapshot_as_stale() {
        let cached = json!({"snapshots": [{"provider":"codex","accountId":"default","status":"ok","windows":[1]}]});
        let fresh = json!({"snapshots": [{"provider":"codex","accountId":"default","status":"error","error":"offline","windows":[]}]});
        let merged = merge_quota_snapshots(&cached, fresh);
        assert_eq!(merged["snapshots"][0]["status"], "stale");
        assert_eq!(merged["snapshots"][0]["windows"], json!([1]));
        assert_eq!(merged["snapshots"][0]["error"], "offline");
    }

    #[test]
    fn upsert_replaces_matching_claude_account() {
        let cached = json!({
            "snapshots": [
                {"provider":"claude","accountId":"default","status":"unavailable"},
                {"provider":"codex","accountId":"default","status":"ok"}
            ],
            "environment": {"KIMI": true}
        });
        let merged = upsert_quota_snapshot(
            Some(&cached),
            json!({"provider":"claude","accountId":"default","status":"ok","windows":[1]}),
        );
        assert_eq!(merged["snapshots"].as_array().unwrap().len(), 2);
        assert_eq!(merged["snapshots"][0]["status"], "ok");
        assert_eq!(merged["snapshots"][0]["windows"], json!([1]));
        assert_eq!(merged["snapshots"][1]["provider"], "codex");
        assert_eq!(merged["environment"]["KIMI"], true);
    }
}
