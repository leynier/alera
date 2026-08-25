use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use base64::Engine as _;
use hound::{SampleFormat, WavReader};
use serde_json::{json, Value};
use whisper_rs::{
    convert_integer_to_float_audio, FullParams, SamplingStrategy, WhisperContext,
    WhisperContextParameters,
};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_dictation_credentials::AiDictationCredentialStore;
use super::ai_dictation_openai::OpenAiDictationRequest;
use super::ServerActor;

static ACTIVE_REQUESTS: OnceLock<Mutex<HashMap<String, Arc<AtomicBool>>>> = OnceLock::new();

fn active_requests() -> &'static Mutex<HashMap<String, Arc<AtomicBool>>> {
    ACTIVE_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

struct DictationRequestGuard {
    request_id: String,
    temporary_audio: Option<PathBuf>,
}

impl Drop for DictationRequestGuard {
    fn drop(&mut self) {
        if let Ok(mut requests) = active_requests().lock() {
            requests.remove(&self.request_id);
        }
        if let Some(path) = self.temporary_audio.take() {
            let _ = fs::remove_file(path);
        }
    }
}

impl ServerActor {
    pub(super) async fn transcribe_ai_dictation(&mut self, payload: &Value) -> HostResult<Value> {
        match payload
            .get("engine")
            .and_then(Value::as_str)
            .unwrap_or("whisper")
        {
            "whisper" => transcribe_whisper(payload, true, &self.runtime_dir).await,
            "openAiCompatible" => self.transcribe_openai_compatible(payload).await,
            "codexSubscription" => self.transcribe_codex_subscription(payload).await,
            _ => Err(HostError::format("unknown AI Dictation engine")),
        }
    }

    pub(super) async fn ai_dictation_credential_status(&self) -> HostResult<Value> {
        Ok(json!({
            "configured": self.ai_dictation_credentials().load().await?.is_some(),
        }))
    }

    pub(super) async fn save_ai_dictation_credential(&self, payload: &Value) -> HostResult<Value> {
        let token = string(payload, "token")?;
        self.ai_dictation_credentials().save(token).await?;
        Ok(json!({"configured": true}))
    }

    pub(super) async fn clear_ai_dictation_credential(&self) -> HostResult<Value> {
        self.ai_dictation_credentials().delete().await?;
        Ok(json!({"configured": false}))
    }

    async fn transcribe_openai_compatible(&self, payload: &Value) -> HostResult<Value> {
        let request_id = string(payload, "requestId")?;
        let audio_path = PathBuf::from(string(payload, "audioPath")?);
        let base_url = string(payload, "baseUrl")?;
        let model = string(payload, "modelId")?;
        let token = self.ai_dictation_credentials().load().await?;
        let started = std::time::Instant::now();
        let mut response = super::ai_dictation_openai::transcribe(OpenAiDictationRequest {
            audio_path: &audio_path,
            base_url: &base_url,
            model: &model,
            token: token.as_deref(),
            language: payload.get("language").and_then(Value::as_str),
            prompt: payload.get("initialPrompt").and_then(Value::as_str),
            timeout: request_timeout(payload),
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
    }

    async fn transcribe_codex_subscription(&mut self, payload: &Value) -> HostResult<Value> {
        let request_id = string(payload, "requestId")?;
        let audio_path = PathBuf::from(string(payload, "audioPath")?);
        let runtime_dir = self.runtime_dir.clone();
        let cwd = runtime_dir.to_string_lossy().to_string();
        let server = self.ensure_codex_server(Some(&cwd)).await?;
        let started = std::time::Instant::now();
        let result = super::codex_dictation::transcribe(
            &server,
            &audio_path,
            &runtime_dir,
            payload.get("modelId").and_then(Value::as_str),
            request_timeout(payload),
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

    fn ai_dictation_credentials(&self) -> AiDictationCredentialStore {
        AiDictationCredentialStore::new(&self.runtime_dir, self.account_push.service.runtime_id())
    }
}

pub(super) async fn transcribe_mobile(
    payload: &Value,
    runtime_dir: &std::path::Path,
) -> HostResult<Value> {
    if payload
        .get("engine")
        .and_then(Value::as_str)
        .unwrap_or("whisper")
        != "whisper"
    {
        return Err(HostError::format(
            "the paired runtime does not provide this system speech engine",
        ));
    }
    transcribe_whisper(payload, false, runtime_dir).await
}

async fn transcribe_whisper(
    payload: &Value,
    allow_explicit_model_path: bool,
    runtime_dir: &std::path::Path,
) -> HostResult<Value> {
    let request_id = string(payload, "requestId")?;
    let model_path = resolve_model_path(payload, allow_explicit_model_path, runtime_dir)?;
    let cancelled = Arc::new(AtomicBool::new(false));
    {
        let mut requests = active_requests()
            .lock()
            .map_err(|_| HostError::state("dictation cancellation is unavailable"))?;
        if requests.contains_key(&request_id) {
            return Err(HostError::state(
                "another dictation request is already using this id",
            ));
        }
        requests.insert(request_id.clone(), Arc::clone(&cancelled));
    }
    let mut request_guard = DictationRequestGuard {
        request_id: request_id.clone(),
        temporary_audio: None,
    };
    let audio_path = if let Some(encoded) = payload.get("audioBase64").and_then(Value::as_str) {
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(encoded)
            .map_err(|_| HostError::format("audioBase64 is invalid"))?;
        if bytes.len() > 25 * 1024 * 1024 {
            return Err(HostError::format("audio recording is too large"));
        }
        let path =
            std::env::temp_dir().join(format!("alera-dictation-{}.wav", uuid::Uuid::new_v4()));
        fs::write(&path, bytes)
            .map_err(|error| HostError::state(format!("audio could not be stored: {error}")))?;
        request_guard.temporary_audio = Some(path.clone());
        path.to_string_lossy().to_string()
    } else {
        string(payload, "audioPath")?
    };
    let language = normalize_whisper_language(payload.get("language").and_then(Value::as_str));
    let initial_prompt = payload
        .get("initialPrompt")
        .and_then(Value::as_str)
        .map(str::to_string);
    let started = std::time::Instant::now();
    let worker_cancelled = Arc::clone(&cancelled);
    let result = tokio::task::spawn_blocking(move || {
        transcribe_inner(
            &audio_path,
            &model_path,
            language.as_deref(),
            initial_prompt.as_deref(),
            &worker_cancelled,
        )
    })
    .await
    .map_err(|error| HostError::state(format!("dictation worker failed: {error}")))?;
    let result = result?;
    Ok(json!({
        "requestId": request_id,
        "text": result.0,
        "detectedLanguage": result.1,
        "durationMillis": result.2,
        "elapsedMillis": started.elapsed().as_millis() as i64,
    }))
}

pub(super) fn capabilities(runtime_dir: &std::path::Path) -> HostResult<Value> {
    let models = [
        ("whisper-tiny", "Whisper Tiny"),
        ("whisper-base", "Whisper Base"),
        ("whisper-small", "Whisper Small"),
        ("whisper-large-v3-turbo-q5-0", "Whisper Large v3 Turbo"),
    ]
    .into_iter()
    .map(|(id, label)| {
        json!({
            "id": id,
            "label": label,
            "installed": resolve_model_path(&json!({"modelId": id}), false, runtime_dir).is_ok(),
        })
    })
    .collect::<Vec<_>>();
    let platform = if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        "unknown"
    };
    Ok(json!({
        "platform": platform,
        "backends": [{
            "location": "pairedDevice",
            "backend": "whisper",
            "streaming": false,
            "batchFile": true,
            "requiresNetwork": false,
            "guaranteedOnDevice": true,
            "models": models,
        }],
    }))
}

fn resolve_model_path(
    payload: &Value,
    allow_explicit_model_path: bool,
    runtime_dir: &std::path::Path,
) -> HostResult<String> {
    if allow_explicit_model_path {
        if let Some(path) = payload
            .get("modelPath")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
        {
            return Ok(path.to_string());
        }
    }
    let model_id = payload
        .get("modelId")
        .and_then(Value::as_str)
        .unwrap_or("whisper-base");
    let file_name = match model_id {
        "whisper-tiny" => "ggml-tiny.bin",
        "whisper-base" | "whisper-cpp-base" => "ggml-base.bin",
        "whisper-small" => "ggml-small.bin",
        "whisper-large-v3-turbo-q5-0" => "ggml-large-v3-turbo-q5_0.bin",
        _ => return Err(HostError::format("unknown Whisper model id")),
    };
    let mut roots = Vec::new();
    if let Some(root) = std::env::var_os("ALERA_WHISPER_MODEL_ROOT") {
        roots.push(PathBuf::from(root));
    }
    if let Some(support_directory) = runtime_dir.parent() {
        roots.push(support_directory.join("models").join("ai-dictation"));
    }
    for root in roots {
        let path = root.join(model_id).join("1").join(file_name);
        if path.is_file() {
            return Ok(path.to_string_lossy().to_string());
        }
    }
    if matches!(model_id, "whisper-base" | "whisper-cpp-base") {
        if let Ok(path) = std::env::var("ALERA_WHISPER_MODEL_PATH") {
            if PathBuf::from(&path).is_file() {
                return Ok(path);
            }
        }
    }
    Err(HostError::state(format!(
        "Whisper model {model_id} is not installed on the paired device"
    )))
}

fn transcribe_inner(
    path: &str,
    model: &str,
    language: Option<&str>,
    prompt: Option<&str>,
    cancelled: &Arc<AtomicBool>,
) -> HostResult<(String, Option<String>, i64)> {
    if cancelled.load(Ordering::Relaxed) {
        return Err(HostError::state("dictation was cancelled"));
    }
    let metadata = fs::metadata(path)
        .map_err(|error| HostError::state(format!("audio could not be opened: {error}")))?;
    if !metadata.is_file() || metadata.len() == 0 {
        return Err(HostError::format("audio file is empty"));
    }
    let mut reader = WavReader::open(path)
        .map_err(|error| HostError::format(format!("invalid WAV audio: {error}")))?;
    let spec = reader.spec();
    if spec.sample_format != SampleFormat::Int
        || spec.bits_per_sample != 16
        || spec.channels != 1
        || spec.sample_rate != 16_000
    {
        return Err(HostError::format(
            "runtime dictation requires 16-bit mono 16 kHz WAV audio",
        ));
    }
    let samples = reader
        .samples::<i16>()
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| HostError::format(format!("invalid audio samples: {error}")))?;
    let duration = ((samples.len() as u128 * 1000) / 16_000).min(i64::MAX as u128) as i64;
    let mut audio = vec![0.0; samples.len()];
    convert_integer_to_float_audio(&samples, &mut audio)
        .map_err(|error| HostError::state(format!("audio decode failed: {error:?}")))?;
    let context = WhisperContext::new_with_params(model, desktop_whisper_context_parameters())
        .map_err(|error| {
            HostError::state(format!("Whisper model could not be loaded: {error:?}"))
        })?;
    let mut state = context.create_state().map_err(|error| {
        HostError::state(format!("Whisper state could not be created: {error:?}"))
    })?;
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
    params.set_n_threads(
        std::thread::available_parallelism()
            .map(|value| value.get().clamp(1, 8) as i32)
            .unwrap_or(2),
    );
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_language(language);
    if let Some(prompt) = prompt.filter(|value| !value.trim().is_empty()) {
        params.set_initial_prompt(prompt.trim());
    }
    let abort_flag = Arc::clone(cancelled);
    let callback: Box<dyn FnMut() -> bool> = Box::new(move || abort_flag.load(Ordering::Relaxed));
    params.set_abort_callback_safe::<_, Box<dyn FnMut() -> bool>>(Some(callback));
    state.full(params, &audio).map_err(|error| {
        if cancelled.load(Ordering::Relaxed) {
            HostError::state("dictation was cancelled")
        } else {
            HostError::state(format!("Whisper inference failed: {error:?}"))
        }
    })?;
    let mut text = String::new();
    for segment in state.as_iter() {
        text.push_str(&segment.to_str_lossy().map_err(|error| {
            HostError::state(format!("Whisper returned invalid text: {error:?}"))
        })?);
    }
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err(HostError::format("Whisper did not detect speech"));
    }
    Ok((text, language.map(str::to_string), duration))
}

fn desktop_whisper_context_parameters() -> WhisperContextParameters<'static> {
    WhisperContextParameters {
        use_gpu: cfg!(target_os = "macos")
            || cfg!(all(
                target_arch = "x86_64",
                any(target_os = "linux", target_os = "windows")
            )),
        ..Default::default()
    }
}

fn normalize_whisper_language(language: Option<&str>) -> Option<String> {
    language
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| {
            value
                .split(['-', '_'])
                .next()
                .unwrap_or(value)
                .to_ascii_lowercase()
        })
}

pub(super) fn cancel(payload: &Value) -> HostResult<Value> {
    let request_id = string(payload, "requestId")?;
    if let Ok(requests) = active_requests().lock() {
        if let Some(cancelled) = requests.get(&request_id) {
            cancelled.store(true, Ordering::Relaxed);
        }
    }
    Ok(json!({}))
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

fn string(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_model_ids_are_rejected() {
        let error = resolve_model_path(
            &json!({"modelId": "../outside"}),
            false,
            std::path::Path::new("/tmp/terminal-host"),
        )
        .unwrap_err();
        assert!(error.to_string().contains("unknown Whisper model id"));
    }

    #[test]
    fn mobile_requests_cannot_select_an_arbitrary_model_path() {
        let error = resolve_model_path(
            &json!({
                "modelId": "../outside",
                "modelPath": "C:\\private\\other-model.bin"
            }),
            false,
            std::path::Path::new("/tmp/terminal-host"),
        )
        .unwrap_err();
        assert!(error.to_string().contains("unknown Whisper model id"));
    }

    #[test]
    fn cancellation_is_idempotent() {
        cancel(&json!({"requestId": "missing"})).unwrap();
    }

    #[test]
    fn whisper_languages_use_the_primary_subtag() {
        assert_eq!(
            normalize_whisper_language(Some("en-US")).as_deref(),
            Some("en")
        );
        assert_eq!(
            normalize_whisper_language(Some("pt_BR")).as_deref(),
            Some("pt")
        );
    }

    #[test]
    fn hardware_acceleration_matches_the_supported_desktop_targets() {
        let expected = cfg!(target_os = "macos")
            || cfg!(all(
                target_arch = "x86_64",
                any(target_os = "linux", target_os = "windows")
            ));
        assert_eq!(desktop_whisper_context_parameters().use_gpu, expected);
    }

    #[test]
    fn capabilities_never_include_provider_secrets() {
        let payload = capabilities(std::path::Path::new("/tmp/terminal-host")).unwrap();
        let serialized = payload.to_string();
        assert!(!serialized.contains("apiKey"));
        assert!(!serialized.contains("Authorization"));
        assert!(serialized.contains("whisper"));
    }
}
