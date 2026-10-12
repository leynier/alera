//! Retry timing for host links that should be up but are not.
//!
//! Exponential with full jitter: the n-th retry waits a uniform amount up to
//! `base * factor^(n-1)`, capped. Jitter keeps a hub that lost every host at
//! once (a laptop waking up on a new network) from retrying them in lockstep.

use std::time::Duration;

/// A link closed on purpose during a runtime restart comes back on this delay
/// without counting as a failure.
pub(crate) const RESTART_RETRY_DELAY: Duration = Duration::from_secs(1);

/// The shortest wait full jitter may pick, so a retry never spins.
const MIN_RETRY_DELAY: Duration = Duration::from_millis(250);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RetrySchedule {
    pub(crate) base: Duration,
    pub(crate) factor: u32,
    pub(crate) cap: Duration,
}

impl RetrySchedule {
    pub(crate) const DEFAULT: RetrySchedule = RetrySchedule {
        base: Duration::from_secs(2),
        factor: 2,
        cap: Duration::from_secs(300),
    };

    /// The longest wait before retry number `attempt` (1-based).
    pub(crate) fn ceiling(&self, attempt: u32) -> Duration {
        let exponent = attempt.saturating_sub(1).min(32);
        let multiplier = u64::from(self.factor.max(1)).saturating_pow(exponent);
        let millis = u64::try_from(self.base.as_millis())
            .unwrap_or(u64::MAX)
            .saturating_mul(multiplier);
        Duration::from_millis(millis).min(self.cap)
    }

    /// The wait for retry number `attempt`, drawn with full jitter.
    pub(crate) fn delay(&self, attempt: u32) -> Duration {
        self.delay_at(attempt, rand::random::<f64>())
    }

    /// `unit` in `[0, 1)` picks the point inside the jitter window.
    pub(crate) fn delay_at(&self, attempt: u32, unit: f64) -> Duration {
        let ceiling = self.ceiling(attempt);
        ceiling
            .mul_f64(unit.clamp(0.0, 1.0))
            .max(MIN_RETRY_DELAY.min(ceiling))
    }
}

/// Consecutive failures of one host. A successful attach resets it.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Backoff {
    attempt: u32,
}

impl Backoff {
    pub(crate) fn attempt(&self) -> u32 {
        self.attempt
    }

    /// Records one more failure and returns the retry number it schedules.
    pub(crate) fn advance(&mut self) -> u32 {
        self.attempt = self.attempt.saturating_add(1);
        self.attempt
    }

    pub(crate) fn reset(&mut self) {
        self.attempt = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ceilings_double_until_the_cap() {
        let schedule = RetrySchedule::DEFAULT;
        let seconds: Vec<u64> = (1..=10)
            .map(|attempt| schedule.ceiling(attempt).as_secs())
            .collect();
        assert_eq!(seconds, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300]);
        assert_eq!(schedule.ceiling(u32::MAX), Duration::from_secs(300));
        assert_eq!(schedule.ceiling(0), Duration::from_secs(2));
    }

    #[test]
    fn jitter_stays_inside_the_window() {
        let schedule = RetrySchedule::DEFAULT;
        for attempt in 1..=12 {
            let ceiling = schedule.ceiling(attempt);
            for _ in 0..50 {
                let delay = schedule.delay(attempt);
                assert!(delay <= ceiling, "{delay:?} > {ceiling:?}");
                assert!(delay >= MIN_RETRY_DELAY, "{delay:?}");
            }
        }
        assert_eq!(schedule.delay_at(3, 0.5), Duration::from_secs(4));
        assert_eq!(schedule.delay_at(3, 1.0), Duration::from_secs(8));
        assert_eq!(schedule.delay_at(3, 0.0), MIN_RETRY_DELAY);
    }

    #[test]
    fn a_short_test_schedule_never_waits_past_its_ceiling() {
        let schedule = RetrySchedule {
            base: Duration::from_millis(20),
            factor: 2,
            cap: Duration::from_millis(100),
        };
        assert_eq!(schedule.delay_at(1, 0.0), Duration::from_millis(20));
        assert_eq!(schedule.delay_at(9, 1.0), Duration::from_millis(100));
    }

    #[test]
    fn backoff_counts_failures_and_resets_on_success() {
        let mut backoff = Backoff::default();
        assert_eq!(backoff.advance(), 1);
        assert_eq!(backoff.advance(), 2);
        assert_eq!(backoff.attempt(), 2);
        backoff.reset();
        assert_eq!(backoff.attempt(), 0);
        assert_eq!(backoff.advance(), 1);
    }
}
