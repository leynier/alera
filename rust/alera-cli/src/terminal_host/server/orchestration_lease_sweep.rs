//! Host-wide leases for dispatched workers.
//!
//! Runs from the agent presence sweep tick, so startup deadlines, activity
//! leases and stall decisions apply whether or not a coordinator loop is
//! running. A dispatch without a coordinator (an agent spawned with
//! `delegate`, or a manual `dispatch`) used to stay `awaiting_acceptance` or
//! `dispatched` forever.

use std::sync::atomic::{AtomicI64, Ordering};

use chrono::{DateTime, Utc};

use crate::terminal_host::protocol::{
    ORCHESTRATION_ACTIVITY_LEASE_MINUTES, ORCHESTRATION_STARTUP_DEADLINE_MS,
};
use crate::terminal_host::session::Session;

use super::ServerActor;

const LEASE_SWEEP_SECONDS: i64 = 30;

// Process-wide like the inbox expiry sweep: every actor in a test binary shares
// one cadence, and the sweep is idempotent, so a shared clock only skips
// redundant work.
static LAST_LEASE_SWEEP_UNIX: AtomicI64 = AtomicI64::new(0);

/// SQLite `datetime('now')` shape, so the store compares lexicographically.
fn sqlite_threshold(at: DateTime<Utc>) -> String {
    at.format("%Y-%m-%d %H:%M:%S").to_string()
}

pub(super) fn startup_deadline_threshold_iso(now: DateTime<Utc>) -> String {
    sqlite_threshold(now - chrono::Duration::milliseconds(ORCHESTRATION_STARTUP_DEADLINE_MS as i64))
}

pub(super) fn activity_lease_threshold_iso(now: DateTime<Utc>) -> String {
    sqlite_threshold(now - chrono::Duration::minutes(ORCHESTRATION_ACTIVITY_LEASE_MINUTES))
}

impl ServerActor {
    pub(super) async fn sweep_orchestration_leases_if_due(&mut self) {
        let now = Utc::now().timestamp();
        if now - LAST_LEASE_SWEEP_UNIX.load(Ordering::Relaxed) < LEASE_SWEEP_SECONDS {
            return;
        }
        LAST_LEASE_SWEEP_UNIX.store(now, Ordering::Relaxed);
        self.sweep_orchestration_leases(Utc::now()).await;
    }

    /// Fails startups that can no longer succeed, stalls workers whose lease
    /// expired, and acts on stall gates a person already resolved.
    pub(super) async fn sweep_orchestration_leases(&mut self, now: DateTime<Utc>) {
        if let Err(error) = self.fail_stuck_orchestration_startups(now).await {
            tracing::warn!("[orchestration] startup deadline sweep failed: {error}");
        }
        if let Err(error) = self.stall_idle_orchestration_dispatches(now).await {
            tracing::warn!("[orchestration] activity lease sweep failed: {error}");
        }
        if let Err(error) = self.settle_loopless_shared_runs().await {
            tracing::warn!("[orchestration] shared run settlement failed: {error}");
        }
        if let Err(error) = self.coordinator_process_stall_decisions().await {
            tracing::warn!("[orchestration] stall decisions failed: {error}");
        }
    }

    /// A dispatch past the startup deadline fails only when its terminal is
    /// gone or no agent was ever detected in it. An agent that is running but
    /// has not run a worker command yet is left to the activity lease, which
    /// can tell a slow start from a dead one.
    async fn fail_stuck_orchestration_startups(
        &mut self,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        let threshold = startup_deadline_threshold_iso(now);
        let pending = self
            .runtime_store
            .unaccepted_orchestration_dispatches(&threshold)
            .await?;
        for dispatch in pending {
            let handle = dispatch.assignee_handle.clone().unwrap_or_default();
            let running = self.sessions.get(&handle).is_some_and(Session::running);
            let detected = self.agent_presence.get(&handle).is_some();
            if running && detected {
                continue;
            }
            let reason = if running {
                "no agent started in the worker terminal before the startup deadline"
            } else {
                "the worker terminal stopped before the agent ran a worker command"
            };
            self.runtime_store
                .fail_orchestration_startup(&dispatch.id, reason)
                .await?;
            if !handle.is_empty() {
                self.remove_dispatch_context(&handle);
                self.cleanup_failed_owned_spawn(&handle).await;
            }
            tracing::info!(
                dispatch_id = %dispatch.id,
                "[orchestration] dispatch startup failed: {reason}"
            );
        }
        Ok(())
    }

    /// A worker with no activity past the lease is stalled. It is never
    /// redispatched on its own, because it may still be alive.
    async fn stall_idle_orchestration_dispatches(
        &mut self,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        let threshold = activity_lease_threshold_iso(now);
        let stalled = self
            .runtime_store
            .stall_expired_orchestration_dispatches(&threshold)
            .await?;
        let changed = !stalled.is_empty();
        for dispatch in stalled {
            self.coordinator_log(&format!(
                "dispatch {} on {} exceeded its activity lease and is stalled since {}",
                dispatch.id,
                dispatch.assignee_handle.as_deref().unwrap_or("<unknown>"),
                dispatch
                    .last_activity_at
                    .as_deref()
                    .or(dispatch.dispatched_at.as_deref())
                    .unwrap_or("dispatch")
            ));
            self.apply_stall_policy(&dispatch).await;
        }
        if changed {
            self.broadcast_orchestration_board_change().await;
        }
        Ok(())
    }
}

impl ServerActor {
    /// A shared run without a coordinator loop (delegated work, or a loop
    /// lost to a host restart) finishes once every task finished.
    async fn settle_loopless_shared_runs(&mut self) -> anyhow::Result<()> {
        let runs = self.runtime_store.running_shared_runs().await?;
        let mut changed = false;
        for run in runs {
            if self.coordinators.contains_key(&run.id) {
                continue;
            }
            let tasks = self
                .runtime_store
                .list_scoped_orchestration_tasks(None, Some(&run.id), Some(&run.workspace_id))
                .await?;
            use alera_core::runtime::OrchestrationTaskStatus as Status;
            if tasks.is_empty()
                || !tasks.iter().all(|task| {
                    matches!(
                        task.status,
                        Status::Completed | Status::Failed | Status::Cancelled
                    )
                })
            {
                continue;
            }
            let failed = tasks.iter().any(|task| task.status == Status::Failed);
            self.runtime_store
                .finish_orchestration_coordinator_run(
                    &run.id,
                    if failed {
                        alera_core::runtime::OrchestrationCoordinatorStatus::Failed
                    } else {
                        alera_core::runtime::OrchestrationCoordinatorStatus::Completed
                    },
                )
                .await?;
            changed = true;
        }
        if changed {
            self.broadcast_orchestration_board_change().await;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thresholds_match_the_sqlite_timestamp_shape() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-07-05T12:30:00Z")
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(startup_deadline_threshold_iso(now), "2026-07-05 12:27:00");
        assert_eq!(activity_lease_threshold_iso(now), "2026-07-05 12:20:00");
    }
}
