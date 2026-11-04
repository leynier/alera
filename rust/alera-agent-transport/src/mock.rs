use std::collections::VecDeque;

use async_trait::async_trait;

use crate::{JsonTransport, TransportError};

/// A deterministic in-memory transport for provider and protocol tests.
///
/// Responses are consumed in order. Writes are retained so a test can assert
/// the exact messages that a provider emitted without starting a child process.
#[derive(Debug, Default)]
pub struct MockTransport {
    responses: VecDeque<Result<Option<serde_json::Value>, TransportError>>,
    writes: Vec<serde_json::Value>,
    closed: bool,
}

impl MockTransport {
    /// Create a mock that returns each value in `responses`, then EOF.
    pub fn new(responses: impl IntoIterator<Item = serde_json::Value>) -> Self {
        Self {
            responses: responses
                .into_iter()
                .map(|response| Ok(Some(response)))
                .collect(),
            ..Self::default()
        }
    }

    /// Create a mock from scripted receive results, including errors and EOF.
    pub fn from_results(
        responses: impl IntoIterator<Item = Result<Option<serde_json::Value>, TransportError>>,
    ) -> Self {
        Self {
            responses: responses.into_iter().collect(),
            ..Self::default()
        }
    }

    /// Create a mock from an already assembled response queue.
    pub fn scripted(
        responses: VecDeque<Result<Option<serde_json::Value>, TransportError>>,
    ) -> Self {
        Self {
            responses,
            ..Self::default()
        }
    }

    /// Append a receive result to the script.
    pub fn push_result(&mut self, response: Result<Option<serde_json::Value>, TransportError>) {
        self.responses.push_back(response);
    }

    /// Append one successful response to the script.
    pub fn push_response(&mut self, response: serde_json::Value) {
        self.responses.push_back(Ok(Some(response)));
    }

    /// The messages sent through this transport, in order.
    pub fn writes(&self) -> &[serde_json::Value] {
        &self.writes
    }

    /// Consume the mock and return its captured writes.
    pub fn into_writes(self) -> Vec<serde_json::Value> {
        self.writes
    }

    /// Whether [`JsonTransport::close`] has been called.
    pub fn is_closed(&self) -> bool {
        self.closed
    }
}

#[async_trait]
impl JsonTransport for MockTransport {
    async fn send(&mut self, message: serde_json::Value) -> Result<(), TransportError> {
        if self.closed {
            return Err(TransportError::Closed);
        }
        self.writes.push(message);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<serde_json::Value>, TransportError> {
        if self.closed {
            return Err(TransportError::Closed);
        }
        self.responses.pop_front().unwrap_or(Ok(None))
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed = true;
        Ok(())
    }
}
