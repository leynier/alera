use std::collections::HashMap;
use std::fs;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use hound::{SampleFormat, WavReader};
use whisper_rs::{
    convert_integer_to_float_audio, convert_stereo_to_mono_audio, get_lang_str, FullParams,
    SamplingStrategy, WhisperContext, WhisperContextParameters,
};

static ACTIVE_REQUESTS: OnceLock<Mutex<HashMap<String, Arc<AtomicBool>>>> = OnceLock::new();

fn active_requests() -> &'static Mutex<HashMap<String, Arc<AtomicBool>>> {
    ACTIVE_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Debug, Clone)]
pub struct AiDictationRequest {
    pub request_id: String,
    pub audio_path: String,
    pub model_path: String,
    pub language: Option<String>,
    pub initial_prompt: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AiDictationResult {
    pub text: String,
    pub detected_language: Option<String>,
    pub duration_millis: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiDictationErrorKind {
    InvalidRequest,
    Audio,
    Model,
    Cancelled,
    Inference,
    Io,
}

#[derive(Debug, Clone)]
pub struct AiDictationError {
    pub kind: AiDictationErrorKind,
    pub message: String,
}

pub fn cancel_whisper(request_id: String) {
    if let Ok(requests) = active_requests().lock() {
        if let Some(cancelled) = requests.get(request_id.trim()) {
            cancelled.store(true, Ordering::Relaxed);
        }
    }
}

pub fn transcribe_whisper(
    request: AiDictationRequest,
) -> Result<AiDictationResult, AiDictationError> {
    let request_id = request.request_id.trim().to_string();
    if request_id.is_empty() {
        return Err(error(
            AiDictationErrorKind::InvalidRequest,
            "Dictation request id is empty.",
        ));
    }
    if request.audio_path.trim().is_empty() || request.model_path.trim().is_empty() {
        return Err(error(
            AiDictationErrorKind::InvalidRequest,
            "Dictation audio and model paths are required.",
        ));
    }

    let cancelled = Arc::new(AtomicBool::new(false));
    {
        let mut requests = active_requests().lock().map_err(|_| {
            error(
                AiDictationErrorKind::Inference,
                "The dictation cancellation registry is unavailable.",
            )
        })?;
        if requests
            .insert(request_id.clone(), Arc::clone(&cancelled))
            .is_some()
        {
            return Err(error(
                AiDictationErrorKind::Inference,
                "Another dictation request is already using this id.",
            ));
        }
    }

    let result = transcribe_inner(&request, &cancelled);
    if let Ok(mut requests) = active_requests().lock() {
        requests.remove(&request_id);
    }
    result
}

fn transcribe_inner(
    request: &AiDictationRequest,
    cancelled: &Arc<AtomicBool>,
) -> Result<AiDictationResult, AiDictationError> {
    if cancelled.load(Ordering::Relaxed) {
        return Err(cancelled_error());
    }

    let (audio, duration_millis) = read_audio(&request.audio_path)?;
    if audio.is_empty() {
        return Err(error(
            AiDictationErrorKind::Audio,
            "The recording did not contain audio samples.",
        ));
    }
    if cancelled.load(Ordering::Relaxed) {
        return Err(cancelled_error());
    }

    let context =
        WhisperContext::new_with_params(&request.model_path, WhisperContextParameters::default())
            .map_err(|native_error| {
            error(
                AiDictationErrorKind::Model,
                format!("The Whisper model could not be loaded: {native_error:?}"),
            )
        })?;
    let mut state = context.create_state().map_err(|native_error| {
        error(
            AiDictationErrorKind::Model,
            format!("The Whisper state could not be created: {native_error:?}"),
        )
    })?;

    let thread_count = std::thread::available_parallelism()
        .map(|count| count.get().clamp(1, 8) as i32)
        .unwrap_or(2);
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
    params.set_n_threads(thread_count);
    params.set_translate(false);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_language(
        request
            .language
            .as_deref()
            .filter(|value| !value.is_empty()),
    );
    if let Some(initial_prompt) = request.initial_prompt.as_deref() {
        if !initial_prompt.trim().is_empty() {
            params.set_initial_prompt(initial_prompt.trim());
        }
    }
    let abort_flag = Arc::clone(cancelled);
    let abort_callback: Box<dyn FnMut() -> bool> =
        Box::new(move || abort_flag.load(Ordering::Relaxed));
    params.set_abort_callback_safe::<_, Box<dyn FnMut() -> bool>>(Some(abort_callback));

    state.full(params, &audio).map_err(|native_error| {
        if cancelled.load(Ordering::Relaxed) {
            cancelled_error()
        } else {
            error(
                AiDictationErrorKind::Inference,
                format!("Whisper could not transcribe the recording: {native_error:?}"),
            )
        }
    })?;
    if cancelled.load(Ordering::Relaxed) {
        return Err(cancelled_error());
    }

    let mut text = String::new();
    for segment in state.as_iter() {
        text.push_str(&segment.to_str_lossy().map_err(|native_error| {
            error(
                AiDictationErrorKind::Inference,
                format!("Whisper returned an invalid segment: {native_error:?}"),
            )
        })?);
    }
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err(error(
            AiDictationErrorKind::Audio,
            "Whisper did not detect speech in the recording.",
        ));
    }

    let detected_language = request
        .language
        .clone()
        .or_else(|| get_lang_str(state.full_lang_id_from_state()).map(str::to_string));
    Ok(AiDictationResult {
        text,
        detected_language,
        duration_millis,
    })
}

fn read_audio(path: &str) -> Result<(Vec<f32>, i64), AiDictationError> {
    let metadata = fs::metadata(path).map_err(|native_error| {
        error(
            AiDictationErrorKind::Io,
            format!("The recording could not be opened: {native_error}"),
        )
    })?;
    if !metadata.is_file() || metadata.len() == 0 {
        return Err(error(
            AiDictationErrorKind::Audio,
            "The recording file is empty.",
        ));
    }
    let mut reader = WavReader::open(path).map_err(|native_error| {
        error(
            AiDictationErrorKind::Audio,
            format!("The recording is not a valid WAV file: {native_error}"),
        )
    })?;
    let spec = reader.spec();
    if spec.sample_format != SampleFormat::Int || spec.bits_per_sample != 16 {
        return Err(error(
            AiDictationErrorKind::Audio,
            "Dictation recordings must use 16-bit PCM WAV audio.",
        ));
    }
    if !matches!(spec.channels, 1 | 2) || spec.sample_rate == 0 {
        return Err(error(
            AiDictationErrorKind::Audio,
            "Dictation recordings must contain one or two audio channels.",
        ));
    }
    let samples = reader
        .samples::<i16>()
        .collect::<Result<Vec<_>, _>>()
        .map_err(|native_error| {
            error(
                AiDictationErrorKind::Audio,
                format!("The recording contains invalid samples: {native_error}"),
            )
        })?;
    let duration_millis = ((samples.len() as u128 * 1000)
        / (spec.sample_rate as u128 * spec.channels as u128))
        .min(i64::MAX as u128) as i64;
    let mut audio = vec![0.0; samples.len()];
    convert_integer_to_float_audio(&samples, &mut audio).map_err(|native_error| {
        error(
            AiDictationErrorKind::Audio,
            format!("The recording could not be decoded: {native_error:?}"),
        )
    })?;
    if spec.channels == 2 {
        let mut mono = vec![0.0; audio.len() / 2];
        convert_stereo_to_mono_audio(&audio, &mut mono).map_err(|native_error| {
            error(
                AiDictationErrorKind::Audio,
                format!("The stereo recording could not be mixed: {native_error:?}"),
            )
        })?;
        audio = mono;
    }
    if spec.sample_rate != 16_000 {
        audio = resample(&audio, spec.sample_rate, 16_000);
    }
    Ok((audio, duration_millis))
}

fn resample(samples: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if samples.is_empty() || source_rate == target_rate {
        return samples.to_vec();
    }
    let output_len =
        ((samples.len() as u64 * target_rate as u64) / source_rate as u64).max(1) as usize;
    let ratio = source_rate as f64 / target_rate as f64;
    (0..output_len)
        .map(|index| {
            let source = index as f64 * ratio;
            let left = source.floor() as usize;
            let right = (left + 1).min(samples.len() - 1);
            let fraction = source - left as f64;
            samples[left] * (1.0 - fraction as f32) + samples[right] * fraction as f32
        })
        .collect()
}

fn error(kind: AiDictationErrorKind, message: impl Into<String>) -> AiDictationError {
    AiDictationError {
        kind,
        message: message.into(),
    }
}

fn cancelled_error() -> AiDictationError {
    error(AiDictationErrorKind::Cancelled, "Dictation was cancelled.")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resampling_keeps_non_empty_audio() {
        let output = resample(&[0.0, 1.0, 0.0], 8_000, 16_000);
        assert_eq!(output.len(), 6);
        assert!(output.iter().any(|sample| *sample > 0.5));
    }

    #[test]
    fn cancellation_is_idempotent_for_unknown_request() {
        cancel_whisper("missing".to_string());
    }
}
