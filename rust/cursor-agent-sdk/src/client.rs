use crate::error::CursorSdkError;
use crate::framing::{encode_connect_frame, ConnectFrameDecoder};
use crate::transport::{BridgeTransport, ByteStream, ReqwestBridgeTransport};
use crate::types::*;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::sync::Arc;
use std::time::Duration;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone)]
pub struct CursorClientConfig {
    pub base_url: String,
    pub bearer_token: String,
    pub timeout: Duration,
    pub allow_remote_endpoint: bool,
}

impl std::fmt::Debug for CursorClientConfig {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CursorClientConfig")
            .field("base_url", &self.base_url)
            .field("bearer_token", &"<redacted>")
            .field("timeout", &self.timeout)
            .field("allow_remote_endpoint", &self.allow_remote_endpoint)
            .finish()
    }
}

impl CursorClientConfig {
    pub fn new(base_url: impl Into<String>, bearer_token: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into(),
            bearer_token: bearer_token.into(),
            timeout: DEFAULT_TIMEOUT,
            allow_remote_endpoint: false,
        }
    }

    pub fn allow_remote_endpoint(mut self, allow: bool) -> Self {
        self.allow_remote_endpoint = allow;
        self
    }
}

#[derive(Clone)]
pub struct CursorClient {
    transport: Arc<dyn BridgeTransport>,
    bearer_token: String,
    timeout: Duration,
}

impl CursorClient {
    pub fn connect(config: CursorClientConfig) -> Result<Self, CursorSdkError> {
        validate_endpoint(&config.base_url, config.allow_remote_endpoint)?;
        let transport = ReqwestBridgeTransport::new_with_timeout(config.base_url, config.timeout)?;
        Self::with_transport_and_timeout(transport, config.bearer_token, config.timeout)
    }

    pub fn from_ready(ready: ReadyHandshake, timeout: Duration) -> Result<Self, CursorSdkError> {
        Self::from_ready_with_remote(ready, timeout, false)
    }

    pub fn from_ready_with_remote(
        ready: ReadyHandshake,
        timeout: Duration,
        allow_remote_endpoint: bool,
    ) -> Result<Self, CursorSdkError> {
        let token = ready
            .auth_token
            .clone()
            .filter(|token| !token.trim().is_empty())
            .map(Ok)
            .unwrap_or_else(|| ready.bearer_token_from_file())?;
        Self::connect(CursorClientConfig {
            base_url: ready.endpoint(),
            bearer_token: token,
            timeout,
            allow_remote_endpoint,
        })
    }

    pub fn with_transport<T>(
        transport: T,
        bearer_token: impl Into<String>,
    ) -> Result<Self, CursorSdkError>
    where
        T: BridgeTransport + 'static,
    {
        Self::with_transport_and_timeout(transport, bearer_token, DEFAULT_TIMEOUT)
    }

    pub fn with_transport_and_timeout<T>(
        transport: T,
        bearer_token: impl Into<String>,
        timeout: Duration,
    ) -> Result<Self, CursorSdkError>
    where
        T: BridgeTransport + 'static,
    {
        let bearer_token = bearer_token.into();
        if bearer_token.trim().is_empty() {
            return Err(CursorSdkError::Handshake(
                "bridge bearer token is empty".into(),
            ));
        }
        Ok(Self {
            transport: Arc::new(transport),
            bearer_token,
            timeout,
        })
    }

    pub fn from_shared_transport(
        transport: Arc<dyn BridgeTransport>,
        bearer_token: impl Into<String>,
        timeout: Duration,
    ) -> Result<Self, CursorSdkError> {
        let bearer_token = bearer_token.into();
        if bearer_token.trim().is_empty() {
            return Err(CursorSdkError::Handshake(
                "bridge bearer token is empty".into(),
            ));
        }
        Ok(Self {
            transport,
            bearer_token,
            timeout,
        })
    }

    pub async fn ping(&self) -> Result<Value, CursorSdkError> {
        self.unary("sdk.v1.SdkBridgeControlService/Ping", json!({}))
            .await
    }

    pub async fn get_version(&self) -> Result<Value, CursorSdkError> {
        self.unary("sdk.v1.SdkBridgeControlService/GetVersion", json!({}))
            .await
    }

    pub async fn create_agent(
        &self,
        options: AgentOptions,
        idempotency_key: Option<String>,
    ) -> Result<CreateAgentResponse, CursorSdkError> {
        let mut body = json!({ "options": options });
        if let Some(key) = idempotency_key {
            body["idempotencyKey"] = Value::String(key);
        }
        let value = self
            .unary("sdk.v1.SdkAgentService/CreateAgent", body)
            .await?;
        serde_json::from_value(value)
            .map_err(|error| CursorSdkError::Protocol(format!("CreateAgent response: {error}")))
    }

    pub async fn resume_agent(
        &self,
        agent_id: &str,
        options: AgentOptions,
    ) -> Result<ResumeAgentResponse, CursorSdkError> {
        let value = self
            .unary(
                "sdk.v1.SdkAgentService/ResumeAgent",
                json!({ "agentId": agent_id, "options": options }),
            )
            .await?;
        serde_json::from_value(value)
            .map_err(|error| CursorSdkError::Protocol(format!("ResumeAgent response: {error}")))
    }

    pub async fn reload_agent(&self, agent_id: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/ReloadAgent",
            json!({ "agentId": agent_id }),
        )
        .await
    }

    pub async fn close_agent(&self, agent_id: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/CloseAgent",
            json!({ "agentId": agent_id }),
        )
        .await
    }

    pub async fn send(
        &self,
        agent_id: &str,
        message: UserMessage,
        options: SendOptions,
        idempotency_key: Option<String>,
    ) -> Result<CursorRunStream, CursorSdkError> {
        let mut request = json!({
            "agentId": agent_id,
            "message": message,
            "options": options,
        });
        if let Some(key) = idempotency_key {
            request["idempotencyKey"] = Value::String(key);
        }
        let body = encode_connect_frame(&request)?;
        let stream = self
            .transport
            .stream(
                "sdk.v1.SdkAgentService/Send",
                &self.bearer_token,
                body,
                self.timeout,
            )
            .await?;
        Ok(CursorRunStream::new(stream))
    }

    pub async fn observe_run(
        &self,
        run_id: &str,
        after_offset: Option<&str>,
    ) -> Result<CursorRunStream, CursorSdkError> {
        let mut request = json!({ "runId": run_id });
        if let Some(offset) = after_offset {
            request["afterOffset"] = Value::String(offset.to_owned());
        }
        let body = encode_connect_frame(&request)?;
        let stream = self
            .transport
            .stream(
                "sdk.v1.SdkAgentService/ObserveRun",
                &self.bearer_token,
                body,
                self.timeout,
            )
            .await?;
        Ok(CursorRunStream::new(stream))
    }

    pub async fn cancel_run(
        &self,
        run_id: &str,
        agent_id: Option<&str>,
    ) -> Result<Value, CursorSdkError> {
        let mut body = json!({ "runId": run_id });
        if let Some(agent_id) = agent_id {
            body["agentId"] = Value::String(agent_id.to_owned());
        }
        self.unary("sdk.v1.SdkAgentService/CancelRun", body).await
    }

    pub async fn cancel_and_wait(
        &self,
        run_id: &str,
        agent_id: Option<&str>,
    ) -> Result<Value, CursorSdkError> {
        self.cancel_run(run_id, agent_id).await?;
        self.wait_live_run(run_id).await
    }

    pub async fn wait_live_run(&self, run_id: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/WaitLiveRun",
            json!({ "runId": run_id }),
        )
        .await
    }

    pub async fn get_run(
        &self,
        run_id: &str,
        options: Option<Value>,
    ) -> Result<Value, CursorSdkError> {
        let mut body = json!({ "runId": run_id });
        if let Some(options) = options {
            body["options"] = options;
        }
        self.unary("sdk.v1.SdkAgentService/GetRun", body).await
    }

    pub async fn list_runs(
        &self,
        agent_id: &str,
        options: Option<Value>,
    ) -> Result<Value, CursorSdkError> {
        let mut body = json!({ "agentId": agent_id });
        if let Some(options) = options {
            body["options"] = options;
        }
        self.unary("sdk.v1.SdkAgentService/ListRuns", body).await
    }

    pub async fn get_run_conversation(&self, run_id: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/GetRunConversation",
            json!({ "runId": run_id }),
        )
        .await
    }

    pub async fn list_agents(&self, options: Option<Value>) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/ListAgents",
            json!({ "options": options.unwrap_or_else(|| json!({})) }),
        )
        .await
    }

    pub async fn set_tool_callback(
        &self,
        url: &str,
        auth_token: &str,
    ) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkBridgeControlService/SetToolCallback",
            json!({ "url": url, "authToken": auth_token }),
        )
        .await
    }

    pub async fn list_agent_messages(&self, agent_id: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkAgentService/ListAgentMessages",
            json!({ "agentId": agent_id }),
        )
        .await
    }

    pub async fn list_models(&self, api_key: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkCursorService/ListModels",
            json!({ "options": { "apiKey": api_key } }),
        )
        .await
    }

    pub async fn me(&self, api_key: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkCursorService/Me",
            json!({ "options": { "apiKey": api_key } }),
        )
        .await
    }

    pub async fn list_repositories(&self, api_key: &str) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkCursorService/ListRepositories",
            json!({ "options": { "apiKey": api_key } }),
        )
        .await
    }

    pub async fn shutdown(&self, grace_seconds: u32) -> Result<Value, CursorSdkError> {
        self.unary(
            "sdk.v1.SdkBridgeControlService/Shutdown",
            json!({ "graceSeconds": grace_seconds }),
        )
        .await
    }

    pub async fn close(&self) -> Result<(), CursorSdkError> {
        self.transport.close().await
    }

    async fn unary(&self, path: &str, body: Value) -> Result<Value, CursorSdkError> {
        self.transport
            .unary(path, &self.bearer_token, body, self.timeout)
            .await
    }
}

fn validate_endpoint(base_url: &str, allow_remote_endpoint: bool) -> Result<(), CursorSdkError> {
    let Some((scheme, remainder)) = base_url.split_once("://") else {
        return Err(CursorSdkError::Handshake(
            "bridge endpoint must use http or https".into(),
        ));
    };
    if !matches!(scheme, "http" | "https") {
        return Err(CursorSdkError::Handshake(
            "bridge endpoint must use http or https".into(),
        ));
    }
    if allow_remote_endpoint {
        return Ok(());
    }
    let authority = remainder.split('/').next().unwrap_or_default();
    let authority = authority.rsplit('@').next().unwrap_or(authority);
    let host = if let Some(host) = authority.strip_prefix('[') {
        host.split(']').next().unwrap_or(host)
    } else {
        authority
            .rsplit_once(':')
            .map_or(authority, |(host, _)| host)
    };
    let is_loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    if is_loopback {
        Ok(())
    } else {
        Err(CursorSdkError::Handshake(
            "non-loopback bridge endpoint requires explicit remote access".into(),
        ))
    }
}

pub struct CursorRunStream {
    stream: Box<dyn ByteStream>,
    decoder: ConnectFrameDecoder,
    pending: VecDeque<RunStreamMessage>,
    finished: bool,
}

impl CursorRunStream {
    fn new(stream: Box<dyn ByteStream>) -> Self {
        Self {
            stream,
            decoder: ConnectFrameDecoder::default(),
            pending: VecDeque::new(),
            finished: false,
        }
    }

    pub async fn next(&mut self) -> Result<Option<RunStreamMessage>, CursorSdkError> {
        loop {
            if let Some(value) = self.pending.pop_front() {
                return Ok(Some(value));
            }
            if self.finished {
                return Ok(None);
            }
            match self.stream.next_chunk().await? {
                Some(chunk) => {
                    let values = self.decoder.push(&chunk)?;
                    for value in values {
                        let message: RunStreamMessage =
                            serde_json::from_value(value).map_err(|error| {
                                CursorSdkError::Protocol(format!("RunStreamMessage: {error}"))
                            })?;
                        if message.done.is_some() {
                            self.finished = true;
                        }
                        if !message.is_empty_envelope() {
                            self.pending.push_back(message);
                        }
                    }
                }
                None => {
                    self.decoder.finish()?;
                    self.finished = true;
                }
            }
        }
    }

    pub async fn close(&mut self) -> Result<(), CursorSdkError> {
        self.finished = true;
        self.stream.close().await
    }
}
