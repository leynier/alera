use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};

use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};

type Callback = Box<dyn FnMut(notify::Result<Event>) + Send>;
type Subscribers = Arc<Mutex<Vec<Weak<Subscriber>>>>;

struct Subscriber {
    paths: Mutex<HashSet<PathBuf>>,
    callback: Mutex<Callback>,
}

struct PhysicalWatcher {
    watcher: RecommendedWatcher,
    references: HashMap<PathBuf, usize>,
}

struct CheckoutWatcher {
    physical: Mutex<PhysicalWatcher>,
    subscribers: Subscribers,
}

static CHECKOUTS: OnceLock<Mutex<HashMap<PathBuf, Weak<CheckoutWatcher>>>> = OnceLock::new();

pub(super) struct SharedPulseWatcher {
    checkout: Arc<CheckoutWatcher>,
    subscriber: Arc<Subscriber>,
}

fn lock_error() -> notify::Error {
    notify::Error::generic("Terminal Pulse shared watcher lock failed")
}

impl SharedPulseWatcher {
    pub(super) fn new(
        root: &Path,
        callback: impl FnMut(notify::Result<Event>) + Send + 'static,
        config: Config,
    ) -> notify::Result<Self> {
        let root = dunce::canonicalize(root).map_err(notify::Error::io)?;
        let mut checkouts = CHECKOUTS
            .get_or_init(Mutex::default)
            .lock()
            .map_err(|_| lock_error())?;
        checkouts.retain(|_, checkout| checkout.strong_count() > 0);
        let checkout = match checkouts.get(&root).and_then(Weak::upgrade) {
            Some(checkout) => checkout,
            None => {
                let subscribers = Subscribers::default();
                let recipients = Arc::clone(&subscribers);
                let watcher = RecommendedWatcher::new(
                    move |event: notify::Result<Event>| {
                        // Never hold membership locks while invoking Git callbacks or
                        // waiting for native watch updates on another thread.
                        let recipients = recipients
                            .lock()
                            .unwrap_or_else(|error| error.into_inner())
                            .iter()
                            .filter_map(Weak::upgrade)
                            .collect::<Vec<_>>();
                        for recipient in recipients {
                            let relevant = match &event {
                                Err(_) => true,
                                Ok(event) if event.need_rescan() => true,
                                Ok(event) => {
                                    let paths =
                                        recipient.paths.lock().unwrap_or_else(|e| e.into_inner());
                                    event.paths.iter().any(|path| {
                                        paths.contains(path)
                                            || path
                                                .parent()
                                                .is_some_and(|parent| paths.contains(parent))
                                    })
                                }
                            };
                            if relevant {
                                let copy = match &event {
                                    Ok(event) => Ok(event.clone()),
                                    Err(error) => Err(notify::Error::generic(&error.to_string())),
                                };
                                if let Ok(mut callback) = recipient.callback.lock() {
                                    callback(copy);
                                }
                            }
                        }
                    },
                    config,
                )?;
                let checkout = Arc::new(CheckoutWatcher {
                    physical: Mutex::new(PhysicalWatcher {
                        watcher,
                        references: HashMap::new(),
                    }),
                    subscribers,
                });
                checkouts.insert(root, Arc::downgrade(&checkout));
                checkout
            }
        };
        let subscriber = Arc::new(Subscriber {
            paths: Mutex::default(),
            callback: Mutex::new(Box::new(callback)),
        });
        let mut subscribers = checkout.subscribers.lock().map_err(|_| lock_error())?;
        subscribers.retain(|subscriber| subscriber.strong_count() > 0);
        subscribers.push(Arc::downgrade(&subscriber));
        drop(subscribers);
        Ok(Self {
            checkout,
            subscriber,
        })
    }

    pub(super) fn watch(&mut self, path: &Path, mode: RecursiveMode) -> notify::Result<()> {
        if mode != RecursiveMode::NonRecursive {
            return Err(notify::Error::generic(
                "Terminal Pulse requires non-recursive watches",
            ));
        }
        let mut physical = self.checkout.physical.lock().map_err(|_| lock_error())?;
        {
            let mut paths = self.subscriber.paths.lock().map_err(|_| lock_error())?;
            if !paths.insert(path.to_path_buf()) {
                return Ok(());
            }
        }
        if !physical.references.contains_key(path) {
            if let Err(error) = physical.watcher.watch(path, mode) {
                self.subscriber
                    .paths
                    .lock()
                    .map_err(|_| lock_error())?
                    .remove(path);
                return Err(error);
            }
        }
        *physical.references.entry(path.to_path_buf()).or_default() += 1;
        Ok(())
    }

    pub(super) fn unwatch(&mut self, path: &Path) -> notify::Result<()> {
        let mut physical = self.checkout.physical.lock().map_err(|_| lock_error())?;
        let removed = self
            .subscriber
            .paths
            .lock()
            .map_err(|_| lock_error())?
            .remove(path);
        if !removed {
            return Ok(());
        }
        if let Some(count) = physical.references.get_mut(path) {
            *count -= 1;
            if *count == 0 {
                physical.references.remove(path);
                return physical.watcher.unwatch(path);
            }
        }
        Ok(())
    }
}

impl Drop for SharedPulseWatcher {
    fn drop(&mut self) {
        let paths = self
            .subscriber
            .paths
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        for path in paths {
            let _ = self.unwatch(&path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::time::{Duration, Instant};

    #[test]
    fn shared_checkout_watches_survive_one_tasks_removal() {
        let root = tempfile::tempdir().unwrap();
        let root = dunce::canonicalize(root.path()).unwrap();
        let config = Config::default().with_follow_symlinks(false);
        let (first_tx, first_rx) = mpsc::channel();
        let (second_tx, second_rx) = mpsc::channel();
        let mut first = SharedPulseWatcher::new(
            &root,
            move |event| {
                let _ = first_tx.send(event);
            },
            config,
        )
        .unwrap();
        let mut second = SharedPulseWatcher::new(
            &root.join("."),
            move |event| {
                let _ = second_tx.send(event);
            },
            config,
        )
        .unwrap();
        assert!(Arc::ptr_eq(&first.checkout, &second.checkout));
        first.watch(&root, RecursiveMode::NonRecursive).unwrap();
        second.watch(&root, RecursiveMode::NonRecursive).unwrap();
        first.watch(&root, RecursiveMode::NonRecursive).unwrap();
        assert_eq!(first.checkout.physical.lock().unwrap().references[&root], 2);
        let before = root.join("before.txt");
        std::fs::write(&before, "both tasks").unwrap();
        await_path(&first_rx, &before);
        await_path(&second_rx, &before);
        let weak = Arc::downgrade(&first.checkout);
        drop(first);
        assert_eq!(
            second.checkout.physical.lock().unwrap().references[&root],
            1
        );
        let after = root.join("after.txt");
        std::fs::write(&after, "remaining task").unwrap();
        await_path(&second_rx, &after);
        drop(second);
        assert!(weak.upgrade().is_none());
    }

    #[test]
    fn failed_registration_can_be_retried_without_a_phantom_reference() {
        let root = tempfile::tempdir().unwrap();
        let missing = root.path().join("later");
        let mut watcher = SharedPulseWatcher::new(root.path(), |_| {}, Config::default()).unwrap();
        assert!(watcher
            .watch(&missing, RecursiveMode::NonRecursive)
            .is_err());
        assert!(watcher.subscriber.paths.lock().unwrap().is_empty());
        assert!(watcher
            .checkout
            .physical
            .lock()
            .unwrap()
            .references
            .is_empty());
        std::fs::create_dir(&missing).unwrap();
        watcher
            .watch(&missing, RecursiveMode::NonRecursive)
            .unwrap();
        assert_eq!(
            watcher.checkout.physical.lock().unwrap().references[&missing],
            1
        );
        watcher.unwatch(&missing).unwrap();
        assert!(watcher
            .checkout
            .physical
            .lock()
            .unwrap()
            .references
            .is_empty());
    }

    #[test]
    fn sibling_subscriptions_receive_only_their_directory_events() {
        let root = tempfile::tempdir().unwrap();
        let root = dunce::canonicalize(root.path()).unwrap();
        let left = root.join("left");
        let right = root.join("right");
        std::fs::create_dir(&left).unwrap();
        std::fs::create_dir(&right).unwrap();
        let (left_tx, left_rx) = mpsc::channel();
        let (right_tx, right_rx) = mpsc::channel();
        let mut first = SharedPulseWatcher::new(
            &root,
            move |event| {
                let _ = left_tx.send(event);
            },
            Config::default(),
        )
        .unwrap();
        let mut second = SharedPulseWatcher::new(
            &root,
            move |event| {
                let _ = right_tx.send(event);
            },
            Config::default(),
        )
        .unwrap();
        first.watch(&left, RecursiveMode::NonRecursive).unwrap();
        second.watch(&right, RecursiveMode::NonRecursive).unwrap();
        let left_file = left.join("one.txt");
        let right_file = right.join("two.txt");
        std::fs::write(&left_file, "left").unwrap();
        await_scoped_path(&left_rx, &left_file, &left);
        std::fs::write(&right_file, "right").unwrap();
        await_scoped_path(&right_rx, &right_file, &right);
        assert!(!left_rx
            .try_iter()
            .any(|event| event.unwrap().paths.contains(&right_file)));
        assert!(!right_rx
            .try_iter()
            .any(|event| event.unwrap().paths.contains(&left_file)));
        first.unwatch(&left).unwrap();
        let later_file = right.join("three.txt");
        std::fs::write(&later_file, "still watching").unwrap();
        await_scoped_path(&right_rx, &later_file, &right);
        assert_eq!(second.checkout.physical.lock().unwrap().references.len(), 1);
    }

    fn await_path(receiver: &mpsc::Receiver<notify::Result<Event>>, path: &Path) {
        await_scoped_path(receiver, path, path.parent().unwrap());
    }

    fn await_scoped_path(
        receiver: &mpsc::Receiver<notify::Result<Event>>,
        path: &Path,
        scope: &Path,
    ) {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let event = receiver
                .recv_timeout(deadline.saturating_duration_since(Instant::now()))
                .unwrap()
                .unwrap();
            assert!(event
                .paths
                .iter()
                .all(|observed| observed.starts_with(scope)));
            if event.paths.iter().any(|observed| observed == path) {
                return;
            }
        }
    }
}
