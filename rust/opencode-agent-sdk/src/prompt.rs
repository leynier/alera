use crate::wire::{model_value, prompt_body};
use crate::{Generation, OpenCodeClient, OpenCodeError};
use alera_agent_http::HttpTransport;
use serde_json::{json, Value};

impl<T: HttpTransport> OpenCodeClient<T> {
    pub async fn prompt(
        &mut self,
        session_id: &str,
        text: &str,
        model: Option<&str>,
    ) -> Result<Value, OpenCodeError> {
        self.prompt_parts(
            session_id,
            vec![json!({ "type": "text", "text": text })],
            model,
        )
        .await
    }

    pub async fn prompt_parts(
        &mut self,
        session_id: &str,
        parts: Vec<Value>,
        model: Option<&str>,
    ) -> Result<Value, OpenCodeError> {
        self.prompt_parts_with_id(session_id, parts, model, None)
            .await
    }

    pub async fn prompt_parts_with_id(
        &mut self,
        session_id: &str,
        parts: Vec<Value>,
        model: Option<&str>,
        message_id: Option<&str>,
    ) -> Result<Value, OpenCodeError> {
        self.prompt_parts_with_skills(session_id, parts, model, message_id, &[])
            .await
    }

    /// A prompt that also loads the named skills. Only the 2.x route takes
    /// skills; its `skills` field lists their ids.
    pub async fn prompt_parts_with_skills(
        &mut self,
        session_id: &str,
        parts: Vec<Value>,
        model: Option<&str>,
        message_id: Option<&str>,
        skills: &[String],
    ) -> Result<Value, OpenCodeError> {
        if !skills.is_empty() && self.config().generation == Generation::Legacy1 {
            return Err(OpenCodeError::Unsupported(
                "OpenCode 1.x prompts cannot name skills".into(),
            ));
        }
        let path = match self.config().generation {
            Generation::Legacy1 => format!("/session/{session_id}/prompt_async"),
            Generation::V2 => format!("/session/{session_id}/prompt"),
        };
        let mut body = match self.config().generation {
            Generation::Legacy1 => json!({ "parts": parts }),
            Generation::V2 => prompt_body(parts),
        };
        if let Some(message_id) = message_id {
            let field = if self.config().generation == Generation::V2 {
                "id"
            } else {
                "messageID"
            };
            body[field] = Value::String(message_id.to_owned());
        }
        if let Some(model) = model {
            body["model"] = model_value(model);
        }
        if !skills.is_empty() {
            body["skills"] = skills.iter().map(|id| json!({ "id": id })).collect();
        }
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }

    pub async fn command(
        &mut self,
        session_id: &str,
        command: &str,
        arguments: Option<Value>,
    ) -> Result<Value, OpenCodeError> {
        let path = format!("/session/{session_id}/command");
        let command_field = if self.config().generation == Generation::V2 {
            "name"
        } else {
            "command"
        };
        let body = if self.config().generation == Generation::V2 {
            let text = match arguments {
                Some(Value::String(text)) => text,
                Some(value) => value.to_string(),
                None => String::new(),
            };
            json!({ "name": command, "text": text })
        } else {
            let mut body = json!({ command_field: command });
            if let Some(arguments) = arguments {
                body["arguments"] = arguments;
            }
            body
        };
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }

    pub async fn compact(&mut self, session_id: &str) -> Result<Value, OpenCodeError> {
        let path = match self.config().generation {
            Generation::Legacy1 => format!("/session/{session_id}/summarize"),
            Generation::V2 => format!("/session/{session_id}/compact"),
        };
        Ok(self.raw_request("POST", &path, Some(json!({}))).await?.body)
    }
}
