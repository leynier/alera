//! Reads the run stream one frame at a time.

use super::CursorProvider;
use crate::failure::sdk_error_class;
use crate::mapping::map_run_message;
use crate::stream_state::{is_assistant_delta, item_id, run_id, status_error_message};
use alera_provider_protocol::{FailureClass, ProviderError, ProviderEvent};

impl CursorProvider {
    /// Maps the next frame of the running stream and returns its first event.
    /// `None` with the stream still open means the frame mapped to nothing.
    pub(super) async fn read_frame(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        let Some(stream) = self.stream.as_mut() else {
            return Ok(None);
        };
        let message = match stream.next().await {
            Ok(Some(message)) => message,
            Ok(None) => {
                return self
                    .recover_stream_loss(
                        "run stream ended before a terminal result".into(),
                        FailureClass::Unknown,
                    )
                    .await;
            }
            Err(error) => {
                let class = sdk_error_class(&error);
                return self.recover_stream_loss(error.to_string(), class).await;
            }
        };
        if let Some(run_id) = run_id(&message) {
            self.native_run_id = Some(run_id);
        }
        if let Some(item_id) = item_id(&message) {
            self.native_item_id = Some(item_id);
        }
        if let Some(message) = status_error_message(&message) {
            self.last_status_error_message = Some(message);
        }
        self.track_turn_end(&message);
        let session = self.active_session()?;
        let mut mapped = map_run_message(
            &message,
            &self.config.provider_instance_id,
            &session.thread_id,
            self.active_turn_id.as_deref(),
            self.native_run_id.as_deref(),
            self.native_item_id.as_deref(),
            self.streamed_assistant,
        )?;
        self.settle_terminal_events(&mut mapped)?;
        self.streamed_assistant |= mapped.iter().any(is_assistant_delta);
        let terminal = message.result.is_some() || message.done.is_some();
        self.queued_events.extend(mapped);
        if terminal {
            if let Some(stream) = self.stream.as_mut() {
                let _ = stream.close().await;
            }
            self.clear_turn_state();
        }
        Ok(self.queued_events.pop_front())
    }
}
