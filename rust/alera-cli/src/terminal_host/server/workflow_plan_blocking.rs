use std::sync::Arc;

use tokio::sync::OwnedSemaphorePermit;
use tokio::task::JoinHandle;

pub(super) fn spawn<F, T>(permit: Arc<OwnedSemaphorePermit>, work: F) -> JoinHandle<T>
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
{
    tokio::task::spawn_blocking(move || {
        // A response timeout cannot cancel blocking Git/serialization work.
        // Keep its queue slot occupied until the actual operation finishes.
        let _permit = permit;
        work()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio::sync::{oneshot, Semaphore};

    #[tokio::test]
    async fn workflow_plan_blocking_retains_capacity_after_response_timeout() {
        let queue = Arc::new(Semaphore::new(1));
        let permit = Arc::new(queue.clone().try_acquire_owned().unwrap());
        let (started_tx, started_rx) = oneshot::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let worker = spawn(permit.clone(), move || {
            started_tx.send(()).unwrap();
            release_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        });
        started_rx.await.unwrap();
        assert!(tokio::time::timeout(Duration::from_millis(1), worker)
            .await
            .is_err());
        drop(permit);
        let retained = queue.clone().try_acquire_owned().is_err();
        release_tx.send(()).unwrap();
        let recovered = tokio::time::timeout(Duration::from_secs(5), queue.acquire()).await;
        assert!(retained, "timed-out work must still consume its queue slot");
        assert!(
            recovered.is_ok(),
            "finished work must release its queue slot"
        );
    }
}
