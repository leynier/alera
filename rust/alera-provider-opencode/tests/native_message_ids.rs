use alera_provider_opencode::opencode_agent_sdk::HttpError;
use alera_provider_opencode::{
    ByteStream, ChunkStream, HttpRequest, HttpResponse, HttpTransport, OpenCodeGeneration,
    OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput, TurnInput};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};

const NATIVE_SESSION_ID: &str = "ses_shared";
const BASE_URL: &str = "http://127.0.0.1:4096";

#[derive(Default)]
struct ServerState {
    requests: Vec<HttpRequest>,
    message_ids: HashSet<String>,
}

#[derive(Clone)]
struct SchemaTransport {
    generation: OpenCodeGeneration,
    state: Arc<Mutex<ServerState>>,
}

impl SchemaTransport {
    fn new(generation: OpenCodeGeneration) -> Self {
        Self {
            generation,
            state: Arc::new(Mutex::new(ServerState::default())),
        }
    }

    fn route(&self, route: &str) -> String {
        let prefix = match self.generation {
            OpenCodeGeneration::Legacy1 => "",
            OpenCodeGeneration::V2 => "/api",
        };
        format!("{BASE_URL}{prefix}{route}")
    }

    fn prompt_route(&self) -> String {
        let action = match self.generation {
            OpenCodeGeneration::Legacy1 => "prompt_async",
            OpenCodeGeneration::V2 => "prompt",
        };
        self.route(&format!("/session/{NATIVE_SESSION_ID}/{action}"))
    }

    fn message_id_field(&self) -> &str {
        match self.generation {
            OpenCodeGeneration::Legacy1 => "messageID",
            OpenCodeGeneration::V2 => "id",
        }
    }
}

#[async_trait]
impl HttpTransport for SchemaTransport {
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        let mut state = self.state.lock().unwrap();
        state.requests.push(request.clone());
        if request.method == "POST" && request.path == self.prompt_route() {
            let body: Value = serde_json::from_slice(&request.body).unwrap();
            let message_id = body[self.message_id_field()].as_str().unwrap();
            // The upstream schemas require "msg" for V1 and "msg_" for V2.
            let prefix = match self.generation {
                OpenCodeGeneration::Legacy1 => "msg",
                OpenCodeGeneration::V2 => "msg_",
            };
            if !message_id.starts_with(prefix) {
                return Ok(HttpResponse::new(
                    400,
                    br#"{"name":"BadRequestError","data":{"message":"Invalid message ID"}}"#,
                ));
            }
            if !state.message_ids.insert(message_id.to_owned()) {
                return Ok(HttpResponse::new(
                    409,
                    br#"{"name":"ConflictError","data":{"message":"Duplicate message ID"}}"#,
                ));
            }
            return Ok(match self.generation {
                OpenCodeGeneration::Legacy1 => HttpResponse::new(204, Vec::new()),
                OpenCodeGeneration::V2 => HttpResponse::new(
                    200,
                    serde_json::to_vec(&json!({ "id": message_id })).unwrap(),
                ),
            });
        }
        assert!(
            (request.method == "POST" && request.path == self.route("/session"))
                || (request.method == "GET"
                    && request.path == self.route(&format!("/session/{NATIVE_SESSION_ID}"))),
            "unexpected scripted request: {request:?}"
        );
        Ok(HttpResponse::new(
            200,
            serde_json::to_vec(&json!({ "id": NATIVE_SESSION_ID })).unwrap(),
        ))
    }

    async fn open_stream(&self, request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        assert_eq!(request.method, "GET");
        assert_eq!(request.path, self.route("/event"));
        self.state.lock().unwrap().requests.push(request);
        let event_type = match self.generation {
            OpenCodeGeneration::Legacy1 => "session.idle",
            OpenCodeGeneration::V2 => "session.execution.succeeded",
        };
        let terminal = format!(
            "data: {}\n\n",
            json!({ "type": event_type, "properties": { "sessionID": NATIVE_SESSION_ID } })
        );
        Ok(Box::new(ChunkStream::from_chunks([
            terminal.as_bytes().to_vec(),
            terminal.as_bytes().to_vec(),
        ])))
    }
}

#[tokio::test]
async fn scripted_http_rejects_the_old_native_message_id_for_both_wire_fields() {
    for generation in [OpenCodeGeneration::Legacy1, OpenCodeGeneration::V2] {
        let transport = SchemaTransport::new(generation);
        let mut body = match generation {
            OpenCodeGeneration::Legacy1 => {
                json!({ "parts": [{ "type": "text", "text": "hello" }] })
            }
            OpenCodeGeneration::V2 => json!({ "text": "hello" }),
        };
        body[transport.message_id_field()] = json!("message:opencode:turn:opencode:1");
        let mut request = HttpRequest::new("POST", transport.prompt_route());
        request.body = serde_json::to_vec(&body).unwrap();
        let response = transport.request(request).await.unwrap();
        assert_eq!(response.status, 400);
        assert!(transport.state.lock().unwrap().message_ids.is_empty());
    }
}

async fn assert_native_ids_survive_counter_reuse(generation: OpenCodeGeneration) {
    let transport = SchemaTransport::new(generation);
    let mut observed_ids = HashSet::new();
    let mut previous_id: Option<String> = None;
    for instance in 0..8 {
        let mut provider = OpenCodeProvider::new(
            transport.clone(),
            OpenCodeProviderConfig {
                generation,
                provider_instance_id: "same-provider-config".into(),
                ..OpenCodeProviderConfig::default()
            },
        );
        provider.initialize().await.unwrap();
        let mut input = SessionStartInput::new("same-app-thread");
        if instance != 0 {
            input.resume_thread_id = Some(NATIVE_SESSION_ID.into());
        }
        let session = provider.start_session(input).await.unwrap();
        assert_eq!(session.native_thread_id, NATIVE_SESSION_ID);
        assert_eq!(
            provider.next_event().await.unwrap().unwrap().kind,
            EventKind::ThreadStarted
        );
        for local_turn in 1..=2 {
            let turn = provider
                .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
                .await
                .unwrap();
            let native_id = turn.native_turn_id.as_ref().unwrap();
            assert_eq!(turn.turn_id, format!("turn:opencode:{local_turn}"));
            assert!(native_id.starts_with("msg_"));
            assert_ne!(native_id, &turn.turn_id);
            assert!(observed_ids.insert(native_id.clone()));
            if let Some(previous) = previous_id.replace(native_id.clone()) {
                assert!(native_id > &previous);
            }
            let started = provider.next_event().await.unwrap().unwrap();
            assert_eq!(started.kind, EventKind::TurnStarted);
            assert_eq!(started.turn_id.as_ref(), Some(&turn.turn_id));
            let refs = started.provider_refs.unwrap();
            assert_eq!(refs.provider_turn_id.as_ref(), Some(native_id));
            assert_eq!(refs.provider_item_id.as_ref(), Some(native_id));
            let completed = provider.next_event().await.unwrap().unwrap();
            assert_eq!(completed.kind, EventKind::TurnCompleted);
            assert_eq!(completed.turn_id.as_ref(), Some(&turn.turn_id));
            assert!(provider.session().unwrap().active_turn_id.is_none());
        }
        provider.close().await.unwrap();
    }
    let state = transport.state.lock().unwrap();
    assert_eq!(state.message_ids, observed_ids);
    assert_eq!(observed_ids.len(), 16);
    let prompts: Vec<_> = state
        .requests
        .iter()
        .filter(|request| request.path == transport.prompt_route())
        .collect();
    assert_eq!(prompts.len(), 16);
    for request in prompts {
        let body: Value = serde_json::from_slice(&request.body).unwrap();
        let native_id = body[transport.message_id_field()].as_str().unwrap();
        assert!(observed_ids.contains(native_id));
        assert!(body.get("model").is_none());
        match generation {
            OpenCodeGeneration::Legacy1 => {
                assert_eq!(body["parts"], json!([{ "type": "text", "text": "hello" }]));
                assert!(body.get("id").is_none());
            }
            OpenCodeGeneration::V2 => {
                assert_eq!(body["text"], "hello");
                assert!(body.get("messageID").is_none());
            }
        }
    }
}

#[tokio::test]
async fn v1_native_message_ids_are_valid_and_unique_across_restart_and_resume() {
    assert_native_ids_survive_counter_reuse(OpenCodeGeneration::Legacy1).await;
}

#[tokio::test]
async fn v2_native_message_ids_are_valid_and_unique_across_restart_and_resume() {
    assert_native_ids_survive_counter_reuse(OpenCodeGeneration::V2).await;
}
