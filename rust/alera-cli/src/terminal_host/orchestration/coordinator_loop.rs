use std::{future::Future, pin::Pin, time::Duration};

use tokio::sync::mpsc::UnboundedSender;
use tokio::task::JoinHandle;

use crate::terminal_host::server::{ServerCommand, ServerInbox};

type CoordinatorInboxFuture = Pin<Box<dyn Future<Output = Result<(), ()>> + Send>>;

pub trait CoordinatorInbox<C>: Clone + Send + 'static {
    fn send_wait(&self, command: C) -> CoordinatorInboxFuture;
}

impl<C: Send + 'static> CoordinatorInbox<C> for UnboundedSender<C> {
    fn send_wait(&self, command: C) -> CoordinatorInboxFuture {
        let inbox = self.clone();
        Box::pin(async move { inbox.send(command).map_err(|_| ()) })
    }
}

impl CoordinatorInbox<ServerCommand> for ServerInbox {
    fn send_wait(&self, command: ServerCommand) -> CoordinatorInboxFuture {
        let inbox = self.clone();
        Box::pin(async move { inbox.send_wait(command).await.map_err(|_| ()) })
    }
}

/// Default coordinator cadence, mirroring Orca.
pub const COORDINATOR_DEFAULT_POLL_MS: u64 = 2_000;
pub const COORDINATOR_MAX_CONCURRENT_DEFAULT: usize = 4;
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
    pub fn start<C: Send + 'static, I: CoordinatorInbox<C>>(
        config: CoordinatorConfig,
        inbox: I,
        make_tick: impl Fn(String) -> C + Send + 'static,
    ) -> Self {
        let run_id = config.run_id.clone();
        let poll = Duration::from_millis(config.poll_interval_ms.max(250));
        let ticker = tokio::spawn(async move {
            loop {
                tokio::time::sleep(poll).await;
                // A saturated runtime inbox is transient. `send_wait` keeps
                // this run alive until admission returns and stops cleanly
                // when the actor closes, with one pending tick at a time.
                if inbox.send_wait(make_tick(run_id.clone())).await.is_err() {
                    return;
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

#[cfg(test)]
mod tests {
    use super::*;

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
