use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use std::time::Duration;

use tokio::time::sleep;

use super::{run_bounded_deliveries, MAX_PARALLEL_DELIVERIES};

#[tokio::test]
async fn bounds_parallel_push_delivery_tasks() {
    let active = Arc::new(AtomicUsize::new(0));
    let maximum = Arc::new(AtomicUsize::new(0));
    let tasks = (0..(MAX_PARALLEL_DELIVERIES * 2))
        .map(|_| {
            let active = active.clone();
            let maximum = maximum.clone();
            async move {
                let now = active.fetch_add(1, Ordering::SeqCst) + 1;
                maximum.fetch_max(now, Ordering::SeqCst);
                sleep(Duration::from_millis(10)).await;
                active.fetch_sub(1, Ordering::SeqCst);
                Ok(true)
            }
        })
        .collect();
    let results = run_bounded_deliveries(tasks).await;
    assert_eq!(results.len(), MAX_PARALLEL_DELIVERIES * 2);
    assert!(results.iter().all(Result::is_ok));
    assert!(maximum.load(Ordering::SeqCst) <= MAX_PARALLEL_DELIVERIES);
}
