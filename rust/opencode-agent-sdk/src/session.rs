use crate::{OpenCodeClient, OpenCodeError};
use alera_agent_http::HttpTransport;
use serde_json::Value;

impl<T: HttpTransport> OpenCodeClient<T> {
    /// Read the native message history used to resume or reconstruct a session.
    pub async fn read_messages(&mut self, session_id: &str) -> Result<Vec<Value>, OpenCodeError> {
        let response = self
            .raw_request("GET", &format!("/session/{session_id}/message"), None)
            .await?;
        let body = if let Some(data) = response.body.get("data").cloned() {
            data
        } else {
            response.body
        };
        body.as_array()
            .cloned()
            .ok_or_else(|| OpenCodeError::protocol("OpenCode messages response is not an array"))
    }
}
