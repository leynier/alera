use std::time::{Duration, Instant};

use tokio::task::JoinHandle;

/// Periodic work that runs only while clients keep asking for it, and stops
/// itself once they stop.
///
/// The host is a sidecar, so it cannot see whether the app's window is visible,
/// and it should not take a client's word for it either: a client that says it
/// went away may simply have died mid-report. Silence is the signal that
/// survives both. Every consumer of this is work nobody is reading when nobody
/// is asking, and leaving it running costs an unattended machine real cycles.
///
/// Ownership rather than a shared flag: dropping the ticker aborts its task, so
/// a consumer cannot leak one by forgetting to stop it.
pub struct DemandDrivenTicker {
    task: Option<JoinHandle<()>>,
    last_request_at: Option<Instant>,
    idle_stop: Duration,
}

impl DemandDrivenTicker {
    /// `idle_stop` is how long the ticker keeps going after the last request.
    /// It should comfortably exceed a client's polling period, or a client that
    /// polls on time would still find the ticker stopped.
    pub fn new(idle_stop: Duration) -> DemandDrivenTicker {
        DemandDrivenTicker {
            task: None,
            last_request_at: None,
            idle_stop,
        }
    }

    /// Record that a client asked for this work.
    pub fn note_request(&mut self) {
        self.last_request_at = Some(Instant::now());
    }

    pub fn is_running(&self) -> bool {
        self.task.is_some()
    }

    /// Whether nobody has asked for longer than the idle window. A ticker that
    /// was never asked counts as idle, so a stray tick cannot keep it alive.
    pub fn is_idle(&self) -> bool {
        self.last_request_at
            .is_none_or(|at| at.elapsed() > self.idle_stop)
    }

    /// Begin ticking every `interval`, replacing any previous task.
    ///
    /// `tick` returns whether to keep going, so a consumer whose receiver is
    /// gone ends the loop instead of ticking into nothing.
    pub fn start(&mut self, interval: Duration, tick: impl Fn() -> bool + Send + 'static) {
        self.stop();
        self.task = Some(tokio::spawn(async move {
            loop {
                tokio::time::sleep(interval).await;
                if !tick() {
                    break;
                }
            }
        }));
    }

    pub fn stop(&mut self) {
        if let Some(task) = self.task.take() {
            task.abort();
        }
    }
}

impl Drop for DemandDrivenTicker {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::*;

    const IDLE_STOP: Duration = Duration::from_millis(50);

    #[test]
    fn a_ticker_nobody_has_asked_for_is_idle() {
        // Otherwise the very first tick would find a fresh ticker "busy" and
        // keep sweeping for a client that never arrived.
        assert!(DemandDrivenTicker::new(IDLE_STOP).is_idle());
    }

    #[test]
    fn a_recent_request_keeps_the_ticker_busy() {
        let mut ticker = DemandDrivenTicker::new(IDLE_STOP);

        ticker.note_request();

        assert!(!ticker.is_idle());
    }

    #[tokio::test]
    async fn a_request_goes_stale_once_the_idle_window_passes() {
        let mut ticker = DemandDrivenTicker::new(Duration::from_millis(1));
        ticker.note_request();

        tokio::time::sleep(Duration::from_millis(20)).await;

        assert!(ticker.is_idle());
    }

    #[tokio::test]
    async fn ticks_fire_until_the_callback_declines() {
        let ticks = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ticks);
        let mut ticker = DemandDrivenTicker::new(IDLE_STOP);

        ticker.start(Duration::from_millis(1), move || {
            // Stop on the third tick, standing in for a receiver going away.
            counted.fetch_add(1, Ordering::SeqCst) < 2
        });
        tokio::time::sleep(Duration::from_millis(60)).await;

        assert_eq!(ticks.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn stopping_ends_the_ticks() {
        let ticks = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ticks);
        let mut ticker = DemandDrivenTicker::new(IDLE_STOP);
        ticker.start(Duration::from_millis(1), move || {
            counted.fetch_add(1, Ordering::SeqCst);
            true
        });
        tokio::time::sleep(Duration::from_millis(20)).await;

        ticker.stop();
        assert!(!ticker.is_running());
        let after_stop = ticks.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(20)).await;

        assert_eq!(ticks.load(Ordering::SeqCst), after_stop);
    }

    #[tokio::test]
    async fn dropping_ends_the_ticks() {
        // The reason the task is owned rather than tracked by a flag.
        let ticks = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ticks);
        let mut ticker = DemandDrivenTicker::new(IDLE_STOP);
        ticker.start(Duration::from_millis(1), move || {
            counted.fetch_add(1, Ordering::SeqCst);
            true
        });
        tokio::time::sleep(Duration::from_millis(20)).await;

        drop(ticker);
        let after_drop = ticks.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(20)).await;

        assert_eq!(ticks.load(Ordering::SeqCst), after_drop);
    }
}
