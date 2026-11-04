use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};

use tokio::sync::{Mutex as AsyncMutex, OwnedMutexGuard};

#[derive(PartialEq, Eq, Hash)]
struct RequestIdentity {
    scope: String,
    verb: String,
    request_id: String,
}

type RequestLocks = HashMap<RequestIdentity, Weak<AsyncMutex<()>>>;

/// Serializes one receipt identity while allowing cancellation and unrelated
/// work to proceed during external workspace preparation.
#[derive(Default)]
pub(super) struct RequestAdmission {
    requests: Mutex<RequestLocks>,
}

impl RequestAdmission {
    pub(super) async fn enter(
        &self,
        scope: &str,
        verb: &str,
        request_id: &str,
    ) -> OwnedMutexGuard<()> {
        let mutex = {
            let mut requests = self.requests.lock().expect("request admission lock");
            requests.retain(|_, mutex| mutex.strong_count() > 0);
            let entry = requests
                .entry(RequestIdentity {
                    scope: scope.to_owned(),
                    verb: verb.to_owned(),
                    request_id: request_id.to_owned(),
                })
                .or_default();
            if let Some(mutex) = entry.upgrade() {
                mutex
            } else {
                let mutex = Arc::new(AsyncMutex::new(()));
                *entry = Arc::downgrade(&mutex);
                mutex
            }
        };
        mutex.lock_owned().await
    }
}
