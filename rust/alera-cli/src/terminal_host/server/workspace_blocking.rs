use std::sync::{Arc, OnceLock};

use tokio::sync::Semaphore;

use crate::terminal_host::host_error::{HostError, HostResult};

const WORKSPACE_BLOCKING_CONCURRENCY: usize = 4;

pub(super) async fn spawn_blocking_workspace<T: Send + 'static>(
    operation: &'static str,
    task: impl FnOnce() -> HostResult<T> + Send + 'static,
) -> HostResult<T> {
    let permit = workspace_blocking_permits()
        .try_acquire_owned()
        .map_err(|_| HostError::state(format!("{operation} is busy; retry later.")))?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        task()
    })
    .await
    .map_err(|error| HostError::state(format!("{operation} failed: {error}")))?
}

fn workspace_blocking_permits() -> Arc<Semaphore> {
    Arc::clone(
        WORKSPACE_BLOCKING_PERMITS
            .get_or_init(|| Arc::new(Semaphore::new(WORKSPACE_BLOCKING_CONCURRENCY))),
    )
}

static WORKSPACE_BLOCKING_PERMITS: OnceLock<Arc<Semaphore>> = OnceLock::new();
