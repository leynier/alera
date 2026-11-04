use crate::client::{AcpClient, PendingCallKind};
use crate::error::AcpError;
use crate::schema::{AcpProtocolGeneration, AcpSessionResponse};
use alera_agent_transport::JsonTransport;
use serde_json::{json, Value};

impl<T: JsonTransport> AcpClient<T> {
    pub async fn new_session(
        &mut self,
        cwd: Option<&str>,
        mcp_servers: &[Value],
    ) -> Result<AcpSessionResponse, AcpError> {
        let mut params = serde_json::Map::new();
        params.insert("cwd".into(), Value::String(cwd.unwrap_or(".").to_owned()));
        params.insert("mcpServers".into(), Value::Array(mcp_servers.to_vec()));
        let value = self
            .call(
                "session/new",
                Value::Object(params),
                PendingCallKind::Session,
            )
            .await?;
        let result = AcpSessionResponse::from_value(value);
        if result.session_id.is_none() {
            return Err(AcpError::Protocol(
                "session/new response lacks sessionId".into(),
            ));
        }
        Ok(result)
    }

    pub async fn resume_session(
        &mut self,
        session_id: &str,
        cwd: Option<&str>,
    ) -> Result<AcpSessionResponse, AcpError> {
        self.resume_session_with_mcp(session_id, cwd, &[]).await
    }

    pub async fn resume_session_with_mcp(
        &mut self,
        session_id: &str,
        cwd: Option<&str>,
        mcp_servers: &[Value],
    ) -> Result<AcpSessionResponse, AcpError> {
        let params = json!({
            "sessionId": session_id,
            "cwd": cwd.unwrap_or("."),
            "mcpServers": mcp_servers,
        });
        let value = self
            .call("session/resume", params, PendingCallKind::Session)
            .await?;
        Ok(AcpSessionResponse::from_value(value))
    }

    pub async fn load_session(
        &mut self,
        session_id: &str,
        cwd: Option<&str>,
    ) -> Result<AcpSessionResponse, AcpError> {
        self.load_session_with_mcp(session_id, cwd, &[]).await
    }

    pub async fn load_session_with_mcp(
        &mut self,
        session_id: &str,
        cwd: Option<&str>,
        mcp_servers: &[Value],
    ) -> Result<AcpSessionResponse, AcpError> {
        match self.initialized().map(|response| response.generation) {
            Some(AcpProtocolGeneration::V1) | None => {
                self.load_session_v1(session_id, cwd, mcp_servers).await
            }
            Some(AcpProtocolGeneration::V2) => {
                self.resume_session_with_mcp(session_id, cwd, mcp_servers)
                    .await
            }
        }
    }

    async fn load_session_v1(
        &mut self,
        session_id: &str,
        cwd: Option<&str>,
        mcp_servers: &[Value],
    ) -> Result<AcpSessionResponse, AcpError> {
        let value = self
            .call(
                "session/load",
                json!({"sessionId": session_id, "cwd": cwd.unwrap_or("."), "mcpServers": mcp_servers}),
                PendingCallKind::Session,
            )
            .await?;
        Ok(AcpSessionResponse::from_value(value))
    }

    pub async fn set_model(&mut self, session_id: &str, model: &str) -> Result<Value, AcpError> {
        match self.initialized().map(|response| response.generation) {
            Some(AcpProtocolGeneration::V1) | None => {
                self.call(
                    "session/set_model",
                    json!({"sessionId": session_id, "modelId": model}),
                    PendingCallKind::Config,
                )
                .await
            }
            Some(AcpProtocolGeneration::V2) => {
                self.set_config_option(session_id, "model", Value::String(model.to_owned()))
                    .await
            }
        }
    }

    pub async fn set_mode(&mut self, session_id: &str, mode: &str) -> Result<Value, AcpError> {
        match self.initialized().map(|response| response.generation) {
            Some(AcpProtocolGeneration::V2) => {
                self.set_config_option(session_id, "mode", Value::String(mode.to_owned()))
                    .await
            }
            Some(AcpProtocolGeneration::V1) | None => {
                self.call(
                    "session/set_mode",
                    json!({"sessionId": session_id, "modeId": mode}),
                    PendingCallKind::Config,
                )
                .await
            }
        }
    }

    pub async fn set_config_option(
        &mut self,
        session_id: &str,
        config_id: &str,
        value: Value,
    ) -> Result<Value, AcpError> {
        let mut params = json!({"sessionId": session_id, "configId": config_id, "value": value});
        if self
            .initialized()
            .is_some_and(|response| response.generation == AcpProtocolGeneration::V2)
        {
            let value_type = match params.get("value") {
                Some(Value::Bool(_)) => "boolean",
                Some(Value::String(_)) => "id",
                _ => "json",
            };
            params["type"] = Value::String(value_type.into());
        }
        self.call("session/set_config_option", params, PendingCallKind::Config)
            .await
    }
}
