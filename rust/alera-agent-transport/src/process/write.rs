use std::io;
use std::time::Duration;

use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::time::Instant;

pub(super) enum FrameWriteError {
    Io(io::Error),
    Timeout,
}

/// A cancelled send retains both its prefix and original operation deadline.
pub(super) struct PendingFrame {
    bytes: Vec<u8>,
    offset: usize,
    deadline: Instant,
}

impl PendingFrame {
    pub(super) fn new(bytes: Vec<u8>, timeout: Duration) -> Self {
        Self {
            bytes,
            offset: 0,
            deadline: Instant::now() + timeout,
        }
    }

    pub(super) fn matches(&self, bytes: &[u8]) -> bool {
        self.bytes == bytes
    }

    pub(super) async fn complete<W: AsyncWrite + Unpin>(
        &mut self,
        writer: &mut W,
    ) -> Result<(), FrameWriteError> {
        // An expired retry cannot revive a frame merely because its pipe has
        // become writable since the caller cancelled the original attempt.
        if Instant::now() >= self.deadline {
            return Err(FrameWriteError::Timeout);
        }
        tokio::time::timeout_at(self.deadline, self.write_and_flush(writer))
            .await
            .map_err(|_| FrameWriteError::Timeout)?
            .map_err(FrameWriteError::Io)
    }

    async fn write_and_flush<W: AsyncWrite + Unpin>(&mut self, writer: &mut W) -> io::Result<()> {
        while self.offset < self.bytes.len() {
            let written = writer.write(&self.bytes[self.offset..]).await?;
            if written == 0 {
                return Err(io::ErrorKind::WriteZero.into());
            }
            // write is cancellation-safe, and the accepted prefix is recorded
            // before the next await. An offset at the end retains flush phase.
            self.offset += written;
        }
        writer.flush().await
    }
}

#[cfg(test)]
#[path = "write_tests.rs"]
mod tests;
