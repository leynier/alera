use crate::{Generation, OpenCodeClient, OpenCodeError};
use alera_agent_http::HttpTransport;
use serde_json::{Map, Value};

impl<T: HttpTransport> OpenCodeClient<T> {
    pub async fn form_reply(
        &mut self,
        session_id: &str,
        form_id: &str,
        answers: Vec<(String, Value)>,
    ) -> Result<Value, OpenCodeError> {
        if self.config().generation != Generation::V2 {
            return Err(OpenCodeError::Unsupported(
                "OpenCode forms are only available in generation 2".into(),
            ));
        }
        let answer = answers.into_iter().collect::<Map<_, _>>();
        let path = format!("/session/{session_id}/form/{form_id}/reply");
        Ok(self
            .raw_request("POST", &path, Some(serde_json::json!({ "answer": answer })))
            .await?
            .body)
    }
}
