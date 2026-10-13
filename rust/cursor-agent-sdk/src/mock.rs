use crate::error::CursorSdkError;
use crate::transport::{BridgeTransport, ByteStream};
use async_trait::async_trait;
use serde_json::Value;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Clone, Default)]
pub struct MockBridgeTransport {
    inner: Arc<Mutex<MockState>>,
}

#[derive(Default)]
struct MockState {
    unary: VecDeque<Result<Value, CursorSdkError>>,
    streams: VecDeque<Result<Vec<Vec<u8>>, CursorSdkError>>,
    calls: Vec<(String, Value)>,
}

impl MockBridgeTransport {
    pub fn push_unary(&self, value: Result<Value, CursorSdkError>) {
        self.inner
            .lock()
            .expect("mock mutex poisoned")
            .unary
            .push_back(value);
    }

    pub fn push_stream(&self, chunks: Vec<Vec<u8>>) {
        self.inner
            .lock()
            .expect("mock mutex poisoned")
            .streams
            .push_back(Ok(chunks));
    }

    pub fn calls(&self) -> Vec<(String, Value)> {
        self.inner
            .lock()
            .expect("mock mutex poisoned")
            .calls
            .clone()
    }
}

#[async_trait]
impl BridgeTransport for MockBridgeTransport {
    async fn unary(
        &self,
        path: &str,
        _bearer_token: &str,
        body: Value,
        _timeout: Duration,
    ) -> Result<Value, CursorSdkError> {
        let mut state = self.inner.lock().expect("mock mutex poisoned");
        state.calls.push((path.to_owned(), body));
        state
            .unary
            .pop_front()
            .unwrap_or_else(|| Err(CursorSdkError::Protocol("mock unary queue is empty".into())))
    }

    async fn stream(
        &self,
        path: &str,
        _bearer_token: &str,
        body: Vec<u8>,
        _timeout: Duration,
    ) -> Result<Box<dyn ByteStream>, CursorSdkError> {
        let value = if body.len() >= 5 {
            serde_json::from_slice(&body[5..]).unwrap_or(Value::Null)
        } else {
            Value::Null
        };
        let mut state = self.inner.lock().expect("mock mutex poisoned");
        state.calls.push((path.to_owned(), value));
        let chunks = state.streams.pop_front().unwrap_or_else(|| {
            Err(CursorSdkError::Protocol(
                "mock stream queue is empty".into(),
            ))
        })?;
        Ok(Box::new(MockByteStream {
            chunks: chunks.into_iter().collect(),
        }))
    }
}

struct MockByteStream {
    chunks: VecDeque<Vec<u8>>,
}

#[async_trait]
impl ByteStream for MockByteStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, CursorSdkError> {
        Ok(self.chunks.pop_front())
    }
}
