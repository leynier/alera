//! Thin control-request wrappers of [`ClaudeClient`].

use super::ClaudeClient;
use crate::error::Result;
use serde_json::Value;

impl ClaudeClient {
    pub async fn interrupt(&self) -> Result<()> {
        self.control_command(
            serde_json::json!({ "subtype": "interrupt" }),
            self.options.initialize_timeout,
        )
        .await
        .map(|_| ())
    }

    pub async fn set_permission_mode(&self, mode: impl Into<String>) -> Result<()> {
        self.control_command(
            serde_json::json!({ "subtype": "set_permission_mode", "mode": mode.into() }),
            self.options.initialize_timeout,
        )
        .await
        .map(|_| ())
    }

    pub async fn set_model(&self, model: Option<String>) -> Result<()> {
        self.control_command(
            serde_json::json!({ "subtype": "set_model", "model": model }),
            self.options.initialize_timeout,
        )
        .await
        .map(|_| ())
    }

    pub async fn get_mcp_status(&self) -> Result<Value> {
        self.control_command(
            serde_json::json!({ "subtype": "mcp_status" }),
            self.options.initialize_timeout,
        )
        .await
    }

    pub async fn get_context_usage(&self) -> Result<Value> {
        self.control_command(
            serde_json::json!({ "subtype": "get_context_usage" }),
            self.options.initialize_timeout,
        )
        .await
    }

    pub async fn reconnect_mcp_server(&self, server_name: impl Into<String>) -> Result<()> {
        self.control_command(
            serde_json::json!({ "subtype": "mcp_reconnect", "serverName": server_name.into() }),
            self.options.initialize_timeout,
        )
        .await
        .map(|_| ())
    }

    pub async fn toggle_mcp_server(
        &self,
        server_name: impl Into<String>,
        enabled: bool,
    ) -> Result<()> {
        self.control_command(serde_json::json!({ "subtype": "mcp_toggle", "serverName": server_name.into(), "enabled": enabled }), self.options.initialize_timeout).await.map(|_| ())
    }

    pub async fn stop_task(&self, task_id: impl Into<String>) -> Result<()> {
        self.control_command(
            serde_json::json!({ "subtype": "stop_task", "task_id": task_id.into() }),
            self.options.initialize_timeout,
        )
        .await
        .map(|_| ())
    }
}
