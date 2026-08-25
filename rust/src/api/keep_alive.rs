//! Session keep-alive, matching Exeora's `keepawake` usage.
//!
//! The OS lock is created on a dedicated thread and held there until disable.
//! Windows `SetThreadExecutionState` is per-thread, so creating the lock on a
//! short-lived FRB worker would drop the request when that worker returned to
//! the pool.

use std::sync::mpsc;
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};

const KEEP_ALIVE_REASON: &str = "Alera keep-alive is on";
const KEEP_ALIVE_APP_NAME: &str = "Alera";
const KEEP_ALIVE_APP_REVERSE_DOMAIN: &str = "dev.leynier.alera";

type AcquireFn = Arc<dyn Fn() -> Result<Box<dyn KeepAliveGuard>, String> + Send + Sync>;

trait KeepAliveGuard {}

impl KeepAliveGuard for keepawake::KeepAwake {}

struct KeepAliveOwner {
    stop: mpsc::Sender<()>,
    join: Option<JoinHandle<()>>,
}

struct KeepAliveController {
    acquire: AcquireFn,
    owner: Mutex<Option<KeepAliveOwner>>,
}

pub struct KeepAliveStatusDto {
    pub active: bool,
    pub system: bool,
    pub display: bool,
    pub error: Option<String>,
}

/// Enable or disable idle and display sleep prevention for this process.
pub fn set_keep_alive(enabled: bool) -> KeepAliveStatusDto {
    global_controller().set_enabled(enabled)
}

/// Current keep-alive lock state for this process.
pub fn keep_alive_status() -> KeepAliveStatusDto {
    global_controller().status()
}

fn global_controller() -> &'static KeepAliveController {
    static CONTROLLER: OnceLock<KeepAliveController> = OnceLock::new();
    CONTROLLER.get_or_init(KeepAliveController::production)
}

fn create_keep_awake() -> Result<keepawake::KeepAwake, String> {
    keepawake::Builder::default()
        .idle(true)
        .display(true)
        .reason(KEEP_ALIVE_REASON)
        .app_name(KEEP_ALIVE_APP_NAME)
        .app_reverse_domain(KEEP_ALIVE_APP_REVERSE_DOMAIN)
        .create()
        .map_err(|error| error.to_string())
}

impl KeepAliveController {
    fn production() -> Self {
        Self::new(|| create_keep_awake().map(|awake| Box::new(awake) as Box<dyn KeepAliveGuard>))
    }

    fn new(
        acquire: impl Fn() -> Result<Box<dyn KeepAliveGuard>, String> + Send + Sync + 'static,
    ) -> Self {
        Self {
            acquire: Arc::new(acquire),
            owner: Mutex::new(None),
        }
    }

    fn set_enabled(&self, enabled: bool) -> KeepAliveStatusDto {
        if enabled {
            self.enable()
        } else {
            self.disable()
        }
    }

    fn status(&self) -> KeepAliveStatusDto {
        if self.has_owner() {
            active_status(None)
        } else {
            inactive_status(None)
        }
    }

    fn has_owner(&self) -> bool {
        lock_owner(&self.owner).is_some()
    }

    fn enable(&self) -> KeepAliveStatusDto {
        let mut owner = lock_owner(&self.owner);
        if owner.is_some() {
            return active_status(None);
        }

        let (stop_tx, stop_rx) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::channel();
        let acquire = Arc::clone(&self.acquire);
        let join = match thread::Builder::new()
            .name("alera-keep-alive".to_owned())
            .spawn(move || match acquire() {
                Ok(guard) => {
                    let _ = ready_tx.send(Ok(()));
                    let _guard = guard;
                    let _ = stop_rx.recv();
                }
                Err(error) => {
                    let _ = ready_tx.send(Err(error));
                }
            }) {
            Ok(join) => join,
            Err(error) => {
                return inactive_status(Some(format!("Could not start keep-alive: {error}")))
            }
        };

        match ready_rx.recv() {
            Ok(Ok(())) => {
                *owner = Some(KeepAliveOwner {
                    stop: stop_tx,
                    join: Some(join),
                });
                active_status(None)
            }
            Ok(Err(error)) => {
                let _ = join.join();
                inactive_status(Some(error))
            }
            Err(_) => {
                let _ = join.join();
                inactive_status(Some(
                    "Keep-alive stopped before the sleep lock was ready.".to_owned(),
                ))
            }
        }
    }

    fn disable(&self) -> KeepAliveStatusDto {
        let mut owner = lock_owner(&self.owner);
        let Some(mut current) = owner.take() else {
            return inactive_status(None);
        };
        let _ = current.stop.send(());
        if let Some(join) = current.join.take() {
            let _ = join.join();
        }
        inactive_status(None)
    }
}

fn lock_owner(
    owner: &Mutex<Option<KeepAliveOwner>>,
) -> std::sync::MutexGuard<'_, Option<KeepAliveOwner>> {
    owner
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn active_status(error: Option<String>) -> KeepAliveStatusDto {
    KeepAliveStatusDto {
        active: true,
        system: true,
        display: true,
        error,
    }
}

fn inactive_status(error: Option<String>) -> KeepAliveStatusDto {
    KeepAliveStatusDto {
        active: false,
        system: false,
        display: false,
        error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct CountingGuard {
        drops: Arc<AtomicUsize>,
    }

    impl KeepAliveGuard for CountingGuard {}

    impl Drop for CountingGuard {
        fn drop(&mut self) {
            self.drops.fetch_add(1, Ordering::SeqCst);
        }
    }

    fn counting_controller(
        drops: Arc<AtomicUsize>,
        fails: Arc<AtomicUsize>,
    ) -> KeepAliveController {
        KeepAliveController::new(move || {
            if fails.load(Ordering::SeqCst) > 0 {
                fails.fetch_sub(1, Ordering::SeqCst);
                return Err("not supported".to_owned());
            }
            Ok(Box::new(CountingGuard {
                drops: Arc::clone(&drops),
            }))
        })
    }

    #[test]
    fn enable_holds_the_guard_until_disable() {
        let drops = Arc::new(AtomicUsize::new(0));
        let controller = counting_controller(Arc::clone(&drops), Arc::new(AtomicUsize::new(0)));

        let enabled = controller.set_enabled(true);
        assert!(enabled.active);
        assert!(enabled.system);
        assert!(enabled.display);
        assert_eq!(enabled.error, None);
        assert_eq!(drops.load(Ordering::SeqCst), 0);

        let disabled = controller.set_enabled(false);
        assert!(!disabled.active);
        assert_eq!(disabled.error, None);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn enable_is_idempotent_while_the_lock_is_held() {
        let drops = Arc::new(AtomicUsize::new(0));
        let controller = counting_controller(Arc::clone(&drops), Arc::new(AtomicUsize::new(0)));

        assert!(controller.set_enabled(true).active);
        assert!(controller.set_enabled(true).active);
        assert_eq!(drops.load(Ordering::SeqCst), 0);

        assert!(!controller.set_enabled(false).active);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn disable_is_safe_when_already_off() {
        let controller =
            counting_controller(Arc::new(AtomicUsize::new(0)), Arc::new(AtomicUsize::new(0)));
        let status = controller.set_enabled(false);
        assert!(!status.active);
        assert_eq!(status.error, None);
    }

    #[test]
    fn acquire_failure_leaves_keep_alive_inactive() {
        let drops = Arc::new(AtomicUsize::new(0));
        let controller = counting_controller(Arc::clone(&drops), Arc::new(AtomicUsize::new(1)));

        let failed = controller.set_enabled(true);
        assert!(!failed.active);
        assert_eq!(failed.error.as_deref(), Some("not supported"));
        assert_eq!(drops.load(Ordering::SeqCst), 0);

        let retry = controller.set_enabled(true);
        assert!(retry.active);
        assert_eq!(retry.error, None);

        assert!(!controller.set_enabled(false).active);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
}
