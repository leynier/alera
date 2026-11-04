use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;

use crate::{ByteStream, HttpError, HttpRequest, HttpResponse, HttpTransport};

type ScriptedStream = Result<VecDeque<Result<Vec<u8>, HttpError>>, HttpError>;

#[derive(Debug, Default)]
struct MockState {
    responses: VecDeque<Result<HttpResponse, HttpError>>,
    streams: VecDeque<ScriptedStream>,
    requests: Vec<HttpRequest>,
}

/// A scripted HTTP transport for provider tests.
///
/// Requests are captured in order. Normal responses and stream scripts are
/// consumed independently, allowing one adapter test to exercise both APIs.
#[derive(Clone, Debug, Default)]
pub struct MockHttpTransport {
    state: Arc<Mutex<MockState>>,
}

impl MockHttpTransport {
    /// Create an empty mock. Calls fail with [`HttpError::MockScriptExhausted`]
    /// until a response or stream is scripted.
    pub fn new() -> Self {
        Self::default()
    }

    /// Queue a complete response for the next [`HttpTransport::request`] call.
    pub fn push_response(&self, response: HttpResponse) {
        if let Ok(mut state) = self.state.lock() {
            state.responses.push_back(Ok(response));
        }
    }

    /// Queue an error for the next complete request call.
    pub fn push_response_error(&self, error: HttpError) {
        if let Ok(mut state) = self.state.lock() {
            state.responses.push_back(Err(error));
        }
    }

    /// Queue chunks for the next [`HttpTransport::open_stream`] call.
    pub fn push_stream(&self, chunks: impl IntoIterator<Item = Vec<u8>>) {
        if let Ok(mut state) = self.state.lock() {
            state
                .streams
                .push_back(Ok(chunks.into_iter().map(Ok).collect()));
        }
    }

    /// Queue a stream script containing successful chunks and errors.
    pub fn push_stream_results(
        &self,
        chunks: impl IntoIterator<Item = Result<Vec<u8>, HttpError>>,
    ) {
        if let Ok(mut state) = self.state.lock() {
            state.streams.push_back(Ok(chunks.into_iter().collect()));
        }
    }

    /// Queue an error for the next stream call.
    pub fn push_stream_error(&self, error: HttpError) {
        if let Ok(mut state) = self.state.lock() {
            state.streams.push_back(Err(error));
        }
    }

    /// Return a snapshot of all requests captured so far.
    pub fn captured_requests(&self) -> Vec<HttpRequest> {
        self.state
            .lock()
            .map(|state| state.requests.clone())
            .unwrap_or_default()
    }

    /// Clear captured requests without changing scripted responses.
    pub fn clear_captured_requests(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.requests.clear();
        }
    }
}

#[async_trait]
impl HttpTransport for MockHttpTransport {
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        let scripted = self
            .state
            .lock()
            .map_err(|_| HttpError::Request {
                operation: "mock lock",
            })
            .and_then(|mut state| {
                state.requests.push(request);
                state
                    .responses
                    .pop_front()
                    .unwrap_or(Err(HttpError::MockScriptExhausted))
            })?;
        Ok(scripted)
    }

    async fn open_stream(&self, request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        let scripted = self
            .state
            .lock()
            .map_err(|_| HttpError::Request {
                operation: "mock lock",
            })
            .and_then(|mut state| {
                state.requests.push(request);
                state
                    .streams
                    .pop_front()
                    .unwrap_or(Err(HttpError::MockScriptExhausted))
            })?;
        Ok(Box::new(MockByteStream {
            chunks: scripted,
            closed: false,
        }))
    }
}

#[derive(Debug)]
struct MockByteStream {
    chunks: VecDeque<Result<Vec<u8>, HttpError>>,
    closed: bool,
}

#[async_trait]
impl ByteStream for MockByteStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        if self.closed {
            return Err(HttpError::Closed);
        }
        match self.chunks.pop_front() {
            None => {
                self.closed = true;
                Ok(None)
            }
            Some(Ok(chunk)) => Ok(Some(chunk)),
            Some(Err(error)) => {
                self.closed = true;
                Err(error)
            }
        }
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        self.closed = true;
        self.chunks.clear();
        Ok(())
    }
}
