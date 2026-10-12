//! The registry's state for one remote host, and the status it publishes.
//!
//! Everything about a host lives behind one plain mutex that is never held
//! across an await, so the link, the attempt in flight, the retry timer and
//! the supervisor's flags always change together.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::Value;
use tokio::sync::watch;
use tokio::task::JoinHandle;

use super::host_error::HostResult;
use super::host_link::{HostLink, HostLinkState};
use super::host_link_backoff::Backoff;
use super::host_link_failure::AttachFailureKind;

pub(crate) type AttemptOutcome = Option<HostResult<Arc<HostLink>>>;

#[derive(Default)]
pub(crate) struct HostSlot {
    state: Mutex<SlotState>,
}

impl HostSlot {
    pub(crate) fn lock(&self) -> MutexGuard<'_, SlotState> {
        self.state.lock().expect("host link slot poisoned")
    }
}

/// A connect running in its own task. Callers wait on `outcome`, so dropping
/// a caller never cancels the attempt or leaves the host `connecting`.
pub(crate) struct ConnectAttempt {
    pub(crate) id: u64,
    pub(crate) outcome: watch::Receiver<AttemptOutcome>,
    pub(crate) task: JoinHandle<()>,
}

pub(crate) struct RetryPlan {
    pub(crate) attempt: u32,
    pub(crate) next_retry_at: DateTime<Utc>,
    pub(crate) timer: JoinHandle<()>,
}

#[derive(Default)]
pub(crate) struct SlotState {
    /// Bumped by every deliberate change of course (disconnect, restart,
    /// forget). An attempt only installs its link when the generation it
    /// started under is still current.
    pub(crate) generation: u64,
    pub(crate) link: Option<Arc<HostLink>>,
    pub(crate) attempt: Option<ConnectAttempt>,
    pub(crate) next_attempt_id: u64,
    pub(crate) last_error: Option<String>,
    pub(crate) failure_kind: Option<AttachFailureKind>,
    /// The host has an active workspace and a finished install.
    pub(crate) desired: bool,
    /// The user asked for this link (Connect).
    pub(crate) explicit: bool,
    /// The user disconnected it; nothing reconnects it on its own.
    pub(crate) paused: bool,
    /// Hub sessions run on the host, as of the last supervisor sweep.
    pub(crate) busy: bool,
    /// A runtime restart is under way, so the next close is expected.
    pub(crate) restarting: bool,
    pub(crate) backoff: Backoff,
    pub(crate) retry: Option<RetryPlan>,
    pub(crate) last_used: Option<Instant>,
    pub(crate) satellite_version: Option<String>,
    /// Registration hash and satellite record per mirrored workspace. Only
    /// valid for the current link; replaced with it.
    pub(crate) mirrored: HashMap<String, (u64, Value)>,
}

impl SlotState {
    pub(crate) fn live_link(&self) -> Option<Arc<HostLink>> {
        self.link.as_ref().filter(|link| !link.is_closed()).cloned()
    }

    pub(crate) fn wants_link(&self) -> bool {
        (self.desired || self.explicit) && !self.paused
    }

    pub(crate) fn touch(&mut self) {
        self.last_used = Some(Instant::now());
    }

    pub(crate) fn cancel_retry(&mut self) -> bool {
        match self.retry.take() {
            Some(retry) => {
                retry.timer.abort();
                true
            }
            None => false,
        }
    }

    /// Changes course: the attempt in flight and the pending retry are
    /// abandoned, and a late result of either is ignored.
    pub(crate) fn bump_generation(&mut self) {
        self.generation += 1;
        if let Some(attempt) = self.attempt.take() {
            attempt.task.abort();
        }
        self.cancel_retry();
    }

    pub(crate) fn take_link(&mut self) -> Option<Arc<HostLink>> {
        self.mirrored.clear();
        self.link.take()
    }

    pub(crate) fn link_state(&self) -> HostLinkState {
        if let Some(link) = self.live_link() {
            return HostLinkState::Attached {
                attachment: link.attachment().clone(),
            };
        }
        if self.attempt.is_some() {
            return HostLinkState::Connecting;
        }
        match &self.last_error {
            Some(error) => HostLinkState::Failed {
                error: error.clone(),
            },
            None => HostLinkState::Disconnected,
        }
    }

    /// When the idle sweep will close this link if nothing uses it first.
    pub(crate) fn idle_close_at(&self, idle_close: Duration) -> Option<DateTime<Utc>> {
        if self.wants_link() || self.busy || self.live_link().is_none() {
            return None;
        }
        let remaining = self
            .last_used
            .map(|used| idle_close.saturating_sub(used.elapsed()))
            .unwrap_or_default();
        chrono::Duration::from_std(remaining)
            .ok()
            .map(|remaining| Utc::now() + remaining)
    }

    pub(crate) fn status(&self, idle_close: Duration) -> HostLinkStatus {
        HostLinkStatus {
            state: self.link_state(),
            generation: self.generation,
            desired: self.desired || self.explicit,
            paused: self.paused,
            explicit: self.explicit,
            retry: self.retry.as_ref().map(|retry| RetryStatus {
                attempt: retry.attempt,
                next_retry_at: retry.next_retry_at,
            }),
            idle_close_at: self.idle_close_at(idle_close),
            failure_kind: if self.live_link().is_some() {
                None
            } else {
                self.failure_kind
            },
            satellite_version: self.satellite_version.clone(),
            hub_version: super::runtime_build_info::version().to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RetryStatus {
    pub(crate) attempt: u32,
    pub(crate) next_retry_at: DateTime<Utc>,
}

/// `hostLink.status` and `hostLinkChanged` per host. `state` keeps its four
/// values; every other field is additive.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct HostLinkStatus {
    #[serde(flatten)]
    pub(crate) state: HostLinkState,
    pub(crate) generation: u64,
    pub(crate) desired: bool,
    pub(crate) paused: bool,
    pub(crate) explicit: bool,
    pub(crate) retry: Option<RetryStatus>,
    pub(crate) idle_close_at: Option<DateTime<Utc>>,
    pub(crate) failure_kind: Option<AttachFailureKind>,
    pub(crate) satellite_version: Option<String>,
    pub(crate) hub_version: String,
}
