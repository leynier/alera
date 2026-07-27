use std::sync::{LazyLock, Mutex};
use std::time::Instant;

use crate::computer_use::contract::AppInfo;
use crate::computer_use::error::{ComputerError, ComputerErrorCode, ComputerResult};
use crate::computer_use::snapshot_cache::{cache_keys, lookup_key, CachedSnapshot, SnapshotCache};
use crate::computer_use::snapshot_contract::{ElementRecord, Snapshot};

/// Observations remembered for this host process.
///
/// Process-wide because the desktop is: there is one set of windows to observe,
/// however many callers are looking at it. Keeping it here rather than on the
/// server actor also keeps it out of the actor's test constructors, which have no
/// desktop to observe.
static REGISTRY: LazyLock<Mutex<SnapshotCache>> = LazyLock::new(Mutex::default);

/// Remember an observation so a later action can resolve its element indexes.
pub fn remember(namespace: &str, snapshot: &Snapshot) {
    let keys = cache_keys(
        namespace,
        &snapshot.app.name,
        snapshot.app.bundle_id.as_deref(),
        snapshot.app.pid,
        snapshot.window.index,
        snapshot.window.id,
    );
    let cached = CachedSnapshot {
        snapshot_id: snapshot.snapshot_id.clone(),
        app_pid: snapshot.app.pid,
        window_index: snapshot.window.index,
        window_id: snapshot.window.id,
        elements: snapshot.elements.clone(),
    };
    if let Ok(mut registry) = REGISTRY.lock() {
        let now = Instant::now();
        registry.evict_expired(now);
        registry.insert(keys, cached, now);
    }
}

/// Find the element an agent named, or explain why its index cannot be used.
///
/// A stale index is the most common failure of an agent loop, so the refusal has
/// to say what to do rather than only that something was wrong.
pub fn resolve_element(
    namespace: &str,
    app: &AppInfo,
    snapshot_id: Option<&str>,
    index: usize,
) -> ComputerResult<(ElementRecord, usize)> {
    let registry = REGISTRY
        .lock()
        .map_err(|_| ComputerError::new(ComputerErrorCode::AccessibilityError, POISONED))?;
    let now = Instant::now();
    let cached = match snapshot_id {
        Some(id) => registry.get_by_id(id, now).ok_or_else(|| {
            ComputerError::new(
                ComputerErrorCode::ElementNotFound,
                format!(
                    "Observation `{id}` is no longer held. Re-read the app state and use an \
                     index from that tree."
                ),
            )
        })?,
        None => {
            let key = lookup_key(namespace, &app.name, Some(app.pid), None, None);
            registry.get(&key, now).ok_or_else(|| {
                ComputerError::new(
                    ComputerErrorCode::ElementNotFound,
                    format!(
                        "No recent observation of `{}` is held, so element {index} cannot be \
                         resolved. Read the app state first.",
                        app.name
                    ),
                )
            })?
        }
    };
    let element = cached.element(index).cloned().ok_or_else(|| {
        ComputerError::new(
            ComputerErrorCode::ElementNotFound,
            format!(
                "Element {index} is not in the last observation of `{}`. Indexes are sparse and \
                 short-lived: re-read the app state and use one it reports.",
                app.name
            ),
        )
    })?;
    Ok((element, cached.window_index))
}

const POISONED: &str = "The computer-use observation cache is unusable after an earlier failure. \
                        Restart the runtime host.";

/// Take the registry for one test and leave it empty.
///
/// The registry is process-wide, and tests run in parallel in one process, so a
/// test that only cleared it would race the test inserting next. The returned
/// guard serializes them instead.
#[cfg(test)]
pub fn take_for_test() -> std::sync::MutexGuard<'static, ()> {
    static TEST_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));
    // A test that panicked while holding this poisoned the lock; the next test
    // still needs to run, and it starts from an empty registry regardless.
    let guard = TEST_LOCK.lock().unwrap_or_else(|error| error.into_inner());
    if let Ok(mut registry) = REGISTRY.lock() {
        *registry = SnapshotCache::default();
    }
    guard
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::computer_use::snapshot_contract::{
        Rect, Truncation, WindowInfo, WINDOW_COORDINATE_SPACE,
    };

    fn app(pid: u32) -> AppInfo {
        AppInfo {
            name: format!("App{pid}"),
            bundle_id: None,
            pid,
        }
    }

    fn snapshot(id: &str, pid: u32, indexes: &[usize]) -> Snapshot {
        Snapshot {
            snapshot_id: id.to_string(),
            app: app(pid),
            window: WindowInfo {
                id: None,
                index: 0,
                title: "w".to_string(),
                bounds: Some(Rect::new(0.0, 0.0, 100.0, 100.0)),
                is_active: true,
            },
            coordinate_space: WINDOW_COORDINATE_SPACE,
            tree_text: String::new(),
            element_count: indexes.len(),
            focused_element_index: None,
            truncation: Truncation {
                truncated: false,
                max_nodes: 1200,
                max_depth: 64,
                max_depth_reached: false,
            },
            screenshot: None,
            screenshot_error: None,
            elements: indexes
                .iter()
                .map(|index| ElementRecord {
                    index: *index,
                    role: "push button".to_string(),
                    name: format!("Button {index}"),
                    value: None,
                    actions: vec!["Press".to_string()],
                    frame: None,
                    path: vec![*index],
                    signature: format!("sig{index}"),
                    redacted: false,
                })
                .collect(),
        }
    }

    #[test]
    fn a_remembered_element_is_found_by_its_index() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[0, 4, 9]));
        let (element, window_index) = resolve_element("ws1", &app(10), None, 4).unwrap();
        assert_eq!(element.name, "Button 4");
        assert_eq!(element.path, vec![4]);
        assert_eq!(window_index, 0);
    }

    /// Compaction leaves gaps, so an index that was never handed out has to be
    /// refused rather than treated as a position in the list.
    #[test]
    fn an_index_that_was_never_handed_out_is_refused() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[0, 4, 9]));
        let error = resolve_element("ws1", &app(10), None, 1).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::ElementNotFound);
        assert!(error.message.contains("sparse"));
    }

    #[test]
    fn acting_without_having_read_anything_says_to_read_first() {
        let _guard = take_for_test();
        let error = resolve_element("ws1", &app(99), None, 0).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::ElementNotFound);
        assert!(error.message.contains("Read the app state first"));
    }

    /// Two callers in different workspaces must not resolve against each other's
    /// observation: that is a click on the wrong element, not an error.
    #[test]
    fn namespaces_stay_separate() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[0]));
        assert!(resolve_element("ws1", &app(10), None, 0).is_ok());
        assert!(resolve_element("ws2", &app(10), None, 0).is_err());
    }

    /// Re-reading a window retires the indexes it just superseded, by id as well
    /// as by name. Keeping the old observation addressable would let an agent act
    /// on numbers it has already been told to stop using.
    #[test]
    fn re_reading_a_window_retires_the_previous_observation_entirely() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[7]));
        remember("ws1", &snapshot("s2", 10, &[8]));
        assert!(resolve_element("ws1", &app(10), None, 8).is_ok());
        assert!(resolve_element("ws1", &app(10), None, 7).is_err());
        assert!(resolve_element("ws1", &app(10), Some("s1"), 7).is_err());
    }

    /// Pinning by id is how a caller keeps two windows apart, since each window
    /// is remembered separately.
    #[test]
    fn an_observation_of_another_window_stays_addressable_by_id() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[7]));
        remember("ws1", &snapshot("s2", 11, &[8]));
        assert!(resolve_element("ws1", &app(10), Some("s1"), 7).is_ok());
        assert!(resolve_element("ws1", &app(11), Some("s2"), 8).is_ok());
    }

    #[test]
    fn an_unknown_observation_id_is_refused() {
        let _guard = take_for_test();
        remember("ws1", &snapshot("s1", 10, &[0]));
        let error = resolve_element("ws1", &app(10), Some("gone"), 0).unwrap_err();
        assert_eq!(error.code, ComputerErrorCode::ElementNotFound);
        assert!(error.message.contains("no longer held"));
    }
}
