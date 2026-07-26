use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::computer_use::snapshot_contract::ElementRecord;

/// How many observations are remembered at once.
///
/// An agent works one window at a time; the room is for the handful of windows
/// it moves between, not for a history.
pub const CACHE_CAPACITY: usize = 32;

/// How long an observation may be acted on.
///
/// Short on purpose: an element index describes a moment, and an agent that
/// comes back to a two-minute-old tree is looking at a window the user has
/// since touched. Expiry turns that into a refusal it can recover from.
pub const CACHE_TTL: Duration = Duration::from_secs(120);

/// What the host keeps so a later action can find an element again.
#[derive(Debug, Clone)]
pub struct CachedSnapshot {
    pub snapshot_id: String,
    pub app_pid: u32,
    pub window_index: usize,
    pub window_id: Option<i64>,
    pub elements: Vec<ElementRecord>,
}

impl CachedSnapshot {
    pub fn element(&self, index: usize) -> Option<&ElementRecord> {
        self.elements.iter().find(|element| element.index == index)
    }
}

/// Observations remembered per caller, addressed by every name the caller might
/// use next.
///
/// Keyed by many names because the agent that read the tree with `--app Spotify`
/// may act with `--app com.spotify.client`, and neither spelling should lose the
/// indexes it was just given.
pub struct SnapshotCache {
    entries: VecDeque<Entry>,
    capacity: usize,
    ttl: Duration,
}

struct Entry {
    keys: Vec<String>,
    stored_at: Instant,
    snapshot: CachedSnapshot,
}

impl Default for SnapshotCache {
    fn default() -> Self {
        SnapshotCache::new(CACHE_CAPACITY, CACHE_TTL)
    }
}

impl SnapshotCache {
    pub fn new(capacity: usize, ttl: Duration) -> Self {
        SnapshotCache {
            entries: VecDeque::new(),
            capacity,
            ttl,
        }
    }

    /// Remember an observation under each of the names it can be asked for.
    pub fn insert(&mut self, keys: Vec<String>, snapshot: CachedSnapshot, now: Instant) {
        // A fresh observation of the same window replaces the old one, so the
        // cache cannot answer with indexes the agent has already superseded.
        self.entries
            .retain(|entry| !entry.keys.iter().any(|key| keys.contains(key)));
        self.entries.push_back(Entry {
            keys,
            stored_at: now,
            snapshot,
        });
        while self.entries.len() > self.capacity {
            self.entries.pop_front();
        }
    }

    /// The newest live observation stored under this key.
    pub fn get(&self, key: &str, now: Instant) -> Option<&CachedSnapshot> {
        self.entries
            .iter()
            .rev()
            .find(|entry| !entry.is_expired(now, self.ttl) && entry.keys.iter().any(|k| k == key))
            .map(|entry| &entry.snapshot)
    }

    /// Look up by snapshot id, which is how an agent pins the exact observation
    /// it read rather than whatever is newest for that window.
    pub fn get_by_id(&self, snapshot_id: &str, now: Instant) -> Option<&CachedSnapshot> {
        self.entries
            .iter()
            .rev()
            .find(|entry| {
                !entry.is_expired(now, self.ttl) && entry.snapshot.snapshot_id == snapshot_id
            })
            .map(|entry| &entry.snapshot)
    }

    /// Drop expired entries. Called on insert paths rather than on a timer: the
    /// host must not wake up to tidy a cache nobody is reading.
    pub fn evict_expired(&mut self, now: Instant) {
        let ttl = self.ttl;
        self.entries.retain(|entry| !entry.is_expired(now, ttl));
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

impl Entry {
    fn is_expired(&self, now: Instant, ttl: Duration) -> bool {
        now.saturating_duration_since(self.stored_at) > ttl
    }
}

/// Every name an observation should answer to.
///
/// The namespace keeps two agents working in different workspaces from reading
/// each other's element indexes, which would be a silent wrong click rather than
/// an error.
pub fn cache_keys(
    namespace: &str,
    app_name: &str,
    bundle_id: Option<&str>,
    pid: u32,
    window_index: usize,
    window_id: Option<i64>,
) -> Vec<String> {
    let mut keys = vec![
        format!("{namespace}|name:{}", app_name.to_lowercase()),
        format!("{namespace}|pid:{pid}"),
    ];
    if let Some(bundle_id) = bundle_id {
        keys.push(format!("{namespace}|bundle:{}", bundle_id.to_lowercase()));
    }
    keys.push(format!("{namespace}|pid:{pid}#index:{window_index}"));
    if let Some(window_id) = window_id {
        keys.push(format!("{namespace}|pid:{pid}#id:{window_id}"));
    }
    keys
}

/// The key a caller's request maps to, given how it named the app and window.
pub fn lookup_key(
    namespace: &str,
    app_query: &str,
    pid: Option<u32>,
    window_index: Option<usize>,
    window_id: Option<i64>,
) -> String {
    let base = match pid {
        Some(pid) => format!("{namespace}|pid:{pid}"),
        None => format!("{namespace}|name:{}", app_query.to_lowercase()),
    };
    match (window_id, window_index) {
        (Some(id), _) => format!("{base}#id:{id}"),
        (None, Some(index)) => format!("{base}#index:{index}"),
        (None, None) => base,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(id: &str, pid: u32) -> CachedSnapshot {
        CachedSnapshot {
            snapshot_id: id.to_string(),
            app_pid: pid,
            window_index: 0,
            window_id: None,
            elements: vec![ElementRecord {
                index: 4,
                role: "push button".to_string(),
                name: "Play".to_string(),
                value: None,
                actions: Vec::new(),
                frame: None,
                path: vec![0, 1],
                signature: "sig".to_string(),
                redacted: false,
            }],
        }
    }

    #[test]
    fn an_observation_is_found_under_every_name_it_was_stored_with() {
        let mut cache = SnapshotCache::default();
        let now = Instant::now();
        let keys = cache_keys("ws1", "Spotify", Some("com.spotify.client"), 42, 0, None);
        cache.insert(keys, snapshot("s1", 42), now);

        for key in [
            "ws1|name:spotify",
            "ws1|pid:42",
            "ws1|bundle:com.spotify.client",
            "ws1|pid:42#index:0",
        ] {
            assert!(cache.get(key, now).is_some(), "{key}");
        }
    }

    /// The agent may read with a name and act with a bundle id; losing the
    /// indexes in between would look like the tree went stale for no reason.
    #[test]
    fn a_lookup_key_matches_the_stored_keys() {
        let mut cache = SnapshotCache::default();
        let now = Instant::now();
        cache.insert(
            cache_keys("ws1", "Spotify", Some("com.spotify.client"), 42, 0, None),
            snapshot("s1", 42),
            now,
        );
        let by_name = lookup_key("ws1", "Spotify", None, None, None);
        let by_pid = lookup_key("ws1", "", Some(42), None, None);
        let by_index = lookup_key("ws1", "", Some(42), Some(0), None);
        assert!(cache.get(&by_name, now).is_some());
        assert!(cache.get(&by_pid, now).is_some());
        assert!(cache.get(&by_index, now).is_some());
    }

    /// Two agents in different workspaces must never read each other's indexes:
    /// that is a wrong click, not an error.
    #[test]
    fn namespaces_do_not_see_each_other() {
        let mut cache = SnapshotCache::default();
        let now = Instant::now();
        cache.insert(
            cache_keys("ws1", "Spotify", None, 42, 0, None),
            snapshot("s1", 42),
            now,
        );
        assert!(cache.get("ws1|pid:42", now).is_some());
        assert!(cache.get("ws2|pid:42", now).is_none());
    }

    #[test]
    fn an_expired_observation_is_not_returned() {
        let mut cache = SnapshotCache::new(4, Duration::from_secs(10));
        let now = Instant::now();
        cache.insert(vec!["k".to_string()], snapshot("s1", 1), now);
        assert!(cache.get("k", now + Duration::from_secs(9)).is_some());
        assert!(cache.get("k", now + Duration::from_secs(11)).is_none());
    }

    #[test]
    fn expired_observations_are_evicted() {
        let mut cache = SnapshotCache::new(4, Duration::from_secs(10));
        let now = Instant::now();
        cache.insert(vec!["k".to_string()], snapshot("s1", 1), now);
        assert_eq!(cache.len(), 1);
        cache.evict_expired(now + Duration::from_secs(11));
        assert!(cache.is_empty());
    }

    #[test]
    fn the_oldest_observation_is_dropped_at_capacity() {
        let mut cache = SnapshotCache::new(2, CACHE_TTL);
        let now = Instant::now();
        for i in 0..3 {
            cache.insert(vec![format!("k{i}")], snapshot(&format!("s{i}"), i), now);
        }
        assert_eq!(cache.len(), 2);
        assert!(cache.get("k0", now).is_none());
        assert!(cache.get("k2", now).is_some());
    }

    /// Re-reading a window must retire the previous indexes rather than leave
    /// two live answers for the same key.
    #[test]
    fn a_new_observation_replaces_the_one_it_shares_a_key_with() {
        let mut cache = SnapshotCache::default();
        let now = Instant::now();
        let keys = cache_keys("ws1", "Spotify", None, 42, 0, None);
        cache.insert(keys.clone(), snapshot("s1", 42), now);
        cache.insert(keys, snapshot("s2", 42), now);
        assert_eq!(cache.len(), 1);
        assert_eq!(cache.get("ws1|pid:42", now).unwrap().snapshot_id, "s2");
    }

    #[test]
    fn an_observation_can_be_pinned_by_its_snapshot_id() {
        let mut cache = SnapshotCache::default();
        let now = Instant::now();
        cache.insert(vec!["a".to_string()], snapshot("s1", 1), now);
        cache.insert(vec!["b".to_string()], snapshot("s2", 2), now);
        assert_eq!(cache.get_by_id("s1", now).unwrap().app_pid, 1);
        assert!(cache.get_by_id("missing", now).is_none());
    }

    #[test]
    fn an_element_is_looked_up_by_its_index_not_its_position() {
        let cached = snapshot("s1", 1);
        assert_eq!(cached.element(4).unwrap().name, "Play");
        assert!(cached.element(0).is_none());
    }

    #[test]
    fn a_window_id_takes_precedence_over_an_index_in_a_lookup() {
        let key = lookup_key("ws1", "", Some(42), Some(3), Some(99));
        assert_eq!(key, "ws1|pid:42#id:99");
    }
}
