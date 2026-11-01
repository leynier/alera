//! Antigravity lists its models only from a short-lived ACP session, which
//! takes seconds, so each instance's list is probed once at a time and kept
//! for 30 minutes. The probe runs detached with its own budget: a catalog
//! request that stops waiting does not stop it.

use std::collections::HashMap;
use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use serde_json::Value;
use tokio::sync::{watch, Mutex};

use super::discovery;

const MODELS_TTL: Duration = Duration::from_secs(30 * 60);
const PROBE_BUDGET: Duration = Duration::from_secs(90);

type Outcome = Option<Result<Vec<Value>, String>>;

struct Entry {
    id: u64,
    started: Instant,
    outcome: watch::Receiver<Outcome>,
}

fn cache() -> &'static Mutex<HashMap<String, Entry>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Entry>>> = OnceLock::new();
    CACHE.get_or_init(Default::default)
}

/// The instance's models, from the cache or a probe already running, else
/// from a new probe.
pub(super) async fn models(
    key: String,
    config: alera_provider_antigravity::AntigravityProviderConfig,
) -> Result<Vec<Value>, String> {
    let outcome = probe_once(key, PROBE_BUDGET, move || async move {
        alera_provider_antigravity::discover_models(config)
            .await
            .map(|models| discovery::antigravity(&models))
            .map_err(|_| "Antigravity model discovery failed.".to_owned())
    })
    .await;
    wait(outcome).await
}

/// The models of a finished, successful probe that is still fresh.
pub(super) async fn cached(key: &str) -> Option<Vec<Value>> {
    let cache = cache().lock().await;
    let entry = cache
        .get(key)
        .filter(|entry| entry.started.elapsed() < MODELS_TTL)?;
    let outcome = entry.outcome.borrow().clone();
    outcome.and_then(Result::ok)
}

pub(super) async fn probe_once<F, P>(
    key: String,
    budget: Duration,
    probe: F,
) -> watch::Receiver<Outcome>
where
    F: FnOnce() -> P,
    P: Future<Output = Result<Vec<Value>, String>> + Send + 'static,
{
    static NEXT_ID: AtomicU64 = AtomicU64::new(0);
    let mut entries = cache().lock().await;
    entries.retain(|_, entry| entry.started.elapsed() < MODELS_TTL);
    if let Some(entry) = entries.get(&key) {
        return entry.outcome.clone();
    }
    let (sender, receiver) = watch::channel(None);
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    entries.insert(
        key.clone(),
        Entry {
            id,
            started: Instant::now(),
            outcome: receiver.clone(),
        },
    );
    drop(entries);
    let probe = probe();
    tokio::spawn(async move {
        let outcome = tokio::time::timeout(budget, probe)
            .await
            .unwrap_or_else(|_| Err("Antigravity model discovery timed out.".into()));
        if outcome.is_err() {
            let mut entries = cache().lock().await;
            if entries.get(&key).is_some_and(|entry| entry.id == id) {
                entries.remove(&key);
            }
        }
        let _ = sender.send(Some(outcome));
    });
    receiver
}

pub(super) async fn wait(mut outcome: watch::Receiver<Outcome>) -> Result<Vec<Value>, String> {
    match outcome.wait_for(Option::is_some).await {
        Ok(outcome) => outcome.clone().expect("finished probe"),
        Err(_) => Err("Antigravity model discovery stopped.".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;

    fn key() -> String {
        format!("antigravity-test-{}", uuid::Uuid::new_v4())
    }

    #[tokio::test]
    async fn concurrent_requests_share_one_probe_and_its_result_is_cached() {
        let key = key();
        let runs = Arc::new(AtomicUsize::new(0));
        let probe = |runs: Arc<AtomicUsize>| {
            move || async move {
                runs.fetch_add(1, Ordering::SeqCst);
                tokio::time::sleep(Duration::from_millis(50)).await;
                Ok(vec![json!({"id":"gemini","providerDefault":true})])
            }
        };
        let first = probe_once(key.clone(), PROBE_BUDGET, probe(runs.clone())).await;
        let second = probe_once(key.clone(), PROBE_BUDGET, probe(runs.clone())).await;
        assert!(cached(&key).await.is_none());
        assert_eq!(wait(first).await.unwrap()[0]["id"], "gemini");
        assert_eq!(wait(second).await.unwrap()[0]["id"], "gemini");
        assert_eq!(runs.load(Ordering::SeqCst), 1);
        assert_eq!(cached(&key).await.unwrap()[0]["id"], "gemini");
    }

    #[tokio::test]
    async fn a_failed_or_slow_probe_is_evicted_so_the_next_request_probes_again() {
        let key = key();
        let failed = probe_once(key.clone(), PROBE_BUDGET, || async {
            Err("Antigravity model discovery failed.".to_owned())
        })
        .await;
        assert!(wait(failed).await.is_err());
        assert!(cache().lock().await.get(&key).is_none());
        let slow = probe_once(key.clone(), Duration::from_millis(10), || async {
            tokio::time::sleep(Duration::from_secs(5)).await;
            Ok(Vec::new())
        })
        .await;
        assert_eq!(
            wait(slow).await.unwrap_err(),
            "Antigravity model discovery timed out."
        );
        let retried = probe_once(key.clone(), PROBE_BUDGET, || async {
            Ok(vec![json!({"id":"claude"})])
        })
        .await;
        assert_eq!(wait(retried).await.unwrap()[0]["id"], "claude");
    }
}
