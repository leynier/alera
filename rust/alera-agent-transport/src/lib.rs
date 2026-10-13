//! Provider-facing asynchronous JSON-lines transports.
//!
//! [`JsonLineProcess`] runs a provider SDK or adapter as a child process and
//! exchanges one JSON value per line. The framing is bounded in both
//! directions, and stderr is drained independently so a verbose provider
//! cannot block the protocol pipe.

mod error;
mod framing;
mod managed_process;
mod mock;
mod process;

pub use error::TransportError;
pub use framing::{DEFAULT_MAX_FRAME_BYTES, DEFAULT_SHUTDOWN_TIMEOUT};
pub use managed_process::ManagedProcess;
pub use mock::MockTransport;
pub use process::{JsonLineProcess, ProcessConfig};

use async_trait::async_trait;

/// A bidirectional JSON message transport.
#[async_trait]
pub trait JsonTransport: Send {
    /// Serialize and send one JSON message, followed by a newline.
    async fn send(&mut self, message: serde_json::Value) -> Result<(), TransportError>;

    /// Receive the next JSON message, or `None` after a clean end of stream.
    async fn recv(&mut self) -> Result<Option<serde_json::Value>, TransportError>;

    /// Close the transport and clean up its child or in-memory state.
    async fn close(&mut self) -> Result<(), TransportError>;
}
