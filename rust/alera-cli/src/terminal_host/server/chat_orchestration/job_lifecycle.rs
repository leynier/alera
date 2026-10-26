use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use tokio::task::{AbortHandle, Id, JoinHandle};
use tokio::time::Instant;

const SHUTDOWN_DEADLINE: Duration = Duration::from_secs(5);

#[derive(Default)]
struct JobState {
    closed: bool,
    handles: HashMap<Id, JoinHandle<()>>,
}

#[derive(Default)]
pub(super) struct OrchestrationJobs {
    state: Mutex<JobState>,
    shutdown_gate: tokio::sync::Mutex<()>,
}

struct CompletedJob {
    jobs: Arc<OrchestrationJobs>,
    id: Arc<OnceLock<Id>>,
}

struct StoppingJobs<'a> {
    jobs: &'a OrchestrationJobs,
    handles: HashMap<Id, JoinHandle<()>>,
}

impl Drop for StoppingJobs<'_> {
    fn drop(&mut self) {
        self.handles.retain(|_, handle| !handle.is_finished());
        self.jobs
            .state
            .lock()
            .expect("orchestration job admission lock")
            .handles
            .extend(std::mem::take(&mut self.handles));
    }
}

pub(super) struct RequestJob(pub(super) AbortHandle);

impl Drop for RequestJob {
    fn drop(&mut self) {
        self.0.abort();
    }
}

impl Drop for CompletedJob {
    fn drop(&mut self) {
        if let Ok(mut state) = self.jobs.state.lock() {
            if let Some(id) = self.id.get() {
                state.handles.remove(id);
            }
        }
    }
}

impl OrchestrationJobs {
    pub(super) fn spawn<F>(self: &Arc<Self>, future: F) -> Option<AbortHandle>
    where
        F: Future<Output = ()> + Send + 'static,
    {
        let mut state = self.state.lock().expect("orchestration job admission lock");
        state.handles.retain(|_, handle| !handle.is_finished());
        if state.closed {
            return None;
        }
        let id = Arc::new(OnceLock::new());
        let completed = CompletedJob {
            jobs: self.clone(),
            id: id.clone(),
        };
        // Registration holds the same lock that completion removes from, so
        // even a job that finishes immediately cannot leave a stale handle.
        let handle = tokio::spawn(async move {
            let _completed = completed;
            future.await;
        });
        assert!(id.set(handle.id()).is_ok());
        let abort = handle.abort_handle();
        state.handles.insert(handle.id(), handle);
        Some(abort)
    }

    pub(super) fn is_closed(&self) -> bool {
        self.state
            .lock()
            .expect("orchestration job admission lock")
            .closed
    }

    pub(super) async fn shutdown(&self) -> bool {
        self.shutdown_until(Instant::now() + SHUTDOWN_DEADLINE)
            .await
    }

    async fn shutdown_until(&self, deadline: Instant) -> bool {
        let Ok(_shutdown) = tokio::time::timeout_at(deadline, self.shutdown_gate.lock()).await
        else {
            return false;
        };
        let handles = {
            let mut state = self.state.lock().expect("orchestration job admission lock");
            state.closed = true;
            std::mem::take(&mut state.handles)
        };
        // Retain ownership for a retry even if the shutdown future is dropped.
        let mut stopping = StoppingJobs {
            jobs: self,
            handles,
        };
        for handle in stopping.handles.values() {
            handle.abort();
        }
        let stopped = tokio::time::timeout_at(deadline, async {
            while let Some(id) = stopping.handles.keys().next().copied() {
                let result = stopping
                    .handles
                    .get_mut(&id)
                    .expect("owned orchestration job")
                    .await;
                stopping.handles.remove(&id);
                if let Err(error) = result {
                    if !error.is_cancelled() {
                        tracing::warn!("orchestration job stopped with an error: {error}");
                    }
                }
            }
        })
        .await
        .is_ok();
        if stopped {
            return true;
        }
        stopping.handles.retain(|_, handle| !handle.is_finished());
        stopping.handles.is_empty()
    }

    #[cfg(test)]
    pub(super) fn retained_handles(&self) -> usize {
        self.state.lock().unwrap().handles.len()
    }
}

#[cfg(test)]
#[path = "job_lifecycle_tests.rs"]
mod tests;
