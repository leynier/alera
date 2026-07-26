use std::time::{Duration, Instant, SystemTime};

/// Sleeps shorter than this are not recorded.
///
/// A laptop lid closed for a couple of seconds explains nothing and would bury
/// the gaps that do. Orca measured a week of real sleep cycles for the same
/// decision: the median was 2 seconds and only about a quarter ran past a
/// minute, so a threshold here cuts almost all of the traffic while still
/// catching every gap long enough to be mistaken for a hang.
const MIN_REPORTABLE_SLEEP: Duration = Duration::from_secs(60);

/// Tells a machine that was asleep apart from a host that was wedged.
///
/// The two look identical from the outside: no output, no progress, a long
/// silence. Telling them apart matters because only one of them is a bug, and
/// mistaking a lid for a deadlock sends an investigation somewhere expensive.
///
/// No platform APIs involved. `Instant` runs on a monotonic clock that does not
/// advance while the machine is suspended (`CLOCK_MONOTONIC` on Linux excludes
/// suspended time, and `mach_absolute_time` pauses on macOS), while
/// `SystemTime` keeps wall-clock time across the gap. When the two disagree,
/// the difference is how long the machine was away.
pub struct SleepDetector {
    last_observed: Option<(Instant, SystemTime)>,
    min_reportable: Duration,
}

impl Default for SleepDetector {
    fn default() -> Self {
        SleepDetector::new(MIN_REPORTABLE_SLEEP)
    }
}

impl SleepDetector {
    pub fn new(min_reportable: Duration) -> SleepDetector {
        SleepDetector {
            last_observed: None,
            min_reportable,
        }
    }

    /// Note that the host is doing something now, and report a sleep if the
    /// wall clock ran ahead of the monotonic clock since the last observation.
    ///
    /// Called from the actor's command loop rather than a timer of its own, so
    /// an idle host stays completely quiet and a wake is noticed by the first
    /// thing that happens afterwards, which is exactly when someone is around
    /// to care.
    pub fn observe(&mut self) -> Option<Duration> {
        self.observe_at(Instant::now(), SystemTime::now())
    }

    fn observe_at(&mut self, monotonic: Instant, wall: SystemTime) -> Option<Duration> {
        let previous = self.last_observed.replace((monotonic, wall));
        let (last_monotonic, last_wall) = previous?;
        let awake = monotonic.saturating_duration_since(last_monotonic);
        // A wall clock that went backwards is a correction, never a sleep.
        let elapsed = wall.duration_since(last_wall).ok()?;
        let slept = elapsed.checked_sub(awake)?;
        (slept >= self.min_reportable).then_some(slept)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const THRESHOLD: Duration = Duration::from_secs(60);

    fn detector() -> SleepDetector {
        SleepDetector::new(THRESHOLD)
    }

    /// A suspend: wall time advances by `wall`, monotonic time by `awake`.
    fn advance(
        base: (Instant, SystemTime),
        awake: Duration,
        wall: Duration,
    ) -> (Instant, SystemTime) {
        (base.0 + awake, base.1 + wall)
    }

    fn origin() -> (Instant, SystemTime) {
        (
            Instant::now(),
            SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000),
        )
    }

    #[test]
    fn the_first_observation_reports_nothing() {
        // There is no earlier point to measure a gap against.
        let start = origin();

        assert_eq!(detector().observe_at(start.0, start.1), None);
    }

    #[test]
    fn a_busy_host_reports_no_sleep() {
        // Both clocks advance together, which is what being awake looks like.
        let start = origin();
        let mut detector = detector();
        detector.observe_at(start.0, start.1);

        let later = advance(
            start,
            Duration::from_secs(3_600),
            Duration::from_secs(3_600),
        );

        assert_eq!(detector.observe_at(later.0, later.1), None);
    }

    #[test]
    fn a_long_sleep_is_reported_with_its_span() {
        let start = origin();
        let mut detector = detector();
        detector.observe_at(start.0, start.1);

        // Eight hours of wall clock, thirty seconds of it awake.
        let after_wake = advance(
            start,
            Duration::from_secs(30),
            Duration::from_secs(8 * 3_600),
        );

        assert_eq!(
            detector.observe_at(after_wake.0, after_wake.1),
            Some(Duration::from_secs(8 * 3_600 - 30))
        );
    }

    #[test]
    fn a_short_sleep_stays_quiet() {
        // The case the threshold exists for: frequent, brief, and explains
        // nothing, so recording it would only bury the gaps that do.
        let start = origin();
        let mut detector = detector();
        detector.observe_at(start.0, start.1);

        let after_wake = advance(start, Duration::ZERO, Duration::from_secs(2));

        assert_eq!(detector.observe_at(after_wake.0, after_wake.1), None);
    }

    #[test]
    fn a_backwards_wall_clock_is_not_a_sleep() {
        // An NTP correction, not a suspend.
        let start = origin();
        let mut detector = detector();
        detector.observe_at(start.0, start.1);

        let corrected = (
            start.0 + Duration::from_secs(10),
            start.1 - Duration::from_secs(600),
        );

        assert_eq!(detector.observe_at(corrected.0, corrected.1), None);
    }

    #[test]
    fn each_sleep_is_measured_from_the_last_observation() {
        // The stamp advances even on a quiet observation, so a single long gap
        // is not reported twice.
        let start = origin();
        let mut detector = detector();
        detector.observe_at(start.0, start.1);
        let after_wake = advance(start, Duration::ZERO, Duration::from_secs(3_600));
        assert!(detector.observe_at(after_wake.0, after_wake.1).is_some());

        let busy = advance(after_wake, Duration::from_secs(60), Duration::from_secs(60));

        assert_eq!(detector.observe_at(busy.0, busy.1), None);
    }
}
