use std::future::Future;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

use tokio::io::AsyncWrite;

use super::{FrameWriteError, PendingFrame};

#[derive(Default)]
struct ControlledWriter {
    bytes: Vec<u8>,
    allowance: usize,
    allow_flush: bool,
    write_error: Option<io::ErrorKind>,
    flush_error: Option<io::ErrorKind>,
    write_zero: bool,
}

impl AsyncWrite for ControlledWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _context: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        if let Some(kind) = self.write_error.take() {
            return Poll::Ready(Err(kind.into()));
        }
        if self.write_zero {
            return Poll::Ready(Ok(0));
        }
        if self.allowance == 0 {
            return Poll::Pending;
        }
        let count = bytes.len().min(self.allowance);
        self.bytes.extend_from_slice(&bytes[..count]);
        self.allowance -= count;
        Poll::Ready(Ok(count))
    }

    fn poll_flush(mut self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<io::Result<()>> {
        if let Some(kind) = self.flush_error.take() {
            return Poll::Ready(Err(kind.into()));
        }
        if self.allow_flush {
            Poll::Ready(Ok(()))
        } else {
            Poll::Pending
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, _context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}

async fn poll_pending_once(future: impl Future) {
    let mut future = std::pin::pin!(future);
    std::future::poll_fn(|context| {
        assert!(future.as_mut().poll(context).is_pending());
        Poll::Ready(())
    })
    .await;
}

#[tokio::test]
async fn cancellation_keeps_both_partial_write_and_flush_progress() {
    let bytes = b"{\"id\":1}\n".to_vec();
    let mut frame = PendingFrame::new(bytes.clone(), Duration::from_secs(5));
    let mut writer = ControlledWriter {
        allowance: 3,
        ..ControlledWriter::default()
    };
    poll_pending_once(frame.complete(&mut writer)).await;
    assert_eq!(frame.offset, 3);
    assert_eq!(writer.bytes, bytes[..3]);

    writer.allowance = usize::MAX;
    poll_pending_once(frame.complete(&mut writer)).await;
    assert_eq!(frame.offset, bytes.len());
    assert_eq!(writer.bytes, bytes);

    writer.allow_flush = true;
    assert!(frame.complete(&mut writer).await.is_ok());
    assert_eq!(writer.bytes, bytes);
}

#[tokio::test(start_paused = true)]
async fn retry_keeps_the_original_frame_deadline() {
    let mut frame = PendingFrame::new(b"frame\n".to_vec(), Duration::from_secs(5));
    let deadline = frame.deadline;
    let mut writer = ControlledWriter {
        allowance: 1,
        ..ControlledWriter::default()
    };
    poll_pending_once(frame.complete(&mut writer)).await;
    tokio::time::advance(Duration::from_secs(6)).await;
    writer.allowance = usize::MAX;
    writer.allow_flush = true;
    assert!(matches!(
        frame.complete(&mut writer).await,
        Err(FrameWriteError::Timeout)
    ));
    assert_eq!(frame.deadline, deadline);
    assert_eq!(writer.bytes, b"f");
}

#[tokio::test]
async fn zero_write_and_write_error_are_explicit() {
    for (write_zero, write_error, expected) in [
        (true, None, io::ErrorKind::WriteZero),
        (
            false,
            Some(io::ErrorKind::BrokenPipe),
            io::ErrorKind::BrokenPipe,
        ),
    ] {
        let mut frame = PendingFrame::new(b"frame\n".to_vec(), Duration::from_secs(5));
        let mut writer = ControlledWriter {
            write_zero,
            write_error,
            ..ControlledWriter::default()
        };
        let Err(FrameWriteError::Io(error)) = frame.complete(&mut writer).await else {
            panic!("expected a write I/O error");
        };
        assert_eq!(error.kind(), expected);
        assert_eq!(frame.offset, 0);
    }
}

#[tokio::test]
async fn flush_error_preserves_the_complete_written_prefix() {
    let bytes = b"frame\n".to_vec();
    let mut frame = PendingFrame::new(bytes.clone(), Duration::from_secs(5));
    let mut writer = ControlledWriter {
        allowance: usize::MAX,
        flush_error: Some(io::ErrorKind::BrokenPipe),
        ..ControlledWriter::default()
    };
    let Err(FrameWriteError::Io(error)) = frame.complete(&mut writer).await else {
        panic!("expected a flush I/O error");
    };
    assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
    assert_eq!(frame.offset, bytes.len());
    assert_eq!(writer.bytes, bytes);
}
