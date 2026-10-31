//! The bounded stderr tail a provider exit error carries.

use std::sync::{Arc, Mutex};

use tokio::io::AsyncReadExt;
use tokio::process::ChildStderr;

use super::READ_CHUNK_BYTES;
use crate::framing::{newline_position, STDERR_TAIL_BYTES};
use crate::redaction::redact_secrets;

#[derive(Debug, Default)]
pub(super) struct StderrTail {
    bytes: Vec<u8>,
    truncated: bool,
}

impl StderrTail {
    pub(super) fn append(&mut self, bytes: &[u8]) {
        if bytes.len() >= STDERR_TAIL_BYTES {
            self.truncated |= !self.bytes.is_empty() || bytes.len() > STDERR_TAIL_BYTES;
            self.bytes.clear();
            self.bytes
                .extend_from_slice(&bytes[bytes.len() - STDERR_TAIL_BYTES..]);
            return;
        }

        let total = self.bytes.len() + bytes.len();
        if total > STDERR_TAIL_BYTES {
            self.truncated = true;
            self.bytes
                .drain(..(total - STDERR_TAIL_BYTES).min(self.bytes.len()));
        }
        self.bytes.extend_from_slice(bytes);
    }

    /// The tail with credentials masked. Once older output was dropped the
    /// first line may hold a value cut off from its key, so it goes too.
    pub(super) fn text(&self) -> String {
        let mut bytes = self.bytes.as_slice();
        if self.truncated {
            if let Some(newline) = newline_position(bytes) {
                bytes = &bytes[newline + 1..];
            }
        }
        redact_secrets(&String::from_utf8_lossy(bytes))
    }
}

pub(super) async fn drain_stderr(mut stderr: ChildStderr, tail: Arc<Mutex<StderrTail>>) {
    let mut buffer = [0_u8; READ_CHUNK_BYTES];
    loop {
        match stderr.read(&mut buffer).await {
            Ok(0) | Err(_) => break,
            Ok(read) => {
                if let Ok(mut tail) = tail.lock() {
                    tail.append(&buffer[..read]);
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "stderr_tests.rs"]
mod tests;
