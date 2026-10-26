use crate::{Generation, OpenCodeClient, OpenCodeError};
use alera_agent_http::HttpTransport;
use serde_json::Value;

impl<T: HttpTransport> OpenCodeClient<T> {
    /// The skills OpenCode loads for the client's directory. 1.x answers
    /// `GET /skill` with `{name, description, location}` entries; 2.x answers
    /// `GET /api/skill` with `{id, name, description, path}` entries under
    /// `data`.
    pub async fn list_skills(&mut self) -> Result<Vec<Value>, OpenCodeError> {
        self.list("/skill").await
    }

    /// The commands OpenCode offers for the client's directory.
    pub async fn list_commands(&mut self) -> Result<Vec<Value>, OpenCodeError> {
        self.list("/command").await
    }

    async fn list(&mut self, path: &str) -> Result<Vec<Value>, OpenCodeError> {
        let body = self.raw_request("GET", path, None).await?.body;
        let entries = match self.config().generation {
            Generation::Legacy1 => &body,
            Generation::V2 => body.get("data").unwrap_or(&Value::Null),
        };
        entries
            .as_array()
            .cloned()
            .ok_or_else(|| OpenCodeError::protocol(format!("OpenCode {path} is not a list")))
    }
}
