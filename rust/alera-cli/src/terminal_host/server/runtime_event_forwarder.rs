//! Sends the runtime event journal to the Alera cloud for webhooks and MCP
//! Events, only while some subscription wants this runtime's events.
//!
//! Turning on MCP Control or signing in never starts a flow of events by
//! itself: with no subscription, the forwarder marks events as handled
//! without sending them, so a later subscription does not replay a backlog.
//! It only skips events that occurred before the last refresh that reported
//! no subscriptions; newer events wait for the next refresh (at most one
//! minute, or right away after `webhook.create`), so a subscription created
//! in between still receives them.
//!
//! A batch never blocks the journal: the cloud stores the valid events of a
//! batch and reports the others as `rejected`, and a batch that the cloud
//! refuses as a whole with a definitive client error is logged and skipped.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};

use alera_core::runtime::{RuntimeEvent, RuntimeStore};
use chrono::{DateTime, Utc};
use tokio::sync::Notify;
use tokio::task::JoinHandle;

use crate::terminal_host::alera_account::AleraAccountService;

/// The edge allows ten account mutations a minute per token, shared with
/// the runtime's other cloud calls, so batches go out at most every ten seconds.
const TICK: Duration = Duration::from_secs(10);
const SUBSCRIPTION_REFRESH: Duration = Duration::from_secs(60);
const BATCH: i64 = 100;
const BACKOFF_LIMIT: Duration = Duration::from_secs(300);

/// Bumped by [`request_subscription_refresh`]; a forwarder that sees a new
/// value refreshes its subscription count on its next tick.
static REFRESH_REQUESTS: AtomicU64 = AtomicU64::new(0);
static REFRESH_WAKE: LazyLock<Notify> = LazyLock::new(Notify::new);

/// Asks the forwarder to refresh the subscription count now, for example
/// after this runtime created a webhook.
pub(super) fn request_subscription_refresh() {
    REFRESH_REQUESTS.fetch_add(1, Ordering::SeqCst);
    REFRESH_WAKE.notify_waiters();
}

pub(super) fn spawn(store: RuntimeStore, service: Arc<AleraAccountService>) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut forwarder = Forwarder::new(store, service);
        loop {
            tokio::select! {
                () = tokio::time::sleep(forwarder.next_delay()) => {}
                () = REFRESH_WAKE.notified() => {}
            }
            forwarder.tick().await;
        }
    })
}

struct Forwarder {
    store: RuntimeStore,
    service: Arc<AleraAccountService>,
    active_subscriptions: usize,
    refreshed_at: Option<Instant>,
    /// When the cloud last reported no subscriptions; only events that
    /// occurred before it may be skipped.
    idle_since: Option<DateTime<Utc>>,
    refresh_requests: u64,
    failures: u32,
    pruned_at: Option<Instant>,
}

impl Forwarder {
    fn new(store: RuntimeStore, service: Arc<AleraAccountService>) -> Self {
        Self {
            store,
            service,
            active_subscriptions: 0,
            refreshed_at: None,
            idle_since: None,
            refresh_requests: REFRESH_REQUESTS.load(Ordering::SeqCst),
            failures: 0,
            pruned_at: None,
        }
    }

    fn next_delay(&self) -> Duration {
        let backoff = TICK.saturating_mul(2u32.saturating_pow(self.failures.min(6)));
        backoff.min(BACKOFF_LIMIT)
    }

    fn record_count(&mut self, count: usize) {
        self.active_subscriptions = count;
        self.refreshed_at = Some(Instant::now());
        self.idle_since = (count == 0).then(Utc::now);
    }

    async fn tick(&mut self) {
        self.prune_daily().await;
        if !matches!(self.service.local_account().await, Ok(Some(_))) {
            return;
        }
        let requests = REFRESH_REQUESTS.load(Ordering::SeqCst);
        if requests != self.refresh_requests {
            self.refresh_requests = requests;
            self.refreshed_at = None;
        }
        if self
            .refreshed_at
            .is_none_or(|refreshed| refreshed.elapsed() >= SUBSCRIPTION_REFRESH)
        {
            match self.service.event_subscription_count().await {
                Ok(count) => self.record_count(count),
                Err(error) => {
                    // An older cloud without the endpoint has no subscriptions.
                    tracing::debug!("event subscriptions unavailable: {error}");
                    self.failures = self.failures.saturating_add(1);
                    return;
                }
            }
        }
        let Ok(batch) = self.store.list_unforwarded_runtime_events(BATCH).await else {
            return;
        };
        let Some(last) = batch.last().map(|event| event.seq) else {
            return;
        };
        if self.active_subscriptions == 0 {
            let skippable = self
                .idle_since
                .and_then(|idle_since| skippable_through(&batch, idle_since));
            if let Some(seq) = skippable {
                let _ = self.store.mark_runtime_events_forwarded(seq).await;
            }
            return;
        }
        match self.service.forward_domain_events(&batch).await {
            Ok(Some(count)) => {
                self.record_count(count);
                self.failures = 0;
                let _ = self.store.mark_runtime_events_forwarded(last).await;
            }
            Ok(None) => {
                // Resending the same batch would be refused again and hold every
                // later event back, so it is skipped (the service logged why).
                self.failures = 0;
                let _ = self.store.mark_runtime_events_forwarded(last).await;
            }
            Err(error) => {
                tracing::warn!("could not forward runtime events: {error}");
                self.failures = self.failures.saturating_add(1);
            }
        }
    }

    async fn prune_daily(&mut self) {
        if self
            .pruned_at
            .is_some_and(|pruned| pruned.elapsed() < Duration::from_secs(24 * 60 * 60))
        {
            return;
        }
        self.pruned_at = Some(Instant::now());
        if let Err(error) = self.store.prune_runtime_events().await {
            tracing::warn!("could not prune runtime events: {error}");
        }
    }
}

/// The last sequence number of the leading events that occurred before
/// `idle_since`. Events with an unreadable timestamp count as old.
fn skippable_through(batch: &[RuntimeEvent], idle_since: DateTime<Utc>) -> Option<i64> {
    batch
        .iter()
        .take_while(|event| {
            DateTime::parse_from_rfc3339(&event.occurred_at)
                .map_or(true, |occurred| occurred.with_timezone(&Utc) < idle_since)
        })
        .last()
        .map(|event| event.seq)
}

#[cfg(test)]
mod tests {
    use alera_core::runtime::RuntimeEvent;
    use chrono::{DateTime, TimeDelta, Utc};
    use serde_json::json;

    use super::skippable_through;

    fn event(seq: i64, occurred_at: String) -> RuntimeEvent {
        RuntimeEvent {
            seq,
            event_id: format!("event-{seq}"),
            kind: "agent.status".to_owned(),
            workspace_id: None,
            project_id: None,
            data: json!({}),
            occurred_at,
        }
    }

    fn at(base: DateTime<Utc>, seconds: i64) -> String {
        (base + TimeDelta::seconds(seconds)).to_rfc3339()
    }

    #[test]
    fn runtime_event_skipping_stops_at_events_newer_than_the_idle_refresh() {
        let idle_since = Utc::now();
        let batch = [
            event(1, at(idle_since, -30)),
            event(2, "not a time".to_owned()),
            event(3, at(idle_since, -1)),
            event(4, at(idle_since, 5)),
            event(5, at(idle_since, -2)),
        ];
        assert_eq!(skippable_through(&batch, idle_since), Some(3));
        assert_eq!(skippable_through(&batch[3..], idle_since), None);
        assert_eq!(skippable_through(&[], idle_since), None);
    }
}
