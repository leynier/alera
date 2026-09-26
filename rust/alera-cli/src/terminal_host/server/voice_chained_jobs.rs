//! Off-actor bodies for chained speech-to-text and text-to-speech jobs.

use std::time::Duration;

use alera_core::runtime::RuntimeVoiceSettings;
use serde_json::{json, Value};

use super::ai_dictation_credentials::AiDictationCredentialStore;
use super::ai_dictation_openai::OpenAiDictationRequest;
use super::voice_credentials::VoiceCredentialStore;
use super::voice_stt::transcribe_gemini;
use super::voice_tts::{synthesize, SynthesizeRequest};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

impl ServerActor {}

pub(super) fn pcm16_to_wav(pcm: &[u8], sample_rate: u32) -> Vec<u8> {
    let mut header = [0_u8; 44];
    header[0..4].copy_from_slice(b"RIFF");
    let chunk_size = 36 + pcm.len() as u32;
    header[4..8].copy_from_slice(&chunk_size.to_le_bytes());
    header[8..12].copy_from_slice(b"WAVE");
    header[12..16].copy_from_slice(b"fmt ");
    header[16..20].copy_from_slice(&16_u32.to_le_bytes());
    header[20..22].copy_from_slice(&1_u16.to_le_bytes());
    header[22..24].copy_from_slice(&1_u16.to_le_bytes());
    header[24..28].copy_from_slice(&sample_rate.to_le_bytes());
    let byte_rate = sample_rate * 2;
    header[28..32].copy_from_slice(&byte_rate.to_le_bytes());
    header[32..34].copy_from_slice(&2_u16.to_le_bytes());
    header[34..36].copy_from_slice(&16_u16.to_le_bytes());
    header[36..40].copy_from_slice(b"data");
    header[40..44].copy_from_slice(&(pcm.len() as u32).to_le_bytes());
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(&header);
    wav.extend_from_slice(pcm);
    wav
}

pub(super) async fn transcribe_chained_job(
    pcm: Vec<u8>,
    runtime_dir: std::path::PathBuf,
    runtime_id: String,
    runtime_store: alera_core::runtime::RuntimeStore,
    credentials_store: VoiceCredentialStore,
    request_id: String,
) -> HostResult<String> {
    let wav = pcm16_to_wav(&pcm, 16_000);
    let settings = runtime_store
        .voice_settings()
        .await
        .unwrap_or_else(|_| RuntimeVoiceSettings::default());
    match settings.stt_provider {
        alera_core::runtime::RuntimeVoiceSttProvider::GeminiTranscribeLive => {
            let credentials = credentials_store.load().await?;
            let token = credentials
                .gemini_token
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| {
                    HostError::state("A Gemini API key is required for Gemini transcribe.")
                })?;
            transcribe_gemini(&wav, token).await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::LocalWhisper => {
            let model_id = dictation_model_id(&runtime_store).await;
            super::ai_dictation_requests::transcribe_wav_bytes_with_model_id(
                &wav,
                &runtime_dir,
                &model_id,
                request_id,
            )
            .await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::OpenAiCompatible => {
            transcribe_openai_compatible(&wav, &runtime_dir, &runtime_id, &runtime_store).await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::CodexRealtime => Err(HostError::state(
            "Codex realtime speech-to-text is not available from a mobile voice turn. Use desktop chained STT or a realtime pipeline.",
        )),
    }
}

pub(super) async fn dictation_model_id(
    runtime_store: &alera_core::runtime::RuntimeStore,
) -> String {
    runtime_store
        .configuration_settings()
        .await
        .ok()
        .and_then(|settings| {
            settings
                .get("aiDictation")
                .and_then(|section| section.get("localModelId"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
        })
        .unwrap_or_else(|| "whisper-base".to_string())
}

pub(super) async fn transcribe_openai_compatible(
    wav: &[u8],
    runtime_dir: &std::path::Path,
    runtime_id: &str,
    runtime_store: &alera_core::runtime::RuntimeStore,
) -> HostResult<String> {
    let settings = runtime_store
        .configuration_settings()
        .await
        .unwrap_or(Value::Null);
    let section = settings.get("aiDictation");
    let base_url = section
        .and_then(|value| value.get("remoteBaseUrl"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("https://api.openai.com/v1");
    let model = section
        .and_then(|value| value.get("remoteModel"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("gpt-4o-mini-transcribe");
    let origin = super::ai_dictation_openai::provider_origin(base_url)?;
    let token = token_for_dictation_origin(runtime_dir, runtime_id, &origin).await?;
    let path = std::env::temp_dir().join(format!("alera-voice-stt-{}.wav", uuid::Uuid::new_v4()));
    struct TempWav(std::path::PathBuf);
    impl Drop for TempWav {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }
    let wav = wav.to_vec();
    let write_path = path.clone();
    let _temp = tokio::task::spawn_blocking(move || {
        use std::io::Write as _;
        let temp = TempWav(write_path.clone());
        let mut file = alera_core::runtime::create_private_runtime_file(&write_path)?;
        file.write_all(&wav)?;
        file.sync_all()?;
        Ok::<TempWav, std::io::Error>(temp)
    })
    .await
    .map_err(|error| HostError::state(format!("audio could not be stored: {error}")))?
    .map_err(|error| HostError::state(format!("audio could not be stored: {error}")))?;
    let result = super::ai_dictation_openai::transcribe(OpenAiDictationRequest {
        audio_path: &path,
        base_url,
        model,
        token: token.as_deref(),
        language: None,
        prompt: None,
        timeout: Duration::from_secs(60),
    })
    .await;
    let decoded = result?;
    Ok(decoded
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string())
}

pub(super) async fn token_for_dictation_origin(
    runtime_dir: &std::path::Path,
    runtime_id: &str,
    origin: &str,
) -> HostResult<Option<String>> {
    let store = AiDictationCredentialStore::new(runtime_dir, runtime_id);
    match store.load().await? {
        Some(credential) if credential.origin.as_deref() == Some(origin) => {
            Ok(Some(credential.token))
        }
        Some(_) => Err(HostError::state(
            "The saved AI Dictation token belongs to a different API origin. Replace or remove it before transcribing.",
        )),
        None => Err(HostError::state(
            "Save an OpenAI-compatible AI Dictation token before using that speech-to-text engine.",
        )),
    }
}

pub(super) async fn synthesize_job(
    text: String,
    provider: Option<String>,
    voice: Option<String>,
    runtime_store: alera_core::runtime::RuntimeStore,
    credentials_store: VoiceCredentialStore,
) -> HostResult<Value> {
    let settings = runtime_store
        .voice_settings()
        .await
        .unwrap_or_else(|_| RuntimeVoiceSettings::default());
    let credentials = credentials_store.load().await?;
    let provider = provider.unwrap_or_else(|| match settings.tts_provider {
        alera_core::runtime::RuntimeVoiceTtsProvider::OpenAiTts => "openAiTts".to_string(),
        alera_core::runtime::RuntimeVoiceTtsProvider::GeminiFlashTts => {
            "geminiFlashTts".to_string()
        }
    });
    let audio = synthesize(SynthesizeRequest {
        text: &text,
        gemini_token: credentials.gemini_token.as_deref(),
        openai_token: credentials.openai_token.as_deref(),
        tts_provider: &provider,
        tts_voice: voice.as_deref().or(settings.tts_voice.as_deref()),
    })
    .await?;
    use base64::Engine as _;
    Ok(json!({
        "text": text,
        "audioBase64": base64::engine::general_purpose::STANDARD.encode(audio),
        "mimeType": "audio/wav",
    }))
}
