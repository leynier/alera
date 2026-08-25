use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use hound::WavReader;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::ai_dictation_credentials::{AiDictationCredentialStore, StoredAiDictationCredential};
use super::ai_dictation_openai::OpenAiDictationRequest;
use super::{ServerActor, ServerCommand};

static ACTIVE_REQUESTS: OnceLock<Mutex<HashMap<String, oneshot::Sender<()>>>> = OnceLock::new();

fn active_requests() -> &'static Mutex<HashMap<String, oneshot::Sender<()>>> {
    ACTIVE_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

impl ServerActor {
    pub(super) async fn start_ai_dictation(
        &mut self,
        client_id: u64,
        response_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let request_id = required_string(payload, "requestId")?;
        let engine = payload
            .get("engine")
            .and_then(Value::as_str)
            .unwrap_or("whisper");
        let timeout = request_timeout(payload);
        let audio_path = PathBuf::from(required_string(payload, "audioPath")?);
        let model = payload
            .get("modelId")
            .and_then(Value::as_str)
            .map(str::to_string);
        let language = payload
            .get("language")
            .and_then(Value::as_str)
            .map(str::to_string);
        let prompt = payload
            .get("initialPrompt")
            .and_then(Value::as_str)
            .map(str::to_string);
        let job = match engine {
            "openAiCompatible" => {
                let base_url = required_string(payload, "baseUrl")?;
                let model = model
                    .filter(|value| !value.trim().is_empty())
                    .ok_or_else(|| HostError::format("modelId is required"))?;
                let origin = super::ai_dictation_openai::provider_origin(&base_url)?;
                let token =
                    token_for_origin(self.ai_dictation_credentials().load().await?, &origin)?;
                RemoteDictationJob::OpenAi {
                    audio_path,
                    base_url,
                    model,
                    token,
                    language,
                    prompt,
                    timeout,
                }
            }
            "codexSubscription" => {
                let runtime_dir = self.runtime_dir.clone();
                let cwd = runtime_dir.to_string_lossy().to_string();
                let server = self.ensure_codex_server(Some(&cwd)).await?;
                RemoteDictationJob::Codex {
                    server,
                    audio_path,
                    runtime_dir,
                    model,
                    timeout,
                }
            }
            _ => {
                return Err(HostError::format(
                    "desktop remote AI Dictation requires a remote engine",
                ));
            }
        };
        let (cancel_tx, cancel_rx) = oneshot::channel();
        {
            let mut active = active_requests()
                .lock()
                .map_err(|_| HostError::state("dictation cancellation is unavailable"))?;
            if active.contains_key(&request_id) {
                return Err(HostError::state(
                    "another dictation request is already using this id",
                ));
            }
            active.insert(request_id.clone(), cancel_tx);
        }
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = job.run(&request_id, cancel_rx).await;
            if let Ok(mut active) = active_requests().lock() {
                active.remove(&request_id);
            }
            let _ = inbox.send(ServerCommand::AiDictationFinished {
                client_id,
                request_id: response_id,
                result,
            });
        });
        Ok(())
    }

    pub(super) async fn ai_dictation_credential_status(
        &self,
        payload: &Value,
    ) -> HostResult<Value> {
        let credential = self.ai_dictation_credentials().load().await?;
        let requested_origin = payload
            .get("baseUrl")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(super::ai_dictation_openai::provider_origin)
            .transpose()?;
        Ok(json!({
            "configured": credential.is_some(),
            "matchesBaseUrl": credential.as_ref().is_some_and(|credential| {
                requested_origin.as_ref().is_some_and(|origin| {
                    credential.origin.as_ref() == Some(origin)
                })
            }),
        }))
    }

    pub(super) async fn save_ai_dictation_credential(&self, payload: &Value) -> HostResult<Value> {
        let token = required_string(payload, "token")?;
        let origin =
            super::ai_dictation_openai::provider_origin(&required_string(payload, "baseUrl")?)?;
        self.ai_dictation_credentials()
            .save(StoredAiDictationCredential {
                token,
                origin: Some(origin),
            })
            .await?;
        Ok(json!({"configured": true, "matchesBaseUrl": true}))
    }

    pub(super) async fn clear_ai_dictation_credential(&self) -> HostResult<Value> {
        self.ai_dictation_credentials().delete().await?;
        Ok(json!({"configured": false}))
    }

    pub(super) fn handle_ai_dictation_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }

    fn ai_dictation_credentials(&self) -> AiDictationCredentialStore {
        AiDictationCredentialStore::new(&self.runtime_dir, self.account_push.service.runtime_id())
    }
}

pub(super) fn cancel(request_id: &str) -> HostResult<bool> {
    Ok(active_requests()
        .lock()
        .map_err(|_| HostError::state("dictation cancellation is unavailable"))?
        .remove(request_id)
        .is_some_and(|sender| sender.send(()).is_ok()))
}

enum RemoteDictationJob {
    OpenAi {
        audio_path: PathBuf,
        base_url: String,
        model: String,
        token: Option<String>,
        language: Option<String>,
        prompt: Option<String>,
        timeout: Duration,
    },
    Codex {
        server: super::codex_app_server::CodexAppServer,
        audio_path: PathBuf,
        runtime_dir: PathBuf,
        model: Option<String>,
        timeout: Duration,
    },
}

impl RemoteDictationJob {
    async fn run(self, request_id: &str, mut cancel: oneshot::Receiver<()>) -> HostResult<Value> {
        let started = std::time::Instant::now();
        match self {
            RemoteDictationJob::OpenAi {
                audio_path,
                base_url,
                model,
                token,
                language,
                prompt,
                timeout,
            } => {
                let operation = async {
                    let mut response =
                        super::ai_dictation_openai::transcribe(OpenAiDictationRequest {
                            audio_path: &audio_path,
                            base_url: &base_url,
                            model: &model,
                            token: token.as_deref(),
                            language: language.as_deref(),
                            prompt: prompt.as_deref(),
                            timeout,
                        })
                        .await?;
                    let duration_millis = wav_duration_millis(&audio_path)?;
                    if let Some(response) = response.as_object_mut() {
                        response.insert("requestId".to_string(), json!(request_id));
                        response.insert("durationMillis".to_string(), json!(duration_millis));
                        response.insert(
                            "elapsedMillis".to_string(),
                            json!(started.elapsed().as_millis().min(i64::MAX as u128) as i64),
                        );
                    }
                    Ok(response)
                };
                tokio::select! {
                    _ = &mut cancel => Err(HostError::state("dictation was cancelled")),
                    result = operation => result,
                }
            }
            RemoteDictationJob::Codex {
                server,
                audio_path,
                runtime_dir,
                model,
                timeout,
            } => {
                let result = super::codex_dictation::transcribe(
                    &server,
                    &audio_path,
                    &runtime_dir,
                    model.as_deref(),
                    timeout,
                    cancel,
                )
                .await?;
                Ok(json!({
                    "requestId": request_id,
                    "text": result.text,
                    "providerId": "codex-subscription",
                    "durationMillis": result.duration_millis,
                    "elapsedMillis": started.elapsed().as_millis().min(i64::MAX as u128) as i64,
                }))
            }
        }
    }
}

fn request_timeout(payload: &Value) -> Duration {
    let seconds = payload
        .get("timeoutSeconds")
        .and_then(Value::as_u64)
        .unwrap_or(60)
        .clamp(5, 300);
    Duration::from_secs(seconds)
}

fn wav_duration_millis(path: &std::path::Path) -> HostResult<i64> {
    let reader = WavReader::open(path)
        .map_err(|error| HostError::format(format!("invalid WAV audio: {error}")))?;
    let spec = reader.spec();
    if spec.sample_rate == 0 || spec.channels == 0 {
        return Err(HostError::format("invalid WAV audio format"));
    }
    let samples_per_channel = u128::from(reader.duration()) / u128::from(spec.channels);
    Ok(((samples_per_channel * 1000) / u128::from(spec.sample_rate)).min(i64::MAX as u128) as i64)
}

fn token_for_origin(
    credential: Option<StoredAiDictationCredential>,
    requested_origin: &str,
) -> HostResult<Option<String>> {
    match credential {
        Some(credential) if credential.origin.as_deref() == Some(requested_origin) => {
            Ok(Some(credential.token))
        }
        Some(_) => Err(HostError::state(
            "The saved AI Dictation token belongs to a different API origin. Replace or remove it before transcribing.",
        )),
        None => Ok(None),
    }
}

fn required_string(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;

    #[tokio::test]
    async fn remote_cancellation_signals_the_running_job() {
        let (sender, receiver) = oneshot::channel();
        active_requests()
            .lock()
            .unwrap()
            .insert("remote-1".to_string(), sender);

        assert!(cancel("remote-1").unwrap());
        receiver.await.unwrap();
    }

    #[tokio::test]
    async fn cancelling_openai_job_aborts_in_flight_http_work() {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let address = listener.local_addr().unwrap();
        let request_started = Arc::new(tokio::sync::Notify::new());
        let handler_started = Arc::clone(&request_started);
        let app = axum::Router::new().route(
            "/v1/audio/transcriptions",
            axum::routing::post(move || {
                let handler_started = Arc::clone(&handler_started);
                async move {
                    handler_started.notify_one();
                    tokio::time::sleep(Duration::from_secs(10)).await;
                    axum::Json(json!({"text": "too late"}))
                }
            }),
        );
        let server = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let dir = tempfile::tempdir().unwrap();
        let audio_path = dir.path().join("audio.wav");
        std::fs::write(&audio_path, b"audio").unwrap();
        let job = RemoteDictationJob::OpenAi {
            audio_path,
            base_url: format!("http://{address}"),
            model: "speech-model".to_string(),
            token: None,
            language: None,
            prompt: None,
            timeout: Duration::from_secs(30),
        };
        let (cancel_tx, cancel_rx) = oneshot::channel();
        let running = tokio::spawn(async move { job.run("remote-http", cancel_rx).await });
        request_started.notified().await;

        cancel_tx.send(()).unwrap();
        let error = tokio::time::timeout(Duration::from_secs(1), running)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err();

        assert!(error.to_string().contains("cancelled"));
        server.abort();
    }

    #[test]
    fn saved_tokens_are_bound_to_the_provider_origin() {
        let token = token_for_origin(
            Some(StoredAiDictationCredential {
                token: "secret".to_string(),
                origin: Some("https://api.example.test".to_string()),
            }),
            "https://api.example.test",
        )
        .unwrap();
        assert_eq!(token.as_deref(), Some("secret"));

        let error = token_for_origin(
            Some(StoredAiDictationCredential {
                token: "secret".to_string(),
                origin: Some("https://other.example.test".to_string()),
            }),
            "https://api.example.test",
        )
        .unwrap_err();
        assert!(error.to_string().contains("different API origin"));
    }
}
