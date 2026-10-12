//! One connect to a host, run in its own task.
//!
//! The attempt publishes its result through a watch channel on the slot, so
//! any number of callers can wait on it and any of them can give up without
//! cancelling it. It installs its link only when the slot's generation is
//! still the one it started under: a Disconnect during a slow handshake wins,
//! and the late link is closed instead of reported as attached.

use std::sync::Arc;

use chrono::Utc;
use tokio::sync::watch;

use super::host_error::{HostError, HostResult};
use super::host_link::HostLink;
use super::host_link_backoff::RESTART_RETRY_DELAY;
use super::host_link_failure::{AttachError, AttachFailureKind};
use super::host_link_registry::HostLinkRegistry;
use super::host_link_slot::{AttemptOutcome, ConnectAttempt, HostSlot, RetryPlan, SlotState};

impl HostLinkRegistry {
    /// Spawns a connect for `host_id`. The caller holds the slot lock and
    /// has checked that no attempt is running.
    pub(super) fn start_attempt(
        &self,
        host_id: &str,
        slot: &Arc<HostSlot>,
        state: &mut SlotState,
    ) -> watch::Receiver<AttemptOutcome> {
        state.next_attempt_id += 1;
        let id = state.next_attempt_id;
        let generation = state.generation;
        let (sender, outcome) = watch::channel(None);
        let registry = self.clone();
        let slot = slot.clone();
        let host = host_id.to_string();
        let task = tokio::spawn(async move {
            let result = registry.connect(&host).await;
            registry.finish_attempt(&host, &slot, id, generation, result, sender);
        });
        state.attempt = Some(ConnectAttempt {
            id,
            outcome: outcome.clone(),
            task,
        });
        outcome
    }

    pub(super) async fn await_attempt(
        host_id: &str,
        mut outcome: watch::Receiver<AttemptOutcome>,
    ) -> HostResult<Arc<HostLink>> {
        match outcome.wait_for(Option::is_some).await {
            Ok(value) => value
                .clone()
                .unwrap_or_else(|| Err(Self::cancelled(host_id))),
            Err(_) => Err(Self::cancelled(host_id)),
        }
    }

    async fn connect(&self, host_id: &str) -> Result<Arc<HostLink>, AttachError> {
        let target = crate::ssh_remote::require_bootstrapped_ssh_target(&self.store, host_id)
            .await
            .map_err(|error| {
                Box::new((
                    HostError::from_anyhow(&error),
                    AttachFailureKind::Configuration,
                ))
            })?;
        HostLink::connect_classified(&target, self.inbox.clone(), self.launcher.as_ref()).await
    }

    fn finish_attempt(
        &self,
        host_id: &str,
        slot: &Arc<HostSlot>,
        id: u64,
        generation: u64,
        result: Result<Arc<HostLink>, AttachError>,
        sender: watch::Sender<AttemptOutcome>,
    ) {
        let mut stale = None;
        let mut attached = false;
        let outcome = {
            let mut state = slot.lock();
            let current = state
                .attempt
                .as_ref()
                .is_some_and(|attempt| attempt.id == id);
            if current {
                state.attempt = None;
            }
            if !current || state.generation != generation {
                stale = result.ok();
                Err(Self::cancelled(host_id))
            } else {
                match result {
                    Ok(link) => {
                        state.take_link();
                        state.link = Some(link.clone());
                        state.last_error = None;
                        state.failure_kind = None;
                        state.backoff.reset();
                        state.cancel_retry();
                        state.satellite_version = link.attachment().host_version.clone();
                        state.touch();
                        self.watch_close(host_id, &link);
                        attached = true;
                        Ok(link)
                    }
                    Err(failure) => {
                        let (error, kind) = *failure;
                        state.last_error = Some(error.wire_message());
                        state.failure_kind = Some(kind);
                        if state.wants_link() && kind.retries() {
                            self.schedule_retry(host_id, &mut state, false);
                        } else {
                            state.cancel_retry();
                        }
                        Err(error)
                    }
                }
            }
        };
        if let Some(link) = stale {
            tokio::spawn(async move { link.close().await });
        }
        sender.send_replace(Some(outcome));
        self.publish(host_id, attached);
    }

    /// Reports the close of `link` to the registry even when no actor is
    /// listening for [`super::server::ServerCommand::HostLinkClosed`].
    fn watch_close(&self, host_id: &str, link: &Arc<HostLink>) {
        let registry = self.clone();
        let host = host_id.to_string();
        let link = link.clone();
        tokio::spawn(async move {
            link.closed().await;
            let reason = link
                .close_reason()
                .unwrap_or_else(|| format!("The link to host {host} was closed."));
            registry.note_closed(&host, &reason);
        });
    }

    /// Schedules the next connect. An `expected` close (runtime restart)
    /// comes back quickly and does not count as a failure.
    pub(super) fn schedule_retry(&self, host_id: &str, state: &mut SlotState, expected: bool) {
        let (attempt, delay) = if expected {
            (state.backoff.attempt(), RESTART_RETRY_DELAY)
        } else {
            let attempt = state.backoff.advance();
            (attempt, self.policy.retry.delay(attempt))
        };
        let generation = state.generation;
        let registry = self.clone();
        let host = host_id.to_string();
        let timer = tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            registry.retry_due(&host, generation);
        });
        let next_retry_at = Utc::now()
            + chrono::Duration::from_std(delay).unwrap_or_else(|_| chrono::Duration::zero());
        if let Some(previous) = state.retry.replace(RetryPlan {
            attempt,
            next_retry_at,
            timer,
        }) {
            previous.timer.abort();
        }
    }

    fn retry_due(&self, host_id: &str, generation: u64) {
        let Some(slot) = self.existing_slot(host_id) else {
            return;
        };
        {
            let mut state = slot.lock();
            if state.generation != generation
                || state.live_link().is_some()
                || state.attempt.is_some()
            {
                return;
            }
            if !state.wants_link() {
                state.retry = None;
            } else {
                // The plan stays visible while the attempt runs, so the app
                // can show which retry this is.
                self.start_attempt(host_id, &slot, &mut state);
            }
        }
        self.publish(host_id, false);
    }
}
