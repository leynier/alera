use std::collections::HashMap;

use super::super::actor_test_harness::test_actor;
use crate::terminal_host::session::Session;

#[tokio::test]
async fn cold_terminal_has_no_history_barrier() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    assert!(actor.await_output_writes("new-session").await);
}

#[tokio::test]
async fn deferred_termination_retains_then_releases_the_session_after_storage_recovers() {
    use std::time::Duration;
    let dir = tempfile::tempdir().unwrap();
    let session = Session::driver_test_stub("closing", 80, 24);
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("closing".to_string(), session)]),
    )
    .await;
    let (release, wait) = tokio::sync::oneshot::channel();
    let job = tokio::spawn(async move { wait.await.map_err(|error| error.to_string()) });
    actor
        .sessions
        .get_mut("closing")
        .unwrap()
        .begin_checkpoint_job(job);
    actor.terminate_sessions(vec!["closing".to_string()]).await;
    assert!(actor.sessions["closing"].termination_requested());
    release.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while let Some(session) = actor.sessions.get("closing") {
            let generation = session.durable_output_batch_generation();
            actor
                .handle_durable_output_batch_tick("closing".to_string(), generation)
                .await;
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("pending termination must finish when storage recovers");
    assert!(actor.history_writers.is_empty());
}

#[tokio::test]
async fn configure_waits_for_ambiguous_history_retry_before_trimming() {
    use crate::terminal_host::protocol::TerminalHostConfig;
    use std::time::Duration;

    let dir = tempfile::tempdir().unwrap();
    let mut session = Session::driver_test_stub("retry", 80, 24);
    session.append_output(b"abcdef");
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("retry".to_string(), session)]),
    )
    .await;
    actor
        .store
        .upsert(actor.sessions["retry"].checkpoint_snapshot())
        .await
        .unwrap();
    // The commit succeeded, but the caller still owns the batch for retry.
    actor
        .store
        .append_output("retry", 0, b"abcdef")
        .await
        .unwrap();
    let (release, wait) = tokio::sync::oneshot::channel();
    let job = tokio::spawn(async move { wait.await.map_err(|error| error.to_string()) });
    assert!(actor
        .sessions
        .get_mut("retry")
        .unwrap()
        .begin_checkpoint_job(job));
    actor
        .apply_config(TerminalHostConfig {
            scrollback_bytes: 3,
            ..Default::default()
        })
        .await;
    tokio::time::sleep(Duration::from_millis(30)).await;
    assert_eq!(
        actor
            .store
            .read("retry", usize::MAX)
            .await
            .unwrap()
            .unwrap()
            .buffer,
        b"abcdef"
    );
    release.send(()).unwrap();
    tokio::task::yield_now().await;
    actor.collect_checkpoint_completion("retry").await;
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            actor.flush_durable_output_batch("retry").await;
            if actor.await_output_writes("retry").await {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("idempotent history retry must recover before trimming");
    assert_eq!(actor.sessions["retry"].durable_output_failure_count(), 0);
    actor.immediate_checkpoint("retry").await;
    tokio::time::timeout(Duration::from_secs(2), async {
        while !actor.await_output_writes("retry").await {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("serialized checkpoint must complete");
    assert_eq!(
        actor
            .store
            .read("retry", usize::MAX)
            .await
            .unwrap()
            .unwrap()
            .buffer,
        b"def"
    );
}

#[tokio::test]
async fn shutdown_keeps_session_when_checkpoint_storage_is_pending_then_recovers() {
    let dir = tempfile::tempdir().expect("temporary runtime directory");
    let session = Session::driver_test_stub("pending", 80, 24);
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("pending".to_string(), session)]),
    )
    .await;
    let (release_tx, release_rx) = tokio::sync::oneshot::channel();
    let job = tokio::spawn(async move {
        release_rx
            .await
            .map_err(|error| format!("checkpoint release failed: {error}"))?;
        Ok(())
    });
    assert!(actor
        .sessions
        .get_mut("pending")
        .expect("session exists")
        .begin_checkpoint_job(job));

    actor.dispose().await;
    assert!(
        !actor.disposed,
        "shutdown must remain resumable while storage is pending"
    );
    assert!(actor.sessions.contains_key("pending"));

    release_tx
        .send(())
        .expect("checkpoint worker is still owned");
    tokio::task::yield_now().await;
    actor.dispose().await;
    assert!(
        actor.disposed,
        "shutdown retries after checkpoint completion"
    );
    assert!(actor.sessions.is_empty());
}

#[tokio::test]
async fn checkpoint_barrier_keeps_already_admitted_output_out_of_history_writer() {
    let dir = tempfile::tempdir().expect("temporary runtime directory");
    let session = Session::driver_test_stub("pending", 80, 24);
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("pending".to_string(), session)]),
    )
    .await;
    actor
        .sessions
        .get_mut("pending")
        .expect("session exists")
        .append_output(b"accepted before checkpoint");
    let job = tokio::spawn(std::future::pending::<Result<(), String>>());
    assert!(actor
        .sessions
        .get_mut("pending")
        .expect("session exists")
        .begin_checkpoint_job(job));

    actor.flush_durable_output_batch("pending").await;

    assert!(actor.history_writers.is_empty());
    assert_eq!(
        actor
            .sessions
            .get("pending")
            .expect("session exists")
            .durable_output_batch_len(),
        b"accepted before checkpoint".len()
    );
}

#[tokio::test]
async fn failed_checkpoint_releases_barrier_before_retrying_admitted_output() {
    let dir = tempfile::tempdir().expect("temporary runtime directory");
    let session = Session::driver_test_stub("pending", 80, 24);
    let mut actor = test_actor(
        &dir,
        HashMap::new(),
        HashMap::from([("pending".to_string(), session)]),
    )
    .await;
    actor
        .sessions
        .get_mut("pending")
        .expect("session exists")
        .append_output(b"tail accepted during failed checkpoint");
    let job = tokio::spawn(async { Err::<(), _>("injected checkpoint failure".to_string()) });
    assert!(actor
        .sessions
        .get_mut("pending")
        .expect("session exists")
        .begin_checkpoint_job(job));
    tokio::task::yield_now().await;

    actor.collect_checkpoint_completion("pending").await;
    assert!(!actor
        .sessions
        .get("pending")
        .expect("session exists")
        .checkpoint_output_blocked());

    actor.flush_durable_output_batch("pending").await;
    assert_eq!(
        actor
            .sessions
            .get("pending")
            .expect("session exists")
            .durable_output_batch_len(),
        0
    );
    assert!(actor.history_writers.contains_key("pending"));
}
