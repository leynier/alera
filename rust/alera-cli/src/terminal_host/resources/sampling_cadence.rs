//! How often the sampler runs, and how long it keeps running unasked.

use std::time::Duration;

/// Sampling cadence for a client that does not state one, and the floor for
/// one that does. Matches the panel's own refresh.
pub const RESOURCE_SAMPLE_INTERVAL: Duration = Duration::from_secs(2);
/// Ceiling for a client-stated cadence. Beyond this the CPU delta spans so much
/// history that it stops describing anything the user is looking at.
pub const RESOURCE_MAX_SAMPLE_INTERVAL: Duration = Duration::from_secs(60);
/// Idle window for a client that does not state a cadence.
pub const RESOURCE_IDLE_STOP: Duration = Duration::from_secs(10);

/// How long the ticker keeps sampling after the last request, for a client that
/// polls every `interval`.
///
/// The window has to outlast a client's polling period with room for one missed
/// round, or a client polling exactly on time finds the ticker already stopped
/// and never gets anything but a warming snapshot. Deriving it here is what
/// keeps that invariant from depending on a constant in the app agreeing with a
/// constant in the host.
pub fn resource_idle_stop_for(interval: Duration) -> Duration {
    (interval * 5 / 2).max(RESOURCE_IDLE_STOP)
}

/// A client-stated cadence held to the range the sampler can serve.
pub fn clamp_resource_interval(interval: Duration) -> Duration {
    interval.clamp(RESOURCE_SAMPLE_INTERVAL, RESOURCE_MAX_SAMPLE_INTERVAL)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stated_cadence_is_held_to_what_the_sampler_can_serve() {
        assert_eq!(
            clamp_resource_interval(Duration::from_secs(15)),
            Duration::from_secs(15)
        );
        assert_eq!(
            clamp_resource_interval(Duration::from_millis(50)),
            RESOURCE_SAMPLE_INTERVAL
        );
        assert_eq!(
            clamp_resource_interval(Duration::from_secs(600)),
            RESOURCE_MAX_SAMPLE_INTERVAL
        );
    }

    #[test]
    fn the_idle_window_outlasts_the_cadence_it_was_derived_from() {
        // The bug this replaces: a 15s poll against a fixed 10s window meant
        // the ticker was always already stopped when the next request arrived.
        for seconds in [2, 5, 15, 60] {
            let interval = Duration::from_secs(seconds);
            assert!(
                resource_idle_stop_for(interval) > interval * 2,
                "idle window must survive a missed poll at {seconds}s"
            );
        }
    }

    #[test]
    fn a_client_that_states_nothing_keeps_the_old_defaults() {
        assert_eq!(
            resource_idle_stop_for(RESOURCE_SAMPLE_INTERVAL),
            RESOURCE_IDLE_STOP
        );
    }
}
