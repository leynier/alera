use crate::*;
use async_trait::async_trait;

/// A connected runtime. Events are consumed by one owner; callbacks may be driven with `next_event_with`.
#[async_trait]
pub trait Provider: Send {
    fn kind(&self) -> ProviderKind;
    fn capabilities(&self) -> ProviderCapabilities;
    fn reasoning_effort_capabilities(&self) -> ReasoningEffortCapabilities {
        ReasoningEffortCapabilities::default()
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        NativeHistoryCapabilities::default()
    }
    fn session(&self) -> Option<&ProviderSession>;
    async fn initialize(&mut self) -> Result<(), ProviderError>;
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError>;
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError>;
    async fn steer_turn(
        &mut self,
        _input: TurnInput,
        _expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        Err(ProviderError::Unsupported("native turn steering".into()))
    }
    /// Starts a forked session on a fresh provider connection.
    async fn fork_session(
        &mut self,
        _input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        Err(ProviderError::Unsupported("native session fork".into()))
    }
    async fn rollback_session(
        &mut self,
        _input: NativeRollbackInput,
    ) -> Result<NativeRollbackResult, ProviderError> {
        Err(ProviderError::Unsupported(
            "native conversation rollback".into(),
        ))
    }
    async fn rewind_files(
        &mut self,
        _input: NativeRewindFilesInput,
    ) -> Result<NativeRewindFilesResult, ProviderError> {
        Err(ProviderError::Unsupported(
            "native filesystem rewind".into(),
        ))
    }
    /// Marks (`awaited`) or unmarks background tasks the agent will resume
    /// from, by the task ids the agent saw, and returns the ids it matched.
    /// Ids not running in this session are not returned and change nothing.
    async fn await_background_tasks(
        &mut self,
        _task_ids: &[String],
        _awaited: bool,
    ) -> Result<Vec<String>, ProviderError> {
        Err(ProviderError::Unsupported(
            "awaiting background tasks".into(),
        ))
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError>;
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError>;
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError>;
    async fn close(&mut self) -> Result<(), ProviderError>;

    async fn next_event_with(
        &mut self,
        handler: &mut dyn RequestHandler,
    ) -> Result<Option<ProviderEvent>, ProviderError> {
        let event = self.next_event().await?;
        if let Some(request) = event
            .as_ref()
            .filter(|event| {
                matches!(
                    &event.kind,
                    EventKind::RequestOpened | EventKind::UserInputRequested
                )
            })
            .and_then(|event| event.runtime_request.as_ref())
        {
            let response = handler.handle(request).await?;
            if response.request_id() != &request.request_id {
                return Err(ProviderError::Validation(
                    "callback response request id does not match".into(),
                ));
            }
            self.respond(response).await?;
        }
        Ok(event)
    }
}

#[async_trait]
pub trait RequestHandler: Send {
    async fn handle(&mut self, request: &RuntimeRequest) -> Result<RuntimeResponse, ProviderError>;
}
