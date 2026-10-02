use super::*;
use crate::terminal_host::session::PtyEvent;
use std::future::{poll_fn, Future};
use std::pin::Pin;
use std::sync::{mpsc, Barrier};
use std::task::Poll;
use std::time::Duration;

type SendResult = Result<(), ServerInboxSendError>;

fn completion() -> ServerCommand {
    ServerCommand::AiAssistFinished {
        client_id: 7,
        request_id: 999,
        result: Ok(serde_json::json!({"ok": true})),
    }
}

fn work() -> ServerCommand {
    ServerCommand::Pty {
        session_id: "session".to_string(),
        event: PtyEvent::Output(vec![1]),
        handled: mpsc::sync_channel(0).0,
    }
}

fn fill_admission_lanes(inbox: &ServerInbox) {
    // One completion fills its byte budget so one dequeue is the only wake.
    inbox
        .send(ServerCommand::HistoryWriterReady {
            session_id: "x".repeat(SERVER_COMMAND_COMPLETION_BYTES - 1),
        })
        .expect("completion byte budget");
    for id in 0..SERVER_COMMAND_CONTROL_CAPACITY {
        inbox
            .send(ServerCommand::ClientDisconnected { id: id as u64 })
            .expect("control capacity");
    }
    for _ in 0..SERVER_COMMAND_WORK_CAPACITY {
        inbox.send(work()).expect("work capacity");
    }
    assert_eq!(
        inbox.completion_counts(),
        (1, SERVER_COMMAND_COMPLETION_BYTES)
    );
}

async fn assert_admission_pending<F: Future>(mut future: Pin<&mut F>) {
    poll_fn(|cx| {
        assert!(future.as_mut().poll(cx).is_pending());
        Poll::Ready(())
    })
    .await;
}

#[tokio::test]
async fn completion_release_wakes_async_sender_behind_ineligible_classes() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_admission_lanes(&inbox);
    let mut control =
        std::pin::pin!(inbox.send_wait(ServerCommand::ClientDisconnected { id: 999 }));
    let mut work = std::pin::pin!(inbox.send_wait(work()));
    let mut completion = std::pin::pin!(inbox.send_wait(completion()));
    assert_admission_pending(control.as_mut()).await;
    assert_admission_pending(work.as_mut()).await;
    assert_admission_pending(completion.as_mut()).await;

    assert!(matches!(
        receiver.try_recv(),
        Ok(ServerCommand::HistoryWriterReady { .. })
    ));
    let result = tokio::time::timeout(Duration::from_secs(1), completion.as_mut()).await;
    assert_admission_pending(control.as_mut()).await;
    assert_admission_pending(work.as_mut()).await;
    drop(receiver);
    assert_eq!(control.await, Err(ServerInboxSendError::Closed));
    assert_eq!(work.await, Err(ServerInboxSendError::Closed));
    assert_eq!(
        result.expect("completion must use the freed capacity"),
        Ok(())
    );
}

fn park_blocking_sender(
    inbox: &ServerInbox,
    command: ServerCommand,
) -> (
    std::thread::JoinHandle<SendResult>,
    mpsc::Receiver<SendResult>,
) {
    let wait_started = Arc::new(Barrier::new(2));
    inbox.admission.set_blocking_wait_hook(wait_started.clone());
    let (result_tx, result_rx) = mpsc::channel();
    let blocked = inbox.clone();
    let join = std::thread::spawn(move || {
        let result = blocked.send_blocking(command);
        result_tx.send(result).expect("sender result receiver");
        result
    });
    wait_started.wait();
    // This lock is acquired only after the producer enters the condvar wait.
    inbox.completion_counts();
    (join, result_rx)
}

#[test]
fn completion_release_wakes_blocking_sender_behind_ineligible_classes() {
    let (inbox, mut receiver) = ServerInbox::channel();
    fill_admission_lanes(&inbox);
    let (control_join, control_rx) =
        park_blocking_sender(&inbox, ServerCommand::ClientDisconnected { id: 999 });
    let (work_join, work_rx) = park_blocking_sender(&inbox, work());
    let (completion_join, completion_rx) = park_blocking_sender(&inbox, completion());

    assert!(matches!(
        receiver.try_recv(),
        Ok(ServerCommand::HistoryWriterReady { .. })
    ));
    let result = completion_rx.recv_timeout(Duration::from_secs(1));
    let control_still_waits = matches!(control_rx.try_recv(), Err(mpsc::TryRecvError::Empty));
    let work_still_waits = matches!(work_rx.try_recv(), Err(mpsc::TryRecvError::Empty));
    drop(receiver);
    let control_result = control_join.join().expect("control sender joins");
    let work_result = work_join.join().expect("work sender joins");
    let completion_result = completion_join.join().expect("completion sender joins");

    assert!(control_still_waits);
    assert!(work_still_waits);
    assert_eq!(control_result, Err(ServerInboxSendError::Closed));
    assert_eq!(work_result, Err(ServerInboxSendError::Closed));
    assert_eq!(
        result.expect("completion must use the freed capacity"),
        Ok(())
    );
    assert_eq!(completion_result, Ok(()));
}
