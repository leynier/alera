use std::path::Path;
use std::time::Duration;

use base64::Engine as _;
use hound::{SampleFormat, WavReader};
use serde_json::json;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_app_server::CodexAppServer;

const AUDIO_CHUNK_SAMPLES: usize = 16_000;

pub(super) struct CodexDictationResult {
    pub(super) text: String,
    pub(super) duration_millis: i64,
}

pub(super) async fn transcribe(
    server: &CodexAppServer,
    audio_path: &Path,
    cwd: &Path,
    model: Option<&str>,
    timeout: Duration,
    mut cancel: tokio::sync::oneshot::Receiver<()>,
) -> HostResult<CodexDictationResult> {
    let deadline = tokio::time::Instant::now() + timeout;
    let chunks = tokio::select! {
        _ = &mut cancel => return Err(HostError::state("dictation was cancelled")),
        _ = tokio::time::sleep_until(deadline) => {
            return Err(HostError::state("Codex subscription dictation timed out"));
        }
        result = read_audio_chunks(audio_path) => result?,
    };
    let duration_millis =
        ((chunks.sample_count as u128 * 1000) / 16_000).min(i64::MAX as u128) as i64;
    let thread_params = json!({
        "cwd": cwd.to_string_lossy(),
        "approvalPolicy": "never",
        "sandbox": "readOnly",
        "ephemeral": true,
    });
    let thread = tokio::select! {
        _ = &mut cancel => return Err(HostError::state("dictation was cancelled")),
        _ = tokio::time::sleep_until(deadline) => {
            return Err(HostError::state("Codex subscription dictation timed out"));
        }
        result = server.request("thread/start", thread_params) => result?,
    };
    let thread_id = thread
        .pointer("/thread/id")
        .or_else(|| thread.get("threadId"))
        .and_then(serde_json::Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| HostError::state("Codex app-server returned no thread id"))?;
    let transcript = server
        .session_state
        .begin_realtime_transcript(&thread_id)
        .await;
    let operation = transcribe_on_thread(server, &thread_id, chunks.frames, transcript, model);
    let result = tokio::select! {
        _ = &mut cancel => Err(HostError::state("dictation was cancelled")),
        _ = tokio::time::sleep_until(deadline) => {
            Err(HostError::state("Codex subscription dictation timed out"))
        }
        result = operation => result,
    };
    server
        .session_state
        .remove_realtime_transcript(&thread_id)
        .await;
    if result.is_err() {
        let _ = tokio::time::timeout(
            Duration::from_secs(3),
            server.request("thread/realtime/stop", json!({"threadId": &thread_id})),
        )
        .await;
    }
    let _ = tokio::time::timeout(
        Duration::from_secs(3),
        server.request("thread/delete", json!({"threadId": &thread_id})),
    )
    .await;
    result.map(|text| CodexDictationResult {
        text,
        duration_millis,
    })
}

async fn transcribe_on_thread(
    server: &CodexAppServer,
    thread_id: &str,
    frames: Vec<String>,
    transcript: tokio::sync::oneshot::Receiver<HostResult<String>>,
    model: Option<&str>,
) -> HostResult<String> {
    let start_params = realtime_start_params(thread_id, model);
    server
        .request("thread/realtime/start", start_params)
        .await
        .map_err(|error| {
            HostError::state(format!(
                "Codex subscription dictation is unavailable. Update Codex CLI and confirm it is authenticated: {error}"
            ))
        })?;
    for frame in frames {
        server
            .request(
                "thread/realtime/appendAudio",
                json!({
                    "threadId": thread_id,
                    "audio": {
                        "data": frame,
                        "sampleRate": 16_000,
                        "numChannels": 1,
                    },
                }),
            )
            .await?;
    }
    server
        .request("thread/realtime/stop", json!({"threadId": thread_id}))
        .await?;
    transcript
        .await
        .map_err(|_| HostError::state("Codex subscription dictation ended unexpectedly"))?
}

fn realtime_start_params(thread_id: &str, model: Option<&str>) -> serde_json::Value {
    let mut params = json!({
        "threadId": thread_id,
        "outputModality": "text",
        "includeStartupContext": false,
        "clientManagedHandoffs": true,
        "prompt": null,
        "version": "v2",
    });
    if let Some(model) = normalized(model) {
        params["model"] = json!(model);
    }
    params
}

struct AudioChunks {
    frames: Vec<String>,
    sample_count: usize,
}

async fn read_audio_chunks(path: &Path) -> HostResult<AudioChunks> {
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        let mut reader = WavReader::open(path)
            .map_err(|error| HostError::format(format!("invalid WAV audio: {error}")))?;
        let spec = reader.spec();
        if spec.sample_format != SampleFormat::Int
            || spec.bits_per_sample != 16
            || spec.channels != 1
            || spec.sample_rate != 16_000
        {
            return Err(HostError::format(
                "Codex dictation requires 16-bit mono 16 kHz WAV audio",
            ));
        }
        let samples = reader
            .samples::<i16>()
            .collect::<Result<Vec<_>, _>>()
            .map_err(|error| HostError::format(format!("invalid audio samples: {error}")))?;
        if samples.is_empty() {
            return Err(HostError::format("audio recording is empty"));
        }
        let frames = samples
            .chunks(AUDIO_CHUNK_SAMPLES)
            .map(|chunk| {
                let bytes = chunk
                    .iter()
                    .flat_map(|sample| sample.to_le_bytes())
                    .collect::<Vec<_>>();
                base64::engine::general_purpose::STANDARD.encode(bytes)
            })
            .collect();
        Ok(AudioChunks {
            frames,
            sample_count: samples.len(),
        })
    })
    .await
    .map_err(|error| HostError::state(format!("audio read task failed: {error}")))?
}

fn normalized(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::{read_audio_chunks, realtime_start_params};

    #[tokio::test]
    async fn wav_audio_is_encoded_as_little_endian_pcm() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("audio.wav");
        let mut writer = hound::WavWriter::create(
            &path,
            hound::WavSpec {
                channels: 1,
                sample_rate: 16_000,
                bits_per_sample: 16,
                sample_format: hound::SampleFormat::Int,
            },
        )
        .unwrap();
        writer.write_sample::<i16>(1).unwrap();
        writer.write_sample::<i16>(-2).unwrap();
        writer.finalize().unwrap();

        let chunks = read_audio_chunks(&path).await.unwrap();

        assert_eq!(chunks.sample_count, 2);
        assert_eq!(chunks.frames, vec!["AQD+/w=="]);
    }

    #[test]
    fn realtime_model_override_is_sent_to_realtime_start() {
        let params = realtime_start_params("thread-1", Some(" realtime-model "));
        assert_eq!(params["threadId"], "thread-1");
        assert_eq!(params["model"], "realtime-model");
        assert_eq!(params["clientManagedHandoffs"], true);
        assert_eq!(params["includeStartupContext"], false);
    }
}
