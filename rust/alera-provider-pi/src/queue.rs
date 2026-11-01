//! Stop clears Pi's native message queue before it aborts, as T3 Code does:
//! an abort leaves queued steers and follow-ups for Pi's next prompt, and Pi
//! before 0.86 starts them as soon as the abort lands.

use crate::event_core::event;
use crate::provider::PiProvider;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::EventKind;
use serde_json::{json, Map, Value};
use std::time::Duration;

const CLEAR_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_NOTICE_CHARS: usize = 2_000;

impl<T: JsonTransport> PiProvider<T> {
    /// Sends `clear_queue` and reports any messages Pi had not read. Pi before
    /// 0.84.4 rejects the command, which gates it; a rejection or a late
    /// answer leaves the queue as it was and Stop still aborts.
    pub(crate) async fn clear_native_queue(&mut self) {
        let Ok(data) = self
            .call_within("clear_queue", Value::Object(Map::new()), CLEAR_TIMEOUT)
            .await
        else {
            return;
        };
        let cleared: Vec<&str> = ["steering", "followUp"]
            .iter()
            .filter_map(|key| data.get(*key).and_then(Value::as_array))
            .flatten()
            .filter_map(Value::as_str)
            .collect();
        if cleared.is_empty() {
            return;
        }
        let count = cleared.len();
        let noun = if count == 1 { "message" } else { "messages" };
        // Image-only messages come back as empty text.
        let message: String = std::iter::once(format!(
            "Stop cleared {count} queued {noun} Pi had not read:"
        ))
        .chain(
            cleared
                .iter()
                .filter(|text| !text.is_empty())
                .map(|text| (*text).to_owned()),
        )
        .collect::<Vec<_>>()
        .join("\n\n")
        .chars()
        .take(MAX_NOTICE_CHARS)
        .collect();
        let raw = json!({ "type": "clear_queue", "data": data });
        let notice = event(
            self,
            EventKind::RuntimeWarning,
            json!({ "message": message, "cleared": count }),
            &raw,
            None,
        );
        self.queued_events.push_back(notice);
    }
}
