//! Sends the runtime event journal to the Alera cloud for webhooks and MCP
//! Events, only while some subscription wants this runtime's events.
//!
//! Turning on MCP Control or signing in never starts a flow of events by
//! itself: with no subscription, the forwarder marks events as handled
//! without sending them, so a later subscription does not replay a backlog.

use std::sync::Arc;
use std::time::{Duration, Instant};

use alera_core::runtime::RuntimeStore;
use tokio::task::JoinHandle;

use crate::terminal_host::alera_account::AleraAccountService;

/// The edge allows ten account mutations a minute per token, shared with
/// the runtime's other cloud calls, so batches go out at most every ten seconds.
const TICK: Duration = Duration::from_secs(10);
const SUBSCRIPTION_REFRESH: Duration = Duration::from_secs(60);
const BATCH: i64 = 100;
const BACKOFF_LIMIT: Duration = Duration::from_secs(300);

pub(super) fn spawn(store: RuntimeStore, service: Arc<AleraAccountService>) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut forwarder = Forwarder::new(store, service);
        loop {
            tokio::time::sleep(forwarder.next_delay()).await;
            forwarder.tick().await;
        }
    })
}

struct Forwarder {
    store: RuntimeStore,
    service: Arc<AleraAccountService>,
    active_subscriptions: usize,
    refreshed_at: Option<Instant>,
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
            failures: 0,
            pruned_at: None,
        }
    }

    fn next_delay(&self) -> Duration {
        let backoff = TICK.saturating_mul(2u32.saturating_pow(self.failures.min(6)));
        backoff.min(BACKOFF_LIMIT)
    }

    async fn tick(&mut self) {
        self.prune_daily().await;
        if !matches!(self.service.local_account().await, Ok(Some(_))) {
            return;
        }
        if self
            .refreshed_at
            .is_none_or(|refreshed| refreshed.elapsed() >= SUBSCRIPTION_REFRESH)
        {
            match self.service.event_subscription_count().await {
                Ok(count) => {
                    self.active_subscriptions = count;
                    self.refreshed_at = Some(Instant::now());
                }
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
            let _ = self.store.mark_runtime_events_forwarded(last).await;
            return;
        }
        match self.service.forward_domain_events(&batch).await {
            Ok(count) => {
                self.active_subscriptions = count;
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
