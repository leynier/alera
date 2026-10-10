use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::json;
use tokio::sync::oneshot;

use super::*;

const SHORT: Duration = Duration::from_millis(20);
const LONG: Duration = Duration::from_secs(5);

fn jobs(capacity: usize) -> Arc<GenerationJobs> {
    Arc::new(GenerationJobs::new(Duration::from_secs(60), capacity))
}

fn started(attachment: Attachment) -> (OutcomeReceiver, JobCompletion) {
    match attachment {
        Attachment::Started {
            outcome,
            completion,
        } => (outcome, completion),
        Attachment::Joined(_) => panic!("expected a new job"),
    }
}

fn joined(attachment: Attachment) -> OutcomeReceiver {
    match attachment {
        Attachment::Joined(outcome) => outcome,
        Attachment::Started { .. } => panic!("expected the existing job"),
    }
}

/// A generation that finishes when `release` fires, counting its starts.
fn gated(
    starts: &Arc<AtomicUsize>,
    release: oneshot::Receiver<()>,
) -> impl FnOnce() -> std::pin::Pin<Box<dyn Future<Output = Outcome> + Send>> {
    let starts = starts.clone();
    move || {
        starts.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move {
            let _ = release.await;
            Ok(json!({ "title": "Add resumable details" }))
        })
    }
}

fn never_started(
    starts: &Arc<AtomicUsize>,
) -> impl FnOnce() -> std::pin::Pin<Box<dyn Future<Output = Outcome> + Send>> {
    let starts = starts.clone();
    move || {
        starts.fetch_add(1, Ordering::SeqCst);
        Box::pin(async { Err(HostError::state("started twice")) })
    }
}

#[tokio::test]
async fn a_job_keeps_running_after_its_caller_gives_up_and_a_retry_reads_it() {
    let jobs = jobs(4);
    let starts = Arc::new(AtomicUsize::new(0));
    let (release, gate) = oneshot::channel();
    let first = attach_or_start(&jobs, "key", SHORT, gated(&starts, gate))
        .await
        .unwrap();
    assert_eq!(first, None, "the wait ends before the generation");
    assert!(jobs.has_running());

    // The caller is gone; the job finishes on its own task.
    release.send(()).unwrap();
    let retry = attach_or_start(&jobs, "key", LONG, never_started(&starts))
        .await
        .unwrap();
    assert_eq!(retry, Some(json!({ "title": "Add resumable details" })));
    assert_eq!(starts.load(Ordering::SeqCst), 1);
    assert!(!jobs.has_running());

    // The finished result stays readable without generating again.
    let again = attach_or_start(&jobs, "key", SHORT, never_started(&starts))
        .await
        .unwrap();
    assert_eq!(again, Some(json!({ "title": "Add resumable details" })));
    assert_eq!(starts.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn a_second_caller_attaches_to_the_running_job() {
    let jobs = jobs(4);
    let starts = Arc::new(AtomicUsize::new(0));
    let (release, gate) = oneshot::channel();
    let first = {
        let jobs = jobs.clone();
        let generate = gated(&starts, gate);
        tokio::spawn(async move { attach_or_start(&jobs, "key", LONG, generate).await })
    };
    while !jobs.has_running() {
        tokio::task::yield_now().await;
    }
    let second = {
        let jobs = jobs.clone();
        let generate = never_started(&starts);
        tokio::spawn(async move { attach_or_start(&jobs, "key", LONG, generate).await })
    };
    tokio::task::yield_now().await;
    release.send(()).unwrap();
    let expected = Some(json!({ "title": "Add resumable details" }));
    assert_eq!(first.await.unwrap().unwrap(), expected);
    assert_eq!(second.await.unwrap().unwrap(), expected);
    assert_eq!(starts.load(Ordering::SeqCst), 1);
}

#[test]
fn finished_results_expire_after_the_ttl() {
    let jobs = Arc::new(GenerationJobs::new(Duration::from_secs(60), 4));
    let now = Instant::now();
    let (_outcome, completion) = started(jobs.attach("key", now).unwrap());
    completion.finish(Ok(json!({ "title": "x" })));
    let receiver = joined(jobs.attach("key", now).unwrap());
    assert!(matches!(&*receiver.borrow(), Some(Ok(value)) if value == &json!({ "title": "x" })));
    let later = Instant::now() + Duration::from_secs(61);
    let (_outcome, _completion) = started(jobs.attach("key", later).unwrap());
}

#[test]
fn a_failure_is_reported_once_then_the_key_retries() {
    let jobs = jobs(4);
    let now = Instant::now();
    let (outcome, completion) = started(jobs.attach("key", now).unwrap());
    drop(outcome);
    completion.finish(Err(HostError::state("AI Assist timed out.")));
    let receiver = joined(jobs.attach("key", now).unwrap());
    assert!(
        matches!(&*receiver.borrow(), Some(Err(error)) if error.to_string() == "AI Assist timed out.")
    );
    let (_outcome, _completion) = started(jobs.attach("key", now).unwrap());
}

#[test]
fn a_failure_with_a_waiting_caller_frees_the_key_at_once() {
    let jobs = jobs(4);
    let now = Instant::now();
    let (outcome, completion) = started(jobs.attach("key", now).unwrap());
    completion.finish(Err(HostError::state("boom")));
    assert!(matches!(&*outcome.borrow(), Some(Err(_))));
    let (_outcome, _completion) = started(jobs.attach("key", now).unwrap());
}

#[test]
fn a_job_dropped_without_an_outcome_reports_a_failure() {
    let jobs = jobs(4);
    let (outcome, completion) = started(jobs.attach("key", Instant::now()).unwrap());
    assert!(jobs.has_running());
    drop(completion);
    assert!(!jobs.has_running());
    assert!(matches!(&*outcome.borrow(), Some(Err(_))));
}

#[test]
fn capacity_evicts_the_oldest_finished_job_and_refuses_when_all_run() {
    let jobs = jobs(2);
    let now = Instant::now();
    let (_a, a) = started(jobs.attach("a", now).unwrap());
    let (_b, _b_running) = started(jobs.attach("b", now).unwrap());
    assert!(
        jobs.attach("c", now).is_err(),
        "both jobs are still running"
    );
    a.finish(Ok(json!({})));
    let (_c, _c_running) = started(jobs.attach("c", now).unwrap());
    // "a" made room for "c", and with both remaining jobs running it cannot
    // start over yet.
    assert!(jobs.attach("a", now).is_err());
}

#[test]
fn a_late_completion_does_not_overwrite_a_newer_job() {
    let jobs = Arc::new(GenerationJobs::new(Duration::from_millis(0), 4));
    let now = Instant::now();
    let (_old, old) = started(jobs.attach("key", now).unwrap());
    // Simulate an expired entry replaced by a new job under the same key.
    jobs.lock().unwrap().jobs.remove("key");
    let (fresh, _fresh_running) = started(jobs.attach("key", now).unwrap());
    old.finish(Ok(json!({ "title": "stale" })));
    assert!(fresh.borrow().is_none());
    assert!(jobs.has_running());
}
