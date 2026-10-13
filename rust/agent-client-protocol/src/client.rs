use crate::callbacks::ClientCallbacks;
use crate::error::AcpError;
use crate::handler::AcpClientRequestHandler;
use crate::rpc::{self, AcpIncoming, AcpRequestId, AcpResponse, RpcError};
use crate::schema::{AcpInitializeResponse, AcpPromptResponse, AcpProtocolGeneration};
use alera_agent_transport::{JsonTransport, DEFAULT_MAX_FRAME_BYTES};
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[path = "client_routing.rs"]
mod routing;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingCallKind {
    Initialize,
    Authenticate,
    Session,
    Prompt,
    Config,
    Other,
}

#[derive(Debug, Clone)]
struct PendingCall {
    method: String,
    kind: PendingCallKind,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpClientState {
    pub initialized: bool,
    pub negotiated_protocol_version: Option<u64>,
    pub pending_requests: usize,
    pub queued_incoming: usize,
}

/// ACP JSON-RPC client over an injected newline JSON transport.
pub struct AcpClient<T> {
    transport: T,
    next_id: i64,
    timeout: Duration,
    max_queued_incoming: usize,
    max_response_frame_bytes: usize,
    pending: HashMap<String, PendingCall>,
    completed: HashMap<String, Result<Value, RpcError>>,
    incoming: VecDeque<AcpIncoming>,
    request_handler: Option<Arc<dyn AcpClientRequestHandler>>,
    callbacks: ClientCallbacks,
    initialized: Option<AcpInitializeResponse>,
    closed: bool,
}

impl<T: JsonTransport> AcpClient<T> {
    pub fn new(transport: T) -> Self {
        Self::with_options(transport, Duration::from_secs(120), 32)
    }

    pub fn with_options(transport: T, timeout: Duration, max_queued_incoming: usize) -> Self {
        Self {
            transport,
            next_id: 1,
            timeout,
            max_queued_incoming: max_queued_incoming.max(1),
            max_response_frame_bytes: DEFAULT_MAX_FRAME_BYTES,
            pending: HashMap::new(),
            completed: HashMap::new(),
            incoming: VecDeque::new(),
            request_handler: None,
            callbacks: ClientCallbacks::new(max_queued_incoming.max(1)),
            initialized: None,
            closed: false,
        }
    }

    pub fn transport(&self) -> &T {
        &self.transport
    }

    pub fn transport_mut(&mut self) -> &mut T {
        &mut self.transport
    }

    pub fn state(&self) -> AcpClientState {
        AcpClientState {
            initialized: self.initialized.is_some(),
            negotiated_protocol_version: self
                .initialized
                .as_ref()
                .map(|value| value.protocol_version),
            pending_requests: self.pending.len(),
            queued_incoming: self.incoming.len(),
        }
    }

    pub fn initialized(&self) -> Option<&AcpInitializeResponse> {
        self.initialized.as_ref()
    }

    pub fn set_request_handler(&mut self, handler: Option<Arc<dyn AcpClientRequestHandler>>) {
        self.request_handler = handler;
    }

    pub fn set_timeout(&mut self, timeout: Duration) {
        self.timeout = timeout;
    }

    /// Set the transport's encoded response limit, excluding the newline.
    ///
    /// Configure this before receiving requests. Custom transports do not
    /// expose a frame limit. The default matches `ProcessConfig`; direct SDK
    /// users must supply this when their transport uses a different limit.
    pub fn set_max_response_frame_bytes(&mut self, max_frame_bytes: usize) {
        self.max_response_frame_bytes = max_frame_bytes;
    }

    pub fn take_completed(&mut self, id: &AcpRequestId) -> Option<Result<Value, RpcError>> {
        self.completed.remove(&id.key())
    }

    pub async fn initialize(
        &mut self,
        client_name: &str,
        client_version: &str,
    ) -> Result<(), AcpError> {
        self.initialize_with_meta(client_name, client_version, None)
            .await
    }

    pub async fn initialize_with_meta(
        &mut self,
        client_name: &str,
        client_version: &str,
        meta: Option<Value>,
    ) -> Result<(), AcpError> {
        if self.initialized.is_some() {
            return Ok(());
        }
        let mut params = json!({
            "protocolVersion": 2,
            "info": {"name": client_name, "version": client_version},
            "capabilities": {
                "elicitation": {"form": {}, "url": {}}
            },
            "clientCapabilities": {
                "fs": {"readTextFile": false, "writeTextFile": false},
                "terminal": self.request_handler.as_ref().is_some_and(|handler| handler.supports_terminal()),
                "session": {"list": null},
                "elicitation": {"form": {}, "url": {}}
            },
            "clientInfo": {"name": client_name, "version": client_version}
        });
        if let Some(meta) = meta {
            params["_meta"] = meta;
        }
        let value = self
            .call("initialize", params, PendingCallKind::Initialize)
            .await?;
        self.initialized = Some(AcpInitializeResponse::from_value(value)?);
        Ok(())
    }

    pub async fn authenticate(&mut self, method_id: &str) -> Result<Value, AcpError> {
        let (method, params) = match self
            .initialized
            .as_ref()
            .map(|response| response.generation)
        {
            Some(AcpProtocolGeneration::V1) | None => {
                ("authenticate", json!({"methodId": method_id}))
            }
            Some(AcpProtocolGeneration::V2) => ("auth/login", json!({"methodId": method_id})),
        };
        self.call(method, params, PendingCallKind::Authenticate)
            .await
    }

    pub async fn prompt(
        &mut self,
        session_id: &str,
        prompt: Vec<Value>,
    ) -> Result<AcpPromptResponse, AcpError> {
        let value = self
            .call(
                "session/prompt",
                json!({"sessionId": session_id, "prompt": prompt}),
                PendingCallKind::Prompt,
            )
            .await?;
        Ok(AcpPromptResponse::from_value(value))
    }

    /// Sends a prompt without waiting for its terminal response.
    ///
    /// This is the path providers use for interactive turns. ACP agents may
    /// send permission requests while `session/prompt` is still pending; a
    /// blocking prompt call would deadlock the provider waiting for a user
    /// response.
    pub async fn begin_prompt(
        &mut self,
        session_id: &str,
        prompt: Vec<Value>,
    ) -> Result<AcpRequestId, AcpError> {
        self.begin_prompt_with_meta(session_id, prompt, None).await
    }

    /// Sends an interactive prompt with an optional provider metadata envelope.
    ///
    /// Metadata is part of the ACP request parameters and is intentionally
    /// independent from the JSON-RPC request id. Some agents correlate prompt
    /// notifications with these values rather than with the transport id.
    pub async fn begin_prompt_with_meta(
        &mut self,
        session_id: &str,
        prompt: Vec<Value>,
        meta: Option<Value>,
    ) -> Result<AcpRequestId, AcpError> {
        let mut params = json!({"sessionId": session_id, "prompt": prompt});
        if let Some(meta) = meta {
            params["_meta"] = meta;
        }
        self.send_call("session/prompt", params, PendingCallKind::Prompt)
            .await
    }

    pub async fn cancel(&mut self, session_id: &str) -> Result<(), AcpError> {
        self.cancel_with_meta(session_id, None).await
    }

    pub async fn cancel_with_meta(
        &mut self,
        session_id: &str,
        meta: Option<Value>,
    ) -> Result<(), AcpError> {
        self.ensure_open()?;
        self.flush_callbacks().await?;
        let mut params = json!({"sessionId": session_id});
        if let Some(meta) = meta {
            params["_meta"] = meta;
        }
        self.send_frame(
            rpc::notification("session/cancel", params),
            "session/cancel",
        )
        .await
    }

    pub async fn respond(
        &mut self,
        id: &AcpRequestId,
        result: Result<Value, RpcError>,
    ) -> Result<(), AcpError> {
        self.ensure_open()?;
        self.callbacks
            .queue_response(id, result, self.timeout, self.max_response_frame_bytes)?;
        self.flush_callbacks().await
    }

    pub async fn close(&mut self) -> Result<(), AcpError> {
        self.stop_routing();
        self.callbacks.reap().await;
        tokio::time::timeout(self.timeout, self.transport.close())
            .await
            .map_err(|_| AcpError::Timeout {
                method: "close".into(),
                timeout: self.timeout,
            })??;
        Ok(())
    }

    pub(crate) async fn call(
        &mut self,
        method: &str,
        params: Value,
        kind: PendingCallKind,
    ) -> Result<Value, AcpError> {
        let id = self.send_call(method, params, kind).await?;
        let deadline = Instant::now() + self.timeout;
        loop {
            if let Some(result) = self.take_completed(&id) {
                return result.map_err(|error| AcpError::Rpc {
                    code: error.code,
                    message: error.message,
                    data: error.data,
                });
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return self
                    .fail_routing(AcpError::Timeout {
                        method: method.to_owned(),
                        timeout: self.timeout,
                    })
                    .await;
            }
            if let Err(error) = self.receive_for_call(remaining).await {
                self.pending.remove(&id.key());
                return Err(error);
            }
        }
    }

    async fn send_call(
        &mut self,
        method: &str,
        params: Value,
        kind: PendingCallKind,
    ) -> Result<AcpRequestId, AcpError> {
        self.ensure_open()?;
        self.flush_callbacks().await?;
        if self.pending.len() + self.completed.len() >= self.max_queued_incoming {
            return Err(AcpError::QueueFull {
                capacity: self.max_queued_incoming,
            });
        }
        let id = AcpRequestId::Number(self.next_id);
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or_else(|| AcpError::Protocol("ACP request id counter exhausted".into()))?;
        let key = id.key();
        self.pending.insert(
            key.clone(),
            PendingCall {
                method: method.to_owned(),
                kind,
            },
        );
        self.send_frame(rpc::request(id.clone(), method, params), method)
            .await?;
        Ok(id)
    }

    fn route_response(&mut self, response: AcpResponse) -> Result<(), AcpError> {
        let key = response.id.key();
        let Some(pending) = self.pending.remove(&key) else {
            return Err(AcpError::Protocol(format!(
                "response for unknown ACP request id {}",
                response.id
            )));
        };
        let _pending_metadata = (&pending.method, pending.kind);
        self.completed.insert(
            key,
            match response.error {
                Some(error) => Err(error),
                None => Ok(response.result.unwrap_or(Value::Null)),
            },
        );
        Ok(())
    }

    fn ensure_open(&self) -> Result<(), AcpError> {
        if self.closed {
            Err(AcpError::Closed)
        } else {
            Ok(())
        }
    }

    fn enqueue(&mut self, incoming: AcpIncoming) -> Result<(), AcpError> {
        if self.incoming.len() >= self.max_queued_incoming {
            return Err(AcpError::QueueFull {
                capacity: self.max_queued_incoming,
            });
        }
        self.incoming.push_back(incoming);
        Ok(())
    }
}

impl<T> Drop for AcpClient<T> {
    fn drop(&mut self) {
        self.callbacks.abort();
    }
}
