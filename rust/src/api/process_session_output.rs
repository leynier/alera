//! Concurrent stdout/stderr forwarding for a running process session.

use std::sync::Arc;

use tokio::io::{AsyncRead, AsyncReadExt};

use super::{ProcessEvent, ProcessEventKind};
use crate::frb_generated::StreamSink;

/// How long output already in flight may take to drain once the child exited.
pub(super) const DRAIN_GRACE: std::time::Duration = std::time::Duration::from_secs(2);

pub(super) fn forward<R>(
    reader: Option<R>,
    sink: Arc<StreamSink<ProcessEvent>>,
    kind: ProcessEventKind,
) -> tokio::task::JoinHandle<Result<(), String>>
where
    R: AsyncRead + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let Some(mut reader) = reader else {
            return Ok(());
        };
        let mut buffer = vec![0_u8; 64 * 1024];
        let mut sink_open = true;
        loop {
            match reader.read(&mut buffer).await {
                Ok(0) => return Ok(()),
                Err(error) => {
                    return Err(format!(
                        "failed reading {}: {error}",
                        match kind {
                            ProcessEventKind::Stdout => "stdout",
                            ProcessEventKind::Stderr => "stderr",
                            _ => "process output",
                        }
                    ));
                }
                Ok(read) => {
                    // A closed sink means the Dart listener is gone. Keep
                    // draining the pipe so the child cannot block on a full
                    // kernel buffer while it is being reaped.
                    if sink_open {
                        let event = ProcessEvent {
                            kind,
                            session_id: 0,
                            pid: 0,
                            data: buffer[..read].to_vec(),
                            exit_code: 0,
                            message: String::new(),
                        };
                        sink_open = sink.add(event).is_ok();
                    }
                }
            }
        }
    })
}
