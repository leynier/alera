use crate::rpc::{AcpRequestId, RpcError, RpcRequest};
use async_trait::async_trait;
use serde_json::Value;
use std::time::{Duration, Instant};

/// The original typed request id and monotonic operation deadline.
///
/// Handlers run concurrently. Their futures survive cancellation of a client
/// read, but are dropped when the deadline expires or the client shuts down.
/// Any owned process must therefore have independent cancellation cleanup.
#[derive(Debug, Clone)]
pub struct AcpRequestHandlerContext {
    pub request_id: AcpRequestId,
    pub deadline: Instant,
}

impl AcpRequestHandlerContext {
    pub fn remaining(&self) -> Duration {
        self.deadline.saturating_duration_since(Instant::now())
    }

    pub fn is_expired(&self) -> bool {
        Instant::now() >= self.deadline
    }
}

#[async_trait]
pub trait AcpClientRequestHandler: Send + Sync {
    /// Advertise terminal support only for handlers implementing the ACP
    /// terminal service. Generic request handlers default to no capability.
    fn supports_terminal(&self) -> bool {
        false
    }

    async fn handle(
        &self,
        request: RpcRequest,
        context: AcpRequestHandlerContext,
    ) -> Option<Result<Value, RpcError>>;
}
