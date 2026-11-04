use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::sync::mpsc::Sender;

use super::{FrameResult, READ_CHUNK_BYTES, STDOUT_QUEUE_CAPACITY};
use crate::framing::{frame_length, newline_position};
use crate::TransportError;

async fn send_frame(sender: &Sender<FrameResult>, bytes: &[u8], timeout: Duration) -> bool {
    let value = match crate::framing::parse_frame(bytes) {
        Ok(value) => value,
        Err(error) => {
            let _ = sender.send(Err(error)).await;
            return false;
        }
    };

    // Keep one slot for a terminal error. Waiting for two slots lets a
    // healthy receiver drain a burst without growing the bounded queue.
    let mut permits = match tokio::time::timeout(timeout, sender.reserve_many(2)).await {
        Ok(Ok(permits)) => permits,
        Ok(Err(_)) => return false,
        Err(_) => {
            let _ = sender.try_send(Err(TransportError::OutputQueueFull {
                capacity: STDOUT_QUEUE_CAPACITY,
            }));
            return false;
        }
    };
    permits
        .next()
        .expect("two slots were reserved")
        .send(Ok(Some(value)));
    true
}

pub(super) async fn drain_stdout<R>(
    mut stdout: R,
    sender: Sender<FrameResult>,
    max_frame_bytes: usize,
    backpressure_timeout: Duration,
) where
    R: AsyncRead + Unpin,
{
    let mut read_buffer = Vec::new();

    loop {
        let mut chunk = [0_u8; READ_CHUNK_BYTES];
        let read = match stdout.read(&mut chunk).await {
            Ok(read) => read,
            Err(source) => {
                let _ = sender
                    .send(Err(TransportError::io("read stdout", source)))
                    .await;
                return;
            }
        };
        if read == 0 {
            let frame_len = frame_length(&read_buffer);
            if frame_len > max_frame_bytes {
                let _ = sender
                    .send(Err(TransportError::FrameTooLarge {
                        limit: max_frame_bytes,
                        observed: frame_len,
                    }))
                    .await;
                return;
            }
            if !read_buffer.is_empty()
                && !send_frame(&sender, &read_buffer, backpressure_timeout).await
            {
                return;
            }
            let _ = sender.send(Ok(None)).await;
            return;
        }

        read_buffer.extend_from_slice(&chunk[..read]);
        while let Some(newline) = newline_position(&read_buffer) {
            let frame_len = frame_length(&read_buffer[..newline]);
            if frame_len > max_frame_bytes {
                let _ = sender
                    .send(Err(TransportError::FrameTooLarge {
                        limit: max_frame_bytes,
                        observed: frame_len,
                    }))
                    .await;
                return;
            }

            let mut frame = read_buffer.drain(..=newline).collect::<Vec<_>>();
            frame.pop();
            if !send_frame(&sender, &frame, backpressure_timeout).await {
                return;
            }
        }

        if frame_length(&read_buffer) > max_frame_bytes {
            let _ = sender
                .send(Err(TransportError::FrameTooLarge {
                    limit: max_frame_bytes,
                    observed: frame_length(&read_buffer),
                }))
                .await;
            return;
        }
    }
}

#[cfg(test)]
#[path = "read_tests.rs"]
mod tests;
