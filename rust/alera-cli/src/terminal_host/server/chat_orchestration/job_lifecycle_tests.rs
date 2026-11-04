use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::time::Duration;

use tokio::sync::Notify;

use super::OrchestrationJobs;
use crate::terminal_host::server::chat_orchestration::test_support::TEST_DEADLINE;

async fn wait_empty(jobs: &OrchestrationJobs) {
    tokio::time::timeout(TEST_DEADLINE, async {
        while jobs.retained_handles() != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("completed orchestration jobs retained their handles");
}

#[tokio::test]
async fn completed_jobs_prune_their_handles_without_another_admission() {
    let jobs = Arc::new(OrchestrationJobs::default());
    for _ in 0..32 {
        assert!(jobs.spawn(async {}).is_some());
        wait_empty(&jobs).await;
    }
    assert!(jobs.shutdown().await);
    let invoked = Arc::new(AtomicBool::new(false));
    let attempted = invoked.clone();
    assert!(jobs
        .spawn(async move { attempted.store(true, Ordering::Release) })
        .is_none());
    assert!(!invoked.load(Ordering::Acquire));
    assert_eq!(jobs.retained_handles(), 0);
    assert!(jobs.shutdown().await);
}

#[tokio::test]
async fn a_job_cancelled_before_its_first_poll_prunes_without_another_admission() {
    let jobs = Arc::new(OrchestrationJobs::default());
    let ran = Arc::new(AtomicBool::new(false));
    let running = ran.clone();
    let job = jobs
        .spawn(async move { running.store(true, Ordering::Release) })
        .unwrap();
    job.abort();
    wait_empty(&jobs).await;
    assert!(!ran.load(Ordering::Acquire));
    assert!(jobs.shutdown().await);
}

struct PausedCleanup {
    entered: Arc<Notify>,
    release: mpsc::Receiver<()>,
    finished: Arc<AtomicBool>,
}

impl Drop for PausedCleanup {
    fn drop(&mut self) {
        self.entered.notify_one();
        self.release
            .recv_timeout(TEST_DEADLINE)
            .expect("cancellation cleanup gate was not released");
        self.finished.store(true, Ordering::Release);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn shutdown_deadline_retains_unfinished_cleanup_and_refuses_new_jobs_until_retry() {
    let jobs = Arc::new(OrchestrationJobs::default());
    let started = Arc::new(Notify::new());
    let entered = Arc::new(Notify::new());
    let finished = Arc::new(AtomicBool::new(false));
    let (release, gate) = mpsc::channel();
    let cleanup = PausedCleanup {
        entered: entered.clone(),
        release: gate,
        finished: finished.clone(),
    };
    let running = started.clone();
    assert!(jobs
        .spawn(async move {
            let _cleanup = cleanup;
            running.notify_one();
            std::future::pending::<()>().await;
        })
        .is_some());
    tokio::time::timeout(TEST_DEADLINE, started.notified())
        .await
        .unwrap();
    assert!(
        !jobs
            .shutdown_until(tokio::time::Instant::now() + Duration::from_millis(20))
            .await
    );
    tokio::time::timeout(TEST_DEADLINE, entered.notified())
        .await
        .unwrap();
    assert!(jobs.is_closed());
    assert_eq!(jobs.retained_handles(), 1);
    assert!(!finished.load(Ordering::Acquire));
    assert!(jobs.spawn(async {}).is_none());
    release.send(()).unwrap();
    assert!(jobs.shutdown().await);
    assert!(finished.load(Ordering::Acquire));
    assert_eq!(jobs.retained_handles(), 0);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn dropping_a_shutdown_future_preserves_awaitable_jobs_for_the_next_attempt() {
    let jobs = Arc::new(OrchestrationJobs::default());
    let started = Arc::new(Notify::new());
    let entered = Arc::new(Notify::new());
    let finished = Arc::new(AtomicBool::new(false));
    let (release, gate) = mpsc::channel();
    let cleanup = PausedCleanup {
        entered: entered.clone(),
        release: gate,
        finished: finished.clone(),
    };
    let running = started.clone();
    assert!(jobs
        .spawn(async move {
            let _cleanup = cleanup;
            running.notify_one();
            std::future::pending::<()>().await;
        })
        .is_some());
    tokio::time::timeout(TEST_DEADLINE, started.notified())
        .await
        .unwrap();
    let stopping = jobs.clone();
    let shutdown = tokio::spawn(async move { stopping.shutdown().await });
    tokio::time::timeout(TEST_DEADLINE, entered.notified())
        .await
        .unwrap();
    shutdown.abort();
    assert!(tokio::time::timeout(TEST_DEADLINE, shutdown)
        .await
        .unwrap()
        .unwrap_err()
        .is_cancelled());
    assert!(jobs.is_closed());
    assert_eq!(jobs.retained_handles(), 1);
    assert!(!finished.load(Ordering::Acquire));
    release.send(()).unwrap();
    assert!(jobs.shutdown().await);
    assert!(finished.load(Ordering::Acquire));
    assert_eq!(jobs.retained_handles(), 0);
}
