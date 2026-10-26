use super::*;
use alera_provider_protocol::{
    NativeForkBoundary, NativeForkInput, NativeForkResult, NativeRewindFilesInput,
    NativeRewindFilesResult,
};

impl ClaudeProvider {
    pub(super) async fn fork_native(
        &mut self,
        input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        input.validate()?;
        if self.closed {
            return Err(ProviderError::Closed);
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Claude forks require a fresh provider connection".into(),
            ));
        }
        let boundary = match &input.boundary {
            Some(NativeForkBoundary::Turn(_)) => {
                return Err(ProviderError::Unsupported(
                    "Claude forks require a native transcript message UUID".into(),
                ))
            }
            Some(NativeForkBoundary::Message(id)) => Some(id.clone()),
            None => None,
        };
        let previous_options = self.config.options.clone();
        self.config.options = native_fork_options(&previous_options, boundary);
        self.fork_source_native_thread_id = Some(input.source_native_thread_id.clone());
        let mut start = input.session;
        start.resume_thread_id = Some(input.source_native_thread_id.clone());
        let result = async {
            self.initialize().await?;
            self.start_session(start).await
        }
        .await;
        self.config.options = previous_options;
        if result.is_err() {
            self.fork_source_native_thread_id = None;
        }
        let session = result?;
        Ok(NativeForkResult {
            native_thread_id: None,
            session,
            source_native_thread_id: input.source_native_thread_id,
            boundary: input.boundary,
        })
    }

    pub(super) async fn rewind_native_files(
        &mut self,
        input: NativeRewindFilesInput,
    ) -> Result<NativeRewindFilesResult, ProviderError> {
        input.validate()?;
        if self.closed {
            return Err(ProviderError::Closed);
        }
        if !self.file_checkpointing {
            return Err(ProviderError::Unsupported(
                "Claude filesystem rewind requires file checkpointing at session launch".into(),
            ));
        }
        let session = self
            .session
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("start a Claude session first".into()))?;
        if session.thread_id != input.thread_id {
            return Err(ProviderError::Validation(
                "rewind threadId does not match Claude session".into(),
            ));
        }
        if session.status != SessionStatus::Ready
            || session.active_turn_id.is_some()
            || session.native_thread_id.starts_with("pending:")
        {
            return Err(ProviderError::InvalidState(
                "filesystem rewind requires a settled native Claude session".into(),
            ));
        }
        let native_thread_id = session.native_thread_id.clone();
        let response = self
            .client
            .as_ref()
            .ok_or_else(|| {
                ProviderError::InvalidState("Claude session client is unavailable".into())
            })?
            .rewind_files(&input.native_user_message_id)
            .await
            .map_err(sdk_error)?;
        Ok(NativeRewindFilesResult {
            thread_id: input.thread_id,
            native_thread_id,
            native_user_message_id: input.native_user_message_id,
            can_rewind: response.can_rewind,
            error: response.error,
            files_changed: response.files_changed,
            insertions: response.insertions,
            deletions: response.deletions,
            skipped_links: response.skipped_links,
            native_response: response.raw,
        })
    }
}

fn native_fork_options(base: &ClaudeAgentOptions, boundary: Option<String>) -> ClaudeAgentOptions {
    let mut options = base.clone();
    options.fork_session = true;
    options.resume_session_at = boundary;
    options.resume_drops_turn = None;
    options.continue_conversation = false;
    options.session_id = None;
    options
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fork_options_use_native_resume_uuid_and_clear_conflicting_launch_state() {
        let base = ClaudeAgentOptions {
            session_id: Some("old".into()),
            continue_conversation: true,
            resume_drops_turn: Some("discarded".into()),
            ..Default::default()
        };
        let options = native_fork_options(&base, Some("last-included-transcript-uuid".into()));
        assert!(options.fork_session);
        assert_eq!(
            options.resume_session_at.as_deref(),
            Some("last-included-transcript-uuid")
        );
        assert!(options.resume_drops_turn.is_none());
        assert!(options.session_id.is_none());
        assert!(!options.continue_conversation);
        assert_eq!(base.session_id.as_deref(), Some("old"));
    }
}
