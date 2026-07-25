use std::collections::HashMap;
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// Samples kept per key. At the 2 s sampling cadence this is about two minutes
/// of sparkline, which is what the panel draws.
pub const HISTORY_CAPACITY: usize = 60;
/// Keys untouched for this long are dropped, so closed sessions do not keep
/// their samples alive for the lifetime of the host.
pub const HISTORY_STALE: Duration = Duration::from_secs(10 * 60);

struct HistorySeries {
    samples: VecDeque<u64>,
    touched_at: Instant,
}

/// Per-key memory history. Only memory is historized: a CPU sparkline over a
/// 2 s cadence is noise, and Orca reached the same conclusion.
#[derive(Default)]
pub struct ResourceHistory {
    series: HashMap<String, HistorySeries>,
}

impl ResourceHistory {
    /// Record a sample and return the series, oldest first, including the value
    /// just pushed.
    pub fn record(&mut self, key: &str, memory_bytes: u64, now: Instant) -> Vec<u64> {
        let series = self
            .series
            .entry(key.to_string())
            .or_insert_with(|| HistorySeries {
                samples: VecDeque::with_capacity(HISTORY_CAPACITY),
                touched_at: now,
            });
        series.touched_at = now;
        if series.samples.len() == HISTORY_CAPACITY {
            series.samples.pop_front();
        }
        series.samples.push_back(memory_bytes);
        series.samples.iter().copied().collect()
    }

    pub fn evict_stale(&mut self, now: Instant) {
        self.series
            .retain(|_, series| now.duration_since(series.touched_at) < HISTORY_STALE);
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.series.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_series_returns_samples_oldest_first_including_the_new_one() {
        let mut history = ResourceHistory::default();
        let now = Instant::now();

        history.record("a", 1, now);
        history.record("a", 2, now);
        let samples = history.record("a", 3, now);

        assert_eq!(samples, vec![1, 2, 3]);
    }

    #[test]
    fn a_series_is_bounded_by_its_capacity() {
        let mut history = ResourceHistory::default();
        let now = Instant::now();

        let mut samples = Vec::new();
        for value in 0..(HISTORY_CAPACITY as u64 + 5) {
            samples = history.record("a", value, now);
        }

        assert_eq!(samples.len(), HISTORY_CAPACITY);
        assert_eq!(samples.first(), Some(&5));
        assert_eq!(samples.last(), Some(&(HISTORY_CAPACITY as u64 + 4)));
    }

    #[test]
    fn series_are_kept_apart_by_key() {
        let mut history = ResourceHistory::default();
        let now = Instant::now();

        history.record("a", 1, now);
        history.record("b", 9, now);

        assert_eq!(history.record("a", 2, now), vec![1, 2]);
        assert_eq!(history.record("b", 8, now), vec![9, 8]);
    }

    #[test]
    fn untouched_series_are_evicted() {
        let mut history = ResourceHistory::default();
        let start = Instant::now();
        history.record("gone", 1, start);
        let later = start + HISTORY_STALE + Duration::from_secs(1);
        history.record("kept", 1, later);

        history.evict_stale(later);

        assert_eq!(history.len(), 1);
        assert_eq!(history.record("kept", 2, later), vec![1, 2]);
        // The evicted key starts over rather than resurrecting old samples.
        assert_eq!(history.record("gone", 5, later), vec![5]);
    }
}
