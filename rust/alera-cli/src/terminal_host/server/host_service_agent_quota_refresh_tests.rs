use std::collections::HashMap;
use std::time::Instant;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::host_error::HostError;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::server::agent_chat_runtime::ChatRuntimeEvent;
use crate::terminal_host::server::ServerActor;

use super::refresh::{RefreshStart, UsageRefresh, HOST_REFRESH_CLIENT_ID};
use super::AgentQuotaCache;

const SIGNATURE: u64 = 7;

fn snapshot(provider: &str, used: u64) -> Value {
    json!({
        "provider": provider, "accountId": "default", "status": "ok",
        "windows": [{"label": "Session", "usedPercent": used}],
    })
}

fn turns(turns: &[(&str, &str, Option<&str>)]) -> ChatRuntimeEvent {
    let turns: Vec<Value> = turns
        .iter()
        .enumerate()
        .map(|(index, (provider, status, class))| {
            json!({
                "turnId": format!("turn-{index}"), "status": status,
                "provider": provider, "failureClass": class,
            })
        })
        .collect();
    ChatRuntimeEvent::Changed {
        chat_id: "chat".into(),
        workspace_id: "workspace".into(),
        cursor: 1,
        delta: json!({ "turns": turns }),
    }
}

fn start(generation: i64, providers: &[&str]) -> RefreshStart {
    RefreshStart {
        generation,
        providers: providers
            .iter()
            .map(|provider| provider.to_string())
            .collect(),
    }
}

async fn actor_with_cache(
    dir: &tempfile::TempDir,
) -> (ServerActor, UnboundedReceiver<ClientFrame>, Instant) {
    let (handle, events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let fetched_at = Instant::now();
    actor.agent_quota_cache = Some(AgentQuotaCache {
        fetched_at,
        environment_signature: SIGNATURE,
        snapshot: json!({
            "snapshots": [snapshot("claude", 5), snapshot("codex", 10), snapshot("cursor", 20)],
            "environment": {},
        }),
        refresh: UsageRefresh::default(),
    });
    (actor, events, fetched_at)
}

fn frames(events: &mut UnboundedReceiver<ClientFrame>) -> Vec<Value> {
    let mut frames = Vec::new();
    while let Ok(frame) = events.try_recv() {
        match frame {
            ClientFrame::Json(value) => frames.push(value),
            ClientFrame::OrderedControl { frame, .. } => {
                if let ClientFrame::Json(value) = *frame {
                    frames.push(value);
                }
            }
            _ => {}
        }
    }
    frames
}

fn quota_events(events: &mut UnboundedReceiver<ClientFrame>) -> usize {
    frames(events)
        .iter()
        .filter(|frame| frame["event"] == "agentQuotasChanged")
        .count()
}

fn cached_usage(actor: &ServerActor, provider: &str) -> Value {
    let cache = actor.agent_quota_cache.as_ref().unwrap();
    cache.snapshot["snapshots"]
        .as_array()
        .unwrap()
        .iter()
        .find(|snapshot| snapshot["provider"] == provider)
        .map(|snapshot| snapshot["windows"][0]["usedPercent"].clone())
        .unwrap()
}

#[tokio::test]
async fn a_usage_limited_turn_refreshes_its_provider_once_behind_the_running_refresh() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, mut events, fetched_at) = actor_with_cache(&dir).await;

    let limited = turns(&[
        ("cursor", "failed", Some("usage_limit")),
        ("codex", "failed", Some("auth")),
        ("claudeAgent", "completed", None),
        ("pi", "failed", Some("usage_limit")),
    ]);
    assert_eq!(
        actor.queue_agent_quota_refreshes(&limited),
        vec![start(1, &["cursor"])]
    );
    // A burst while the refresh runs queues one refresh behind it.
    for _ in 0..3 {
        let burst = turns(&[
            ("cursor", "failed", Some("usage_limit")),
            ("claudeAgent", "failed", Some("usage_limit")),
        ]);
        assert!(actor.queue_agent_quota_refreshes(&burst).is_empty());
    }

    let next = actor.apply_agent_quota_refresh(
        1,
        Ok(json!({"snapshots": [snapshot("cursor", 100)], "environment": {}})),
    );
    assert_eq!(next, Some(start(2, &["claude", "cursor"])));
    assert_eq!(cached_usage(&actor, "cursor"), 100);
    assert_eq!(cached_usage(&actor, "codex"), 10);
    let cache = actor.agent_quota_cache.as_ref().unwrap();
    assert_eq!(cache.fetched_at, fetched_at);
    assert_eq!(quota_events(&mut events), 1);

    let failed = actor.apply_agent_quota_refresh(2, Err(HostError::state("offline")));
    assert_eq!(failed, None);
    assert_eq!(quota_events(&mut events), 0);
}

#[tokio::test]
async fn a_failed_provider_fetch_keeps_the_cached_window_as_stale() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, mut events, _) = actor_with_cache(&dir).await;
    actor.queue_agent_quota_refreshes(&turns(&[("cursor", "failed", Some("usage_limit"))]));

    actor.handle_agent_quota_finished(
        HOST_REFRESH_CLIENT_ID,
        1,
        SIGNATURE,
        Ok(json!({"snapshots": [{
            "provider": "cursor", "accountId": "default", "status": "error",
            "error": "offline", "windows": [],
        }]})),
    );

    let cache = actor.agent_quota_cache.as_ref().unwrap();
    let cursor = &cache.snapshot["snapshots"][2];
    assert_eq!(cursor["status"], "stale");
    assert_eq!(cursor["error"], "offline");
    assert_eq!(cursor["windows"][0]["usedPercent"], 20);
    // The host's own refresh answers no client, only broadcasts.
    assert_eq!(
        frames(&mut events),
        vec![json!({"event": "agentQuotasChanged", "payload": {}})]
    );
}

#[tokio::test]
async fn no_refresh_without_a_cached_snapshot_of_the_provider() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, _events, _) = actor_with_cache(&dir).await;
    let grok = turns(&[("grok", "failed", Some("usage_limit"))]);
    assert!(actor.queue_agent_quota_refreshes(&grok).is_empty());

    actor.agent_quota_cache = None;
    let cursor = turns(&[("cursor", "failed", Some("usage_limit"))]);
    assert!(actor.queue_agent_quota_refreshes(&cursor).is_empty());
}

#[tokio::test]
async fn a_client_fetch_keeps_the_running_refresh() {
    let dir = tempfile::tempdir().unwrap();
    let (mut actor, mut events, _) = actor_with_cache(&dir).await;
    let limited = turns(&[("cursor", "failed", Some("usage_limit"))]);
    assert_eq!(
        actor.queue_agent_quota_refreshes(&limited),
        vec![start(1, &["cursor"])]
    );

    actor.handle_agent_quota_finished(
        1,
        9,
        SIGNATURE,
        Ok(json!({"snapshots": [snapshot("cursor", 30)], "environment": {}})),
    );
    assert_eq!(quota_events(&mut events), 1);
    assert!(actor.queue_agent_quota_refreshes(&limited).is_empty());
    assert_eq!(
        actor.apply_agent_quota_refresh(1, Ok(json!({"snapshots": []}))),
        Some(start(2, &["cursor"]))
    );
}

#[test]
fn a_refresh_waits_for_client_fetches_that_may_predate_the_limit() {
    let mut refresh = UsageRefresh::default();
    refresh.client_fetch_started(4, 1);
    refresh.client_fetch_started(5, 1);
    assert_eq!(refresh.request("cursor"), None);
    assert_eq!(refresh.client_fetch_finished(4, 1), None);
    assert_eq!(
        refresh.client_fetch_finished(5, 1),
        Some(start(1, &["cursor"]))
    );
    // A stale generation does not release the running refresh.
    assert_eq!(refresh.request("codex"), None);
    assert_eq!(refresh.finished(0), None);
    assert_eq!(refresh.finished(1), Some(start(2, &["codex"])));
    assert_eq!(refresh.finished(2), None);
}
