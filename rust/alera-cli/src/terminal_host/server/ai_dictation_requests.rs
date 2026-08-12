use std::fs;

use base64::Engine as _;
use hound::{SampleFormat, WavReader};
use serde_json::{json, Value};
use whisper_rs::{
    convert_integer_to_float_audio, FullParams, SamplingStrategy, WhisperContext,
    WhisperContextParameters,
};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) async fn transcribe(payload: &Value) -> HostResult<Value> {
    let request_id = string(payload, "requestId")?;
    let mut temporary_audio = None;
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
        temporary_audio = Some(path.clone());
        path.to_string_lossy().to_string()
    } else {
        string(payload, "audioPath")?
    };
    let model_path = payload
        .get("modelPath")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .or_else(|| std::env::var("ALERA_WHISPER_MODEL_PATH").ok())
        .ok_or_else(|| HostError::format("Whisper model path is not configured on the runtime"))?;
    let language = payload
        .get("language")
        .and_then(Value::as_str)
        .map(str::to_string);
    let initial_prompt = payload
        .get("initialPrompt")
        .and_then(Value::as_str)
        .map(str::to_string);
    let started = std::time::Instant::now();
    let result = tokio::task::spawn_blocking(move || {
        transcribe_inner(
            &audio_path,
            &model_path,
            language.as_deref(),
            initial_prompt.as_deref(),
        )
    })
    .await
    .map_err(|error| HostError::state(format!("dictation worker failed: {error}")))??;
    if let Some(path) = temporary_audio {
        let _ = fs::remove_file(path);
    }
    Ok(json!({
        "requestId": request_id,
        "text": result.0,
        "detectedLanguage": result.1,
        "durationMillis": result.2,
        "elapsedMillis": started.elapsed().as_millis() as i64,
    }))
}

fn transcribe_inner(
    path: &str,
    model: &str,
    language: Option<&str>,
    prompt: Option<&str>,
) -> HostResult<(String, Option<String>, i64)> {
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
    let context = WhisperContext::new_with_params(model, WhisperContextParameters::default())
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
    params.set_language(language.filter(|value| !value.is_empty()));
    if let Some(prompt) = prompt.filter(|value| !value.trim().is_empty()) {
        params.set_initial_prompt(prompt.trim());
    }
    state
        .full(params, &audio)
        .map_err(|error| HostError::state(format!("Whisper inference failed: {error:?}")))?;
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

pub(super) fn cancel(_payload: &Value) -> HostResult<Value> {
    Ok(json!({}))
}

fn string(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}
