use std::time::Duration;

use tokio::sync::mpsc::UnboundedSender;
use tokio::task::JoinHandle;

/// Default coordinator cadence, mirroring Orca.
pub const COORDINATOR_DEFAULT_POLL_MS: u64 = 2_000;
pub const COORDINATOR_MAX_CONCURRENT_DEFAULT: usize = 4;
/// A dispatch with no heartbeat for 2x the 5-minute heartbeat cadence is
/// considered hung. Warn-only: killing a slow-but-correct worker costs more
/// than a hung worker holding a slot.
pub const COORDINATOR_HUNG_THRESHOLD_MINUTES: i64 = 10;
pub const COORDINATOR_ACCEPTANCE_TIMEOUT_SECONDS: i64 =
    (crate::terminal_host::protocol::ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS / 1_000) as i64;
/// Worktrees more than this many commits behind their base are skipped at
/// dispatch pre-flight (silently retried next tick) unless the spec carries
/// `allow-stale-base: true`.
pub const COORDINATOR_DISPATCH_STALE_THRESHOLD: u64 = 20;

/// Configuration captured when `orchestration.run` starts a coordinator.
#[derive(Debug, Clone)]
pub struct CoordinatorConfig {
    pub run_id: String,
    pub coordinator_handle: Option<String>,
    pub poll_interval_ms: u64,
    pub max_concurrent: usize,
    pub workspace_id: Option<String>,
    pub agent_type: String,
}

/// The host-side handle for the single active coordinator: a ticker task that
/// enqueues `CoordinatorTick` commands. All actual work happens inside the
/// server actor so PTY and store mutations stay single-threaded.
pub struct CoordinatorHandle {
    pub config: CoordinatorConfig,
    ticker: JoinHandle<()>,
}

impl CoordinatorHandle {
    pub fn start<C: Send + 'static>(
        config: CoordinatorConfig,
        inbox: UnboundedSender<C>,
        make_tick: impl Fn(String) -> C + Send + 'static,
    ) -> Self {
        let run_id = config.run_id.clone();
        let poll = Duration::from_millis(config.poll_interval_ms.max(250));
        let ticker = tokio::spawn(async move {
            loop {
                tokio::time::sleep(poll).await;
                if inbox.send(make_tick(run_id.clone())).is_err() {
                    break;
                }
            }
        });
        CoordinatorHandle { config, ticker }
    }

    pub fn stop(&self) {
        self.ticker.abort();
    }
}

impl Drop for CoordinatorHandle {
    fn drop(&mut self) {
        self.ticker.abort();
    }
}

/// The ISO-8601-ish (SQLite `datetime('now')` shaped) threshold string for the
/// hung-dispatch query: now minus the hung threshold, second precision UTC.
pub fn hung_dispatch_threshold_iso(now: chrono::DateTime<chrono::Utc>) -> String {
    (now - chrono::Duration::minutes(COORDINATOR_HUNG_THRESHOLD_MINUTES))
        .format("%Y-%m-%d %H:%M:%S")
        .to_string()
}

pub fn acceptance_timeout_threshold_iso(now: chrono::DateTime<chrono::Utc>) -> String {
    (now - chrono::Duration::seconds(COORDINATOR_ACCEPTANCE_TIMEOUT_SECONDS))
        .format("%Y-%m-%d %H:%M:%S")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hung_threshold_matches_sqlite_shape() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-07-05T12:30:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(hung_dispatch_threshold_iso(now), "2026-07-05 12:20:00");
    }

    #[test]
    fn acceptance_timeout_threshold_matches_cli_wait() {
        let now = chrono::DateTime::parse_from_rfc3339("2026-07-05T12:30:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(acceptance_timeout_threshold_iso(now), "2026-07-05 12:28:30");
    }

    #[tokio::test]
    async fn ticker_emits_and_stop_aborts() {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
        let handle = CoordinatorHandle::start(
            CoordinatorConfig {
                run_id: "run_1".to_string(),
                coordinator_handle: None,
                poll_interval_ms: 250,
                max_concurrent: 4,
                workspace_id: None,
                agent_type: "codex".to_string(),
            },
            tx,
            |run_id| run_id,
        );
        let first = tokio::time::timeout(Duration::from_secs(2), rx.recv())
            .await
            .expect("tick within deadline");
        assert_eq!(first.as_deref(), Some("run_1"));
        handle.stop();
    }
}
