use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::fs;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use hound::{SampleFormat, WavReader};
use serde::{Deserialize, Serialize};
use whisper_rs::{
    convert_integer_to_float_audio, convert_stereo_to_mono_audio, get_lang_str, FullParams,
    SamplingStrategy, WhisperContext, WhisperContextParameters,
};

static ACTIVE_REQUESTS: OnceLock<Mutex<HashMap<String, Arc<AtomicBool>>>> = OnceLock::new();

fn active_requests() -> &'static Mutex<HashMap<String, Arc<AtomicBool>>> {
    ACTIVE_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    request_id: String,
    audio_path: String,
    model_path: String,
    language: Option<String>,
    initial_prompt: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ResultPayload {
    text: String,
    detected_language: Option<String>,
    duration_millis: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ErrorPayload {
    kind: &'static str,
    message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Response {
    result: Option<ResultPayload>,
    error: Option<ErrorPayload>,
}

#[no_mangle]
pub unsafe extern "C" fn alera_mobile_whisper_transcribe(
    request_json: *const c_char,
) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(|| transcribe_pointer(request_json)))
        .unwrap_or_else(|_| failure("inference", "Whisper stopped unexpectedly."));
    response_string(response)
}

#[no_mangle]
pub unsafe extern "C" fn alera_mobile_whisper_cancel(request_id: *const c_char) {
    let Some(request_id) = string_pointer(request_id) else {
        return;
    };
    if let Ok(requests) = active_requests().lock() {
        if let Some(cancelled) = requests.get(request_id.trim()) {
            cancelled.store(true, Ordering::Relaxed);
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn alera_mobile_whisper_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

unsafe fn transcribe_pointer(request_json: *const c_char) -> Response {
    let Some(json) = string_pointer(request_json) else {
        return failure("invalidRequest", "The dictation request is empty.");
    };
    let request: Request = match serde_json::from_str(&json) {
        Ok(request) => request,
        Err(_) => return failure("invalidRequest", "The dictation request is invalid."),
    };
    transcribe(request)
}

unsafe fn string_pointer(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    CStr::from_ptr(value).to_str().ok().map(str::to_string)
}

fn transcribe(request: Request) -> Response {
    let request_id = request.request_id.trim().to_string();
    if request_id.is_empty()
        || request.audio_path.trim().is_empty()
        || request.model_path.trim().is_empty()
    {
        return failure(
            "invalidRequest",
            "The request id, audio path, and model path are required.",
        );
    }
    let cancelled = Arc::new(AtomicBool::new(false));
    if let Ok(mut requests) = active_requests().lock() {
        if requests.contains_key(&request_id) {
            return failure("inference", "Another request is already using this id.");
        }
        requests.insert(request_id.clone(), Arc::clone(&cancelled));
    } else {
        return failure("inference", "Dictation cancellation is unavailable.");
    }
    let response = transcribe_inner(&request, &cancelled);
    if let Ok(mut requests) = active_requests().lock() {
        requests.remove(&request_id);
    }
    response
}

fn transcribe_inner(request: &Request, cancelled: &Arc<AtomicBool>) -> Response {
    let (audio, duration_millis) = match read_audio(&request.audio_path) {
        Ok(audio) => audio,
        Err(error) => return error,
    };
    if cancelled.load(Ordering::Relaxed) {
        return failure("cancelled", "Dictation was cancelled.");
    }
    let context = match WhisperContext::new_with_params(
        &request.model_path,
        WhisperContextParameters::default(),
    ) {
        Ok(context) => context,
        Err(error) => {
            return failure(
                "model",
                format!("The Whisper model could not be loaded: {error:?}"),
            )
        }
    };
    let mut state = match context.create_state() {
        Ok(state) => state,
        Err(error) => {
            return failure(
                "model",
                format!("The Whisper state could not be created: {error:?}"),
            )
        }
    };
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
    params.set_n_threads(
        std::thread::available_parallelism()
            .map(|count| count.get().clamp(1, 6) as i32)
            .unwrap_or(2),
    );
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
    if let Some(prompt) = request
        .initial_prompt
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        params.set_initial_prompt(prompt.trim());
    }
    let abort_flag = Arc::clone(cancelled);
    let callback: Box<dyn FnMut() -> bool> = Box::new(move || abort_flag.load(Ordering::Relaxed));
    params.set_abort_callback_safe::<_, Box<dyn FnMut() -> bool>>(Some(callback));
    if let Err(error) = state.full(params, &audio) {
        return if cancelled.load(Ordering::Relaxed) {
            failure("cancelled", "Dictation was cancelled.")
        } else {
            failure(
                "inference",
                format!("Whisper could not transcribe the recording: {error:?}"),
            )
        };
    }
    let mut text = String::new();
    for segment in state.as_iter() {
        match segment.to_str_lossy() {
            Ok(segment) => text.push_str(&segment),
            Err(error) => {
                return failure(
                    "inference",
                    format!("Whisper returned invalid text: {error:?}"),
                )
            }
        }
    }
    let text = text.trim().to_string();
    if text.is_empty() {
        return failure("audio", "Whisper did not detect speech in the recording.");
    }
    success(ResultPayload {
        text,
        detected_language: request
            .language
            .clone()
            .or_else(|| get_lang_str(state.full_lang_id_from_state()).map(str::to_string)),
        duration_millis,
    })
}

fn read_audio(path: &str) -> Result<(Vec<f32>, i64), Response> {
    let metadata = fs::metadata(path)
        .map_err(|error| failure("io", format!("The recording could not be opened: {error}")))?;
    if !metadata.is_file() || metadata.len() == 0 {
        return Err(failure("audio", "The recording file is empty."));
    }
    let mut reader = WavReader::open(path).map_err(|error| {
        failure(
            "audio",
            format!("The recording is not valid WAV audio: {error}"),
        )
    })?;
    let spec = reader.spec();
    if spec.sample_format != SampleFormat::Int
        || spec.bits_per_sample != 16
        || !matches!(spec.channels, 1 | 2)
    {
        return Err(failure(
            "audio",
            "Dictation requires 16-bit mono or stereo PCM WAV audio.",
        ));
    }
    let samples = reader
        .samples::<i16>()
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| {
            failure(
                "audio",
                format!("The recording contains invalid samples: {error}"),
            )
        })?;
    let duration_millis = ((samples.len() as u128 * 1000)
        / (spec.sample_rate as u128 * spec.channels as u128))
        .min(i64::MAX as u128) as i64;
    let mut audio = vec![0.0; samples.len()];
    convert_integer_to_float_audio(&samples, &mut audio).map_err(|error| {
        failure(
            "audio",
            format!("The recording could not be decoded: {error:?}"),
        )
    })?;
    if spec.channels == 2 {
        let mut mono = vec![0.0; audio.len() / 2];
        convert_stereo_to_mono_audio(&audio, &mut mono).map_err(|error| {
            failure(
                "audio",
                format!("The recording could not be mixed: {error:?}"),
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

fn success(result: ResultPayload) -> Response {
    Response {
        result: Some(result),
        error: None,
    }
}

fn failure(kind: &'static str, message: impl Into<String>) -> Response {
    Response {
        result: None,
        error: Some(ErrorPayload {
            kind,
            message: message.into(),
        }),
    }
}

fn response_string(response: Response) -> *mut c_char {
    let json = serde_json::to_string(&response).unwrap_or_else(|_| {
        "{\"error\":{\"kind\":\"inference\",\"message\":\"The native response was invalid.\"}}"
            .to_string()
    });
    CString::new(json)
        .expect("JSON contains no NUL bytes")
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resampling_preserves_non_empty_audio() {
        let output = resample(&[0.0, 1.0, 0.0], 8_000, 16_000);
        assert_eq!(output.len(), 6);
        assert!(output.iter().any(|sample| *sample > 0.5));
    }
}
