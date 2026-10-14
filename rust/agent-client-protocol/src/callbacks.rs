use crate::handler::{AcpClientRequestHandler, AcpRequestHandlerContext};
use crate::rpc::{AcpRequestId, RpcError, RpcRequest};
use crate::AcpError;
use serde_json::Value;
use std::collections::{HashSet, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::task::{JoinError, JoinSet};

pub(crate) struct CallbackResult {
    request: RpcRequest,
    response: Option<Result<Value, RpcError>>,
}

pub(crate) struct OutboundResponse {
    pub id: AcpRequestId,
    pub result: Result<Value, RpcError>,
    pub frame: Value,
    pub deadline: Instant,
}

/// Owns callback lifetimes and responses independently of any reader future.
pub(crate) struct ClientCallbacks {
    capacity: usize,
    active: HashSet<AcpRequestId>,
    pub tasks: JoinSet<CallbackResult>,
    pub outbox: VecDeque<OutboundResponse>,
}

impl ClientCallbacks {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            active: HashSet::new(),
            tasks: JoinSet::new(),
            outbox: VecDeque::new(),
        }
    }

    pub fn register(&mut self, id: &AcpRequestId) -> Result<(), AcpError> {
        if self.active.contains(id) {
            return Err(AcpError::Protocol(format!(
                "duplicate outstanding ACP peer request id {id}"
            )));
        }
        if self.active.len() >= self.capacity {
            return Err(AcpError::QueueFull {
                capacity: self.capacity,
            });
        }
        self.active.insert(id.clone());
        Ok(())
    }

    pub fn dispatch(
        &mut self,
        request: RpcRequest,
        handler: Arc<dyn AcpClientRequestHandler>,
        timeout: Duration,
    ) {
        let context = AcpRequestHandlerContext {
            request_id: request.id.clone(),
            deadline: Instant::now() + timeout,
        };
        self.tasks.spawn(async move {
            let response = match tokio::time::timeout_at(
                context.deadline.into(),
                handler.handle(request.clone(), context),
            )
            .await
            {
                Ok(response) => response,
                Err(_) => Some(Err(RpcError {
                    code: -32001,
                    message: format!("ACP request handler timed out for {}", request.method),
                    data: None,
                })),
            };
            CallbackResult { request, response }
        });
    }

    pub fn completed(
        &mut self,
        result: Result<CallbackResult, JoinError>,
        timeout: Duration,
        max_frame_bytes: usize,
    ) -> Result<Option<RpcRequest>, AcpError> {
        let result = result.map_err(|error| {
            AcpError::Protocol(format!("ACP request handler task failed: {error}"))
        })?;
        match result.response {
            Some(response) => {
                self.queue_response(&result.request.id, response, timeout, max_frame_bytes)?;
                Ok(None)
            }
            None => Ok(Some(result.request)),
        }
    }

    pub fn queue_response(
        &mut self,
        id: &AcpRequestId,
        result: Result<Value, RpcError>,
        timeout: Duration,
        max_frame_bytes: usize,
    ) -> Result<(), AcpError> {
        if !self.active.contains(id) {
            return Err(AcpError::Protocol(format!(
                "response for unknown or already answered ACP peer request id {id}"
            )));
        }
        if let Some(response) = self.outbox.iter().find(|response| response.id == *id) {
            return if response.result == result {
                Ok(())
            } else {
                Err(AcpError::Protocol(format!(
                    "conflicting response for ACP peer request id {id}"
                )))
            };
        }
        let frame = crate::response_frame::bounded_response(id, result.clone(), max_frame_bytes)?;
        self.outbox.push_back(OutboundResponse {
            id: id.clone(),
            result,
            frame,
            deadline: Instant::now() + timeout,
        });
        Ok(())
    }

    pub fn sent(&mut self) {
        if let Some(response) = self.outbox.pop_front() {
            self.active.remove(&response.id);
        }
    }

    pub fn abort(&mut self) {
        self.tasks.abort_all();
        self.active.clear();
        self.outbox.clear();
    }

    pub async fn reap(&mut self) {
        while self.tasks.join_next().await.is_some() {}
    }
}
