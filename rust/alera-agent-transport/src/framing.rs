use std::time::Duration;

use crate::TransportError;

/// The default maximum encoded JSON frame, including neither the newline nor
/// any process-internal buffering.
pub const DEFAULT_MAX_FRAME_BYTES: usize = 4 * 1024 * 1024;

/// The default grace period used while closing a provider process.
pub const DEFAULT_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(5);

/// Keep diagnostics useful without allowing a noisy provider to grow memory
/// without bound while its stdout protocol is being consumed.
pub(crate) const STDERR_TAIL_BYTES: usize = 64 * 1024;

pub(crate) fn parse_frame(bytes: &[u8]) -> Result<serde_json::Value, TransportError> {
    let bytes = bytes.strip_suffix(b"\r").unwrap_or(bytes);
    let text =
        std::str::from_utf8(bytes).map_err(|source| TransportError::InvalidUtf8 { source })?;
    serde_json::from_str(text).map_err(|source| TransportError::InvalidJson { source })
}

pub(crate) fn frame_length(bytes: &[u8]) -> usize {
    if bytes.ends_with(b"\r") {
        bytes.len() - 1
    } else {
        bytes.len()
    }
}

pub(crate) fn newline_position(bytes: &[u8]) -> Option<usize> {
    bytes.iter().position(|byte| *byte == b'\n')
}
