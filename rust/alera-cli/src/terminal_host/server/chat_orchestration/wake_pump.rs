//! Delivers wakes a parent is owed once it goes idle.
//!
//! A task's own settle tries to wake its parent right away, which fails
//! while the parent is busy. Such a parent joins the owed set, and the pump
//! retries every owed parent when a chat's session, requests or native
//! operation change, when a chat list changes, when the subscription lags,
//! when something nudges it, and on a slow sweep. Startup seeds the set from
//! the store, so cohorts left by a restart are delivered too.

use std::collections::HashSet;
use std::sync::Mutex;
use std::time::Duration;

use chrono::{DateTime, Utc};
use serde_json::Value;
use tokio::sync::{broadcast, mpsc};

use crate::terminal_host::server::agent_chat_runtime::ChatRuntimeEvent;

use super::service::ChatOrchestrationService;
use super::wakes::deliver_next_wake;

/// The backstop for remote parents and satellites that do not report every
/// change.
pub(super) const WAKE_SWEEP: Duration = Duration::from_secs(30);
/// How long a parent whose turn was just interrupted is left alone: a
/// person's stop drops its cohorts right after the interrupt, so a wake must
/// not race it.
pub(super) const STOP_GRACE: Duration = Duration::from_secs(2);
const RUNTIME_RESTARTED: &str = "runtimeRestarted";

pub(crate) struct WakePump {
    owed: Mutex<HashSet<String>>,
    nudge: mpsc::UnboundedSender<()>,
    nudges: Mutex<Option<mpsc::UnboundedReceiver<()>>>,
}

impl Default for WakePump {
    fn default() -> Self {
        let (nudge, nudges) = mpsc::unbounded_channel();
        Self {
            owed: Mutex::default(),
            nudge,
            nudges: Mutex::new(Some(nudges)),
        }
    }
}

impl WakePump {
    /// Remembers that `parent` is owed a wake and asks the pump to try it.
    pub(super) fn owe(&self, parent: &str) {
        self.owed
            .lock()
            .expect("wake pump lock")
            .insert(parent.to_owned());
        let _ = self.nudge.send(());
    }

    fn owed(&self) -> Vec<String> {
        let mut owed: Vec<String> = self
            .owed
            .lock()
            .expect("wake pump lock")
            .iter()
            .cloned()
            .collect();
        owed.sort();
        owed
    }

    fn settle(&self, parent: &str) {
        self.owed.lock().expect("wake pump lock").remove(parent);
    }

    pub(super) fn is_owed(&self, parent: &str) -> bool {
        self.owed.lock().expect("wake pump lock").contains(parent)
    }
}

impl ChatOrchestrationService {
    /// Starts the pump once, after startup recovery. Shutdown aborts it with
    /// the other orchestration jobs.
    pub(crate) fn start_wake_pump(&self) {
        self.start_wake_pump_every(WAKE_SWEEP);
    }

    pub(crate) fn start_wake_pump_every(&self, sweep: Duration) {
        let Some(nudges) = self.wake_pump.nudges.lock().expect("wake pump lock").take() else {
            return;
        };
        // Subscribe before seeding, so no change between the two is lost.
        let events = self.runtime.subscribe();
        let service = self.clone();
        let _ = self.jobs.spawn(async move {
            service.run_wake_pump(events, nudges, sweep).await;
        });
    }

    async fn run_wake_pump(
        &self,
        mut events: broadcast::Receiver<ChatRuntimeEvent>,
        mut nudges: mpsc::UnboundedReceiver<()>,
        sweep: Duration,
    ) {
        let mut sweep = tokio::time::interval_at(tokio::time::Instant::now() + sweep, sweep);
        sweep.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        self.seed_owed_wakes().await;
        self.pump_owed_wakes().await;
        loop {
            tokio::select! {
                event = events.recv() => match event {
                    Ok(ChatRuntimeEvent::Changed { chat_id, delta, .. }) => {
                        if self.wake_pump.is_owed(&chat_id) && wake_relevant(&delta) && !busy(&delta) {
                            self.pump_parent_wake(&chat_id).await;
                        }
                    }
                    Ok(ChatRuntimeEvent::ChatsChanged { .. })
                    | Err(broadcast::error::RecvError::Lagged(_)) => self.pump_owed_wakes().await,
                    Ok(_) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                },
                Some(()) = nudges.recv() => {
                    while nudges.try_recv().is_ok() {}
                    self.pump_owed_wakes().await;
                }
                _ = sweep.tick() => {
                    self.seed_owed_wakes().await;
                    self.pump_owed_wakes().await;
                }
            }
        }
    }

    async fn seed_owed_wakes(&self) {
        match self
            .store
            .list_chat_orchestration_wakes_awaiting_delivery(None)
            .await
        {
            Ok(wakes) => {
                let mut owed = self.wake_pump.owed.lock().expect("wake pump lock");
                owed.extend(wakes.into_iter().map(|wake| wake.parent_chat_id));
            }
            Err(error) => tracing::warn!("owed chat wakes unavailable: {error}"),
        }
    }

    async fn pump_owed_wakes(&self) {
        for parent in self.wake_pump.owed() {
            if self.jobs.is_closed() {
                return;
            }
            self.pump_parent_wake(&parent).await;
        }
    }

    async fn pump_parent_wake(&self, parent: &str) {
        match deliver_next_wake(&self.store, self.runtime.as_ref(), parent, &self.events).await {
            Ok(delivered) => {
                let awaiting = self
                    .store
                    .list_chat_orchestration_wakes_awaiting_delivery(Some(parent))
                    .await;
                if awaiting.is_ok_and(|wakes| wakes.is_empty()) {
                    self.wake_pump.settle(parent);
                } else if !delivered {
                    self.recheck_after_stop_grace(parent).await;
                }
            }
            Err(_) if self.parent_gone(parent).await => self.wake_pump.settle(parent),
            Err(_) => {}
        }
    }

    /// A parent held by the stop grace changes nothing when the grace ends,
    /// so the pump tries it again then.
    async fn recheck_after_stop_grace(&self, parent: &str) {
        let Ok(snapshot) = self.runtime.snapshot(parent).await else {
            return;
        };
        let Some(wait) = stop_grace_left(&snapshot, Utc::now()) else {
            return;
        };
        let service = self.clone();
        let _ = self.jobs.spawn(async move {
            tokio::time::sleep(wait).await;
            let _ = service.wake_pump.nudge.send(());
        });
    }

    /// A local parent that was deleted or archived never takes a wake. A
    /// parent this store does not know may be remote and only unreachable
    /// for now, so the sweep keeps trying it.
    async fn parent_gone(&self, parent: &str) -> bool {
        self.store
            .agent_chat(parent)
            .await
            .ok()
            .flatten()
            .is_some_and(|record| record.archived)
    }
}

/// Whether the parent's newest turn was interrupted within the grace, by
/// anything but a runtime restart.
pub(super) fn stop_grace_left(snapshot: &Value, now: DateTime<Utc>) -> Option<Duration> {
    let turn = snapshot.get("turns")?.as_array()?.last()?;
    if turn.get("status")?.as_str()? != "interrupted"
        || turn.get("reason").and_then(Value::as_str) == Some(RUNTIME_RESTARTED)
    {
        return None;
    }
    let ended = DateTime::parse_from_rfc3339(turn.get("completedAt")?.as_str()?).ok()?;
    let elapsed = now
        .signed_duration_since(ended.with_timezone(&Utc))
        .to_std()
        .unwrap_or_default();
    STOP_GRACE
        .checked_sub(elapsed)
        .filter(|left| !left.is_zero())
}

fn wake_relevant(delta: &Value) -> bool {
    ["session", "requests", "pendingNativeOperation"]
        .iter()
        .any(|key| delta.get(key).is_some())
}

/// A change whose session still shows the parent busy cannot deliver.
fn busy(delta: &Value) -> bool {
    delta
        .get("session")
        .and_then(|session| session.get("activeTurnId"))
        .is_some_and(|turn| !turn.is_null())
}
