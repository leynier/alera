//! Resumable pull request details generations.
//!
//! A generation can outlast the caller: AI Assist allows up to ten minutes,
//! while an MCP client abandons a call after about one. A request that names
//! a wait therefore starts the generation as a job owned by the runtime, not
//! by the connection, and answers `running` when the wait ends first. Calling
//! again with the same retry key attaches to that job, or reads its result,
//! instead of generating again. Results stay for [`RESULT_TTL`]; a failure is
//! reported once and then forgotten, so the next call with that key retries.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use serde_json::Value;
use tokio::sync::watch;

use crate::terminal_host::host_error::{HostError, HostResult};

/// How long a finished result can still be read with its retry key.
pub(super) const RESULT_TTL: Duration = Duration::from_secs(15 * 60);
/// Jobs kept at once, running or finished. Finished ones make room first.
pub(super) const JOB_CAPACITY: usize = 64;

pub(super) type Outcome = HostResult<Value>;
type OutcomeReceiver = watch::Receiver<Option<Outcome>>;

pub(super) struct GenerationJobs {
    state: Mutex<JobsState>,
    ttl: Duration,
    capacity: usize,
}

#[derive(Default)]
struct JobsState {
    jobs: HashMap<String, Job>,
    next_serial: u64,
}

struct Job {
    /// Tells a late completion apart from a newer job under the same key.
    serial: u64,
    outcome: watch::Sender<Option<Outcome>>,
    finished_at: Option<Instant>,
}

pub(super) enum Attachment {
    /// A job under this key already exists; this receiver follows it.
    Joined(OutcomeReceiver),
    /// No job existed: the caller runs one and reports through `completion`.
    Started {
        outcome: OutcomeReceiver,
        completion: JobCompletion,
    },
}

/// Reports a job's outcome. Dropping it unreported, as an aborted or
/// panicking job does, reports a failure so the key does not stay running.
pub(super) struct JobCompletion {
    jobs: Arc<GenerationJobs>,
    key: String,
    serial: u64,
    reported: bool,
}

impl GenerationJobs {
    pub(super) fn new(ttl: Duration, capacity: usize) -> Self {
        Self {
            state: Mutex::new(JobsState::default()),
            ttl,
            capacity,
        }
    }

    fn lock(&self) -> HostResult<MutexGuard<'_, JobsState>> {
        self.state
            .lock()
            .map_err(|_| HostError::state("AI Assist state is unavailable."))
    }

    pub(super) fn attach(self: &Arc<Self>, key: &str, now: Instant) -> HostResult<Attachment> {
        let mut state = self.lock()?;
        let ttl = self.ttl;
        state.jobs.retain(|_, job| {
            job.finished_at
                .is_none_or(|finished| now.saturating_duration_since(finished) < ttl)
        });
        if let Some(job) = state.jobs.get(key) {
            let receiver = job.outcome.subscribe();
            let failed = matches!(&*receiver.borrow(), Some(Err(_)));
            if failed {
                state.jobs.remove(key);
            }
            return Ok(Attachment::Joined(receiver));
        }
        if state.jobs.len() >= self.capacity {
            let oldest = state
                .jobs
                .iter()
                .filter_map(|(key, job)| Some((job.finished_at?, key.clone())))
                .min();
            let Some((_, oldest)) = oldest else {
                return Err(HostError::state(
                    "Too many pull request details are being generated. Try again when one finishes.",
                ));
            };
            state.jobs.remove(&oldest);
        }
        let serial = state.next_serial;
        state.next_serial += 1;
        let (sender, receiver) = watch::channel(None);
        state.jobs.insert(
            key.to_owned(),
            Job {
                serial,
                outcome: sender,
                finished_at: None,
            },
        );
        Ok(Attachment::Started {
            outcome: receiver,
            completion: JobCompletion {
                jobs: self.clone(),
                key: key.to_owned(),
                serial,
                reported: false,
            },
        })
    }

    /// Whether a job is still generating, which keeps the runtime alive.
    pub(super) fn has_running(&self) -> bool {
        self.lock()
            .is_ok_and(|state| state.jobs.values().any(|job| job.finished_at.is_none()))
    }

    fn finish(&self, key: &str, serial: u64, outcome: Outcome, now: Instant) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        let Some(job) = state.jobs.get_mut(key).filter(|job| job.serial == serial) else {
            return;
        };
        let failed = outcome.is_err();
        job.outcome.send_replace(Some(outcome));
        job.finished_at = Some(now);
        // A caller that is waiting receives the failure now, so the key is free
        // for a retry. Without one, the next call with the key receives it.
        if failed && job.outcome.receiver_count() > 0 {
            state.jobs.remove(key);
        }
    }
}

impl JobCompletion {
    pub(super) fn finish(mut self, outcome: Outcome) {
        self.report(outcome);
    }

    fn report(&mut self, outcome: Outcome) {
        if !self.reported {
            self.reported = true;
            self.jobs
                .finish(&self.key, self.serial, outcome, Instant::now());
        }
    }
}

impl Drop for JobCompletion {
    fn drop(&mut self) {
        self.report(Err(HostError::state(
            "Pull request details generation stopped before it finished.",
        )));
    }
}

/// Attaches to the job under `key`, or starts `generate` as a new one that
/// runs on its own task, then waits up to `wait`. `None` means the job is
/// still running; it keeps running whether or not anyone calls again.
pub(super) async fn attach_or_start<F, Fut>(
    jobs: &Arc<GenerationJobs>,
    key: &str,
    wait: Duration,
    generate: F,
) -> HostResult<Option<Value>>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = Outcome> + Send + 'static,
{
    let mut outcome = match jobs.attach(key, Instant::now())? {
        Attachment::Joined(outcome) => outcome,
        Attachment::Started {
            outcome,
            completion,
        } => {
            let job = generate();
            tokio::spawn(async move {
                let result = job.await;
                completion.finish(result);
            });
            outcome
        }
    };
    match tokio::time::timeout(wait, wait_for_outcome(&mut outcome)).await {
        Ok(result) => result.map(Some),
        Err(_) => Ok(None),
    }
}

async fn wait_for_outcome(receiver: &mut OutcomeReceiver) -> Outcome {
    loop {
        if let Some(outcome) = receiver.borrow_and_update().clone() {
            return outcome;
        }
        if receiver.changed().await.is_err() {
            return receiver.borrow().clone().unwrap_or_else(|| {
                Err(HostError::state(
                    "Pull request details generation stopped before it finished.",
                ))
            });
        }
    }
}

pub(super) fn pull_request_details_jobs() -> &'static Arc<GenerationJobs> {
    static JOBS: OnceLock<Arc<GenerationJobs>> = OnceLock::new();
    JOBS.get_or_init(|| Arc::new(GenerationJobs::new(RESULT_TTL, JOB_CAPACITY)))
}

#[cfg(test)]
#[path = "ai_assist_pull_request_details_jobs_tests.rs"]
mod tests;
