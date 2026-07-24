use std::sync::mpsc::TrySendError;
use std::time::Duration;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::{PtyWriteCompletion, Session};

pub(super) struct PtyWrite {
    pub(super) completion: PtyWriteCompletion,
    pub(super) bytes: Vec<u8>,
    pub(super) deferred: Option<PtyDeferredWrite>,
}

pub(super) struct PtyDeferredWrite {
    pub(super) delay: Duration,
    pub(super) bytes: Vec<u8>,
}

impl Session {
    /// Queue input for the session-local blocking writer.
    pub fn queue_write(&mut self, completion: PtyWriteCompletion, bytes: &[u8]) -> HostResult<()> {
        self.queue_write_request(completion, bytes, None)
    }

    /// Queue a write whose delayed suffix must stay adjacent to its payload.
    pub fn queue_write_deferred(
        &mut self,
        completion: PtyWriteCompletion,
        bytes: &[u8],
        delay: Duration,
        deferred_bytes: &[u8],
    ) -> HostResult<()> {
        self.queue_write_request(
            completion,
            bytes,
            Some(PtyDeferredWrite {
                delay,
                bytes: deferred_bytes.to_vec(),
            }),
        )
    }

    fn queue_write_request(
        &mut self,
        completion: PtyWriteCompletion,
        bytes: &[u8],
        deferred: Option<PtyDeferredWrite>,
    ) -> HostResult<()> {
        if bytes.is_empty() {
            return Ok(());
        }
        if !self.running {
            return Err(HostError::state("Terminal session is not running."));
        }
        let Some(input_tx) = self.input_tx.as_ref() else {
            return Err(HostError::state("terminal input writer is unavailable"));
        };
        input_tx
            .try_send(PtyWrite {
                completion,
                bytes: bytes.to_vec(),
                deferred,
            })
            .map_err(|error| match error {
                TrySendError::Full(_) => {
                    HostError::state("terminal_input_backpressure: terminal input queue is full")
                }
                TrySendError::Disconnected(_) => {
                    HostError::state("terminal input writer is unavailable")
                }
            })
    }
}
