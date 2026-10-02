use crate::terminal_host::server::voice_realtime::VoiceRealtimeEvent;

pub(super) fn voice_realtime_event_bytes(event: &VoiceRealtimeEvent) -> usize {
    match event {
        VoiceRealtimeEvent::Audio {
            pcm,
            sample_rate,
            utterance_id,
        } => pcm
            .len()
            .saturating_add(std::mem::size_of_val(sample_rate))
            .saturating_add(std::mem::size_of_val(utterance_id)),
        VoiceRealtimeEvent::UserTranscript { text, item_id, .. } => {
            string_bytes(text) + item_id.as_deref().map(string_bytes).unwrap_or_default()
        }
        VoiceRealtimeEvent::InputCommitted { item_id } => string_bytes(item_id),
        VoiceRealtimeEvent::AudioDone { utterance_id }
        | VoiceRealtimeEvent::Interrupted { utterance_id } => std::mem::size_of_val(utterance_id),
        VoiceRealtimeEvent::Error { message } => string_bytes(message),
        VoiceRealtimeEvent::Ready => 1,
        VoiceRealtimeEvent::Closed { error } => {
            1 + error.as_deref().map(string_bytes).unwrap_or_default()
        }
    }
}

pub(super) fn bound_voice_realtime_event(event: &mut VoiceRealtimeEvent) {
    let message = "Realtime event exceeds the 16 MiB command inbox budget";
    let replace_with_error = match event {
        VoiceRealtimeEvent::UserTranscript { .. } | VoiceRealtimeEvent::InputCommitted { .. } => {
            true
        }
        VoiceRealtimeEvent::Error { message: value } => {
            *value = message.to_string();
            false
        }
        VoiceRealtimeEvent::Closed { error } => {
            *error = Some(message.to_string());
            false
        }
        VoiceRealtimeEvent::AudioDone { .. }
        | VoiceRealtimeEvent::Interrupted { .. }
        | VoiceRealtimeEvent::Ready
        | VoiceRealtimeEvent::Audio { .. } => false,
    };
    if replace_with_error {
        *event = VoiceRealtimeEvent::Error {
            message: message.to_string(),
        };
    }
}

fn string_bytes(value: &str) -> usize {
    value.len().saturating_add(1)
}
