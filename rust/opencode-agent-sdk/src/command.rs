use crate::{Generation, OpenCodeClient, OpenCodeError};
use alera_agent_http::HttpTransport;
use serde_json::{json, Map, Value};

/// A command run through OpenCode's command route instead of as a prompt.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CommandRequest {
    pub name: String,
    /// Everything typed after the command name.
    pub arguments: String,
    /// 1.x only: the id of the user message the command creates.
    pub message_id: Option<String>,
    /// 1.x only: the `provider/model` that answers.
    pub model: Option<String>,
    /// 1.x only: file parts sent along, in prompt part form.
    pub files: Vec<Value>,
}

impl<T: HttpTransport> OpenCodeClient<T> {
    /// 2.x answers once it admits the command; 1.x answers only when the
    /// command's reply is complete.
    pub async fn run_command(
        &mut self,
        session_id: &str,
        request: CommandRequest,
    ) -> Result<Value, OpenCodeError> {
        let body = match self.config().generation {
            Generation::V2 => json!({ "name": request.name, "text": request.arguments }),
            Generation::Legacy1 => {
                let mut body = Map::new();
                if let Some(message_id) = request.message_id {
                    body.insert("messageID".into(), Value::String(message_id));
                }
                body.insert("command".into(), Value::String(request.name));
                body.insert("arguments".into(), Value::String(request.arguments));
                if let Some(model) = request.model {
                    body.insert("model".into(), Value::String(model));
                }
                body.insert("parts".into(), Value::Array(request.files));
                Value::Object(body)
            }
        };
        let path = format!("/session/{session_id}/command");
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }

    /// Compacts the session as a turn. 2.x admits `/compact` under the
    /// turn's prompt id; 1.x `/summarize` needs the `provider/model` that
    /// writes the summary and answers when it is written.
    pub async fn compact_session(
        &mut self,
        session_id: &str,
        message_id: Option<&str>,
        model: Option<&str>,
    ) -> Result<Value, OpenCodeError> {
        let (path, body) = match self.config().generation {
            Generation::V2 => {
                let mut body = Map::new();
                if let Some(message_id) = message_id {
                    body.insert("id".into(), Value::String(message_id.to_owned()));
                }
                (
                    format!("/session/{session_id}/compact"),
                    Value::Object(body),
                )
            }
            Generation::Legacy1 => {
                let (provider_id, model_id) = model
                    .and_then(|model| model.split_once('/'))
                    .filter(|(provider, model)| !provider.is_empty() && !model.is_empty())
                    .ok_or_else(|| {
                        OpenCodeError::Unsupported(
                            "OpenCode 1.x compaction needs a provider/model".into(),
                        )
                    })?;
                (
                    format!("/session/{session_id}/summarize"),
                    json!({ "providerID": provider_id, "modelID": model_id, "auto": false }),
                )
            }
        };
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }
}
