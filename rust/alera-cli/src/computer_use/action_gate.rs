use std::sync::LazyLock;

use tokio::sync::{Mutex, MutexGuard};

/// Serializes actions that change the desktop.
///
/// There is one pointer, one keyboard focus, and one window stack. Two actions
/// running at once interleave into a sequence neither caller asked for: a click
/// that lands after another window was raised, or a value written into a field
/// that just lost focus. Reads are not gated, since observing does not disturb
/// anything.
static GATE: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

/// Hold the desktop for the duration of one action.
///
/// The guard is awaited rather than tried: a caller that arrives during another
/// action should wait its turn, not fail. Actions are short, and the alternative
/// is asking agents to implement their own retry.
pub async fn hold() -> MutexGuard<'static, ()> {
    GATE.lock().await
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::*;

    /// The property that matters: no two holders overlap.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn actions_never_overlap() {
        let concurrent = Arc::new(AtomicUsize::new(0));
        let peak = Arc::new(AtomicUsize::new(0));
        let mut tasks = Vec::new();
        for _ in 0..8 {
            let concurrent = Arc::clone(&concurrent);
            let peak = Arc::clone(&peak);
            tasks.push(tokio::spawn(async move {
                let _guard = hold().await;
                let now = concurrent.fetch_add(1, Ordering::SeqCst) + 1;
                peak.fetch_max(now, Ordering::SeqCst);
                tokio::task::yield_now().await;
                concurrent.fetch_sub(1, Ordering::SeqCst);
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        assert_eq!(peak.load(Ordering::SeqCst), 1);
    }

    /// A waiter must get its turn rather than an error.
    #[tokio::test]
    async fn a_second_caller_waits_and_then_proceeds() {
        let first = hold().await;
        drop(first);
        let second = tokio::time::timeout(std::time::Duration::from_secs(1), hold()).await;
        assert!(second.is_ok());
    }
}
