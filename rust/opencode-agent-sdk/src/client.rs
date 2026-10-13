use crate::error::OpenCodeError;
use crate::mcp::PermissionRule;
use crate::model::{OpenCodeEvent, OpenCodeResponse, OpenCodeSession};
use crate::sse::{SseDecoder, SseFrame, DEFAULT_MAX_SSE_EVENT_BYTES};
use crate::transport::{request_with_body, ByteStream, HttpRequest, HttpResponse, HttpTransport};
use crate::wire::{
    is_execution_boundary, is_unknown_v2, model_value, parse_session, percent_encode_query,
    prompt_body,
};
use base64::Engine;
use serde_json::{json, Value};
use std::collections::VecDeque;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Generation {
    Legacy1,
    V2,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientConfig {
    pub base_url: String,
    pub directory: Option<String>,
    pub password: Option<String>,
    pub generation: Generation,
    pub max_sse_event_bytes: usize,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            base_url: "http://127.0.0.1:4096".into(),
            directory: None,
            password: None,
            generation: Generation::V2,
            max_sse_event_bytes: DEFAULT_MAX_SSE_EVENT_BYTES,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SessionRequest {
    pub title: Option<String>,
    pub directory: Option<String>,
    pub parent_id: Option<String>,
    pub permissions: Option<Vec<PermissionRule>>,
}

pub struct OpenCodeClient<T: HttpTransport> {
    transport: T,
    config: ClientConfig,
    stream: Option<Box<dyn ByteStream>>,
    decoder: SseDecoder,
    decoded_frames: VecDeque<SseFrame>,
    closed: bool,
}

impl<T: HttpTransport> OpenCodeClient<T> {
    pub fn new(transport: T, config: ClientConfig) -> Self {
        let max = config.max_sse_event_bytes;
        Self {
            transport,
            config,
            stream: None,
            decoder: SseDecoder::new(max),
            decoded_frames: VecDeque::new(),
            closed: false,
        }
    }

    pub fn config(&self) -> &ClientConfig {
        &self.config
    }

    /// Sets the workspace query used by directory-scoped server routes.
    pub fn set_directory(&mut self, directory: Option<String>) {
        self.config.directory = directory;
    }

    pub fn transport(&self) -> &T {
        &self.transport
    }

    pub fn transport_mut(&mut self) -> &mut T {
        &mut self.transport
    }

    pub fn into_transport(self) -> T {
        self.transport
    }

    pub async fn raw_request(
        &mut self,
        method: &str,
        path: &str,
        body: Option<Value>,
    ) -> Result<OpenCodeResponse, OpenCodeError> {
        self.ensure_open()?;
        let request = self.request(method, path, body, false)?;
        let response = self.transport.request(request).await?;
        self.check_response(response)
    }

    pub async fn create_session(
        &mut self,
        input: SessionRequest,
    ) -> Result<OpenCodeSession, OpenCodeError> {
        let mut body = serde_json::Map::new();
        if let Some(title) = input.title {
            body.insert("title".into(), Value::String(title));
        }
        if let Some(directory) = input.directory.or_else(|| self.config.directory.clone()) {
            body.insert("directory".into(), Value::String(directory));
        }
        if let Some(parent_id) = input.parent_id {
            body.insert("parentID".into(), Value::String(parent_id));
        }
        if let Some(permissions) = input.permissions {
            body.insert(
                "permissions".into(),
                serde_json::to_value(permissions)
                    .map_err(|error| OpenCodeError::protocol(error.to_string()))?,
            );
        }
        let response = self
            .raw_request("POST", "/session", Some(Value::Object(body)))
            .await?;
        parse_session(response.body)
    }

    pub async fn resume_session(&mut self, id: &str) -> Result<OpenCodeSession, OpenCodeError> {
        self.get_session(id).await
    }

    pub async fn get_session(&mut self, id: &str) -> Result<OpenCodeSession, OpenCodeError> {
        let response = self
            .raw_request("GET", &format!("/session/{id}"), None)
            .await?;
        parse_session(response.body)
    }

    pub async fn read_session(&mut self, id: &str) -> Result<OpenCodeSession, OpenCodeError> {
        self.get_session(id).await
    }

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
        let path = match self.config.generation {
            Generation::Legacy1 => format!("/session/{session_id}/prompt_async"),
            Generation::V2 => format!("/session/{session_id}/prompt"),
        };
        let mut body = match self.config.generation {
            Generation::Legacy1 => json!({ "parts": parts }),
            Generation::V2 => prompt_body(parts),
        };
        if let Some(message_id) = message_id {
            let field = if self.config.generation == Generation::V2 {
                "id"
            } else {
                "messageID"
            };
            body[field] = Value::String(message_id.to_owned());
        }
        if let Some(model) = model {
            body["model"] = model_value(model);
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
        let command_field = if self.config.generation == Generation::V2 {
            "name"
        } else {
            "command"
        };
        let body = if self.config.generation == Generation::V2 {
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
        let path = match self.config.generation {
            Generation::Legacy1 => format!("/session/{session_id}/summarize"),
            Generation::V2 => format!("/session/{session_id}/compact"),
        };
        Ok(self.raw_request("POST", &path, Some(json!({}))).await?.body)
    }

    pub async fn abort(&mut self, session_id: &str) -> Result<Value, OpenCodeError> {
        let action = if self.config.generation == Generation::V2 {
            "interrupt"
        } else {
            "abort"
        };
        let path = format!("/session/{session_id}/{action}");
        Ok(self.raw_request("POST", &path, Some(json!({}))).await?.body)
    }

    pub async fn permission_reply(
        &mut self,
        session_id: &str,
        request_id: &str,
        reply: &str,
    ) -> Result<Value, OpenCodeError> {
        let path = match self.config.generation {
            Generation::Legacy1 => format!("/permission/{request_id}/reply"),
            Generation::V2 => format!("/session/{session_id}/permission/{request_id}/reply"),
        };
        let body = if self.config.generation == Generation::V2 {
            let mut body = json!({ "decision": reply });
            if reply == "reject" {
                body["message"] = Value::String("OpenCode request declined".into());
            }
            body
        } else {
            json!({ "reply": reply })
        };
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }

    pub async fn question_reply(
        &mut self,
        session_id: &str,
        request_id: &str,
        answers: Vec<(String, Vec<String>)>,
    ) -> Result<Value, OpenCodeError> {
        let path = match self.config.generation {
            Generation::Legacy1 => format!("/question/{request_id}/reply"),
            Generation::V2 => format!("/session/{session_id}/form/{request_id}/reply"),
        };
        let body = if self.config.generation == Generation::V2 {
            let answer = answers
                .into_iter()
                .map(|(question_id, values)| {
                    (
                        question_id,
                        Value::Array(values.into_iter().map(Value::String).collect()),
                    )
                })
                .collect::<serde_json::Map<_, _>>();
            json!({ "answer": answer })
        } else {
            json!({ "answers": answers.into_iter().map(|(_, values)| values).collect::<Vec<_>>() })
        };
        Ok(self.raw_request("POST", &path, Some(body)).await?.body)
    }

    pub async fn question_cancel(
        &mut self,
        session_id: &str,
        request_id: &str,
    ) -> Result<Value, OpenCodeError> {
        let path = match self.config.generation {
            Generation::Legacy1 => format!("/question/{request_id}/reject"),
            Generation::V2 => format!("/session/{session_id}/form/{request_id}"),
        };
        let method = if self.config.generation == Generation::V2 {
            "DELETE"
        } else {
            "POST"
        };
        Ok(self.raw_request(method, &path, None).await?.body)
    }

    pub async fn start_events(&mut self) -> Result<(), OpenCodeError> {
        self.ensure_open()?;
        if self.stream.is_some() {
            return Err(OpenCodeError::protocol(
                "OpenCode event stream is already open",
            ));
        }
        let request = self.request("GET", "/event", None, true)?;
        self.stream = Some(self.transport.open_stream(request).await?);
        Ok(())
    }

    pub async fn next_event(&mut self) -> Result<Option<OpenCodeEvent>, OpenCodeError> {
        self.ensure_open()?;
        loop {
            if let Some(event) = self.next_decoded_frame()? {
                if let Some(event) = self.decode_event(event)? {
                    return Ok(Some(event));
                }
            }
            let stream = self
                .stream
                .as_mut()
                .ok_or_else(|| OpenCodeError::protocol("OpenCode event stream is not open"))?;
            let chunk = stream.next_chunk().await?;
            match chunk {
                Some(chunk) => {
                    let frames = self.decoder.push(&chunk)?;
                    self.decoded_frames.extend(frames);
                }
                None => {
                    let frames = self.decoder.finish()?;
                    self.decoded_frames.extend(frames);
                    self.stream = None;
                    if self.decoded_frames.is_empty() {
                        return Ok(None);
                    }
                }
            }
        }
    }

    pub async fn close(&mut self) -> Result<(), OpenCodeError> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        if let Some(stream) = self.stream.as_mut() {
            stream.close().await?;
        }
        self.stream = None;
        Ok(())
    }

    fn ensure_open(&self) -> Result<(), OpenCodeError> {
        if self.closed {
            Err(OpenCodeError::Closed)
        } else {
            Ok(())
        }
    }

    fn request(
        &self,
        method: &str,
        path: &str,
        body: Option<Value>,
        stream: bool,
    ) -> Result<HttpRequest, OpenCodeError> {
        let route = if self.config.generation == Generation::V2 && !path.starts_with("/api/") {
            format!("/api{path}")
        } else {
            path.to_owned()
        };
        let mut url = format!("{}{}", self.config.base_url.trim_end_matches('/'), route);
        if let Some(directory) = &self.config.directory {
            if !url.contains('?') {
                url.push('?');
            } else {
                url.push('&');
            }
            url.push_str("directory=");
            url.push_str(&percent_encode_query(directory));
        }
        let mut request = HttpRequest::new(method, url);
        request.headers.insert(
            "accept".into(),
            if stream {
                "text/event-stream"
            } else {
                "application/json"
            }
            .into(),
        );
        if let Some(password) = &self.config.password {
            let token = base64::engine::general_purpose::STANDARD
                .encode(format!("opencode:{password}").as_bytes());
            request
                .headers
                .insert("authorization".into(), format!("Basic {token}"));
        }
        request_with_body(request, body)
    }

    fn check_response(&self, response: HttpResponse) -> Result<OpenCodeResponse, OpenCodeError> {
        let (status, body) = crate::transport::parse_json_body(response)?;
        if !(200..300).contains(&status) {
            return Err(OpenCodeError::Http {
                status,
                message: body.to_string(),
            });
        }
        Ok(OpenCodeResponse { status, body })
    }

    fn next_decoded_frame(&mut self) -> Result<Option<SseFrame>, OpenCodeError> {
        Ok(self.decoded_frames.pop_front())
    }

    fn decode_event(&self, frame: SseFrame) -> Result<Option<OpenCodeEvent>, OpenCodeError> {
        let payload: Value = serde_json::from_str(&frame.data)
            .map_err(|error| OpenCodeError::protocol(format!("invalid SSE JSON: {error}")))?;
        let event_type = payload
            .get("type")
            .and_then(Value::as_str)
            .or(frame.event.as_deref())
            .ok_or_else(|| OpenCodeError::protocol("OpenCode SSE event has no type"))?
            .to_owned();
        let session_id = payload
            .get("properties")
            .and_then(|properties| properties.get("sessionID"))
            .or_else(|| payload.get("data").and_then(|data| data.get("sessionID")))
            .or_else(|| payload.get("sessionID"))
            .and_then(Value::as_str)
            .map(str::to_owned);
        let terminal = matches!(
            event_type.as_str(),
            "session.idle"
                | "session.execution.succeeded"
                | "session.execution.failed"
                | "session.execution.interrupted"
                | "session.error"
                | "unreadable.execution.ended"
        );
        if self.config.generation == Generation::V2 && is_unknown_v2(&event_type) {
            if is_execution_boundary(&event_type) && session_id.is_some() {
                return Ok(Some(OpenCodeEvent {
                    event_type: if event_type.ends_with("started") {
                        "unreadable.execution.started".into()
                    } else {
                        "unreadable.execution.ended".into()
                    },
                    session_id,
                    payload: payload.clone(),
                    raw: payload,
                    terminal: !event_type.ends_with("started"),
                }));
            }
            return Ok(None);
        }
        Ok(Some(OpenCodeEvent {
            event_type,
            session_id,
            payload: payload.clone(),
            raw: payload,
            terminal,
        }))
    }
}
