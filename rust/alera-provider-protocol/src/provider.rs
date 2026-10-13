use crate::*;
use async_trait::async_trait;

/// A connected runtime. Events are consumed by one owner; callbacks may be driven with `next_event_with`.
#[async_trait]
pub trait Provider: Send {
    fn kind(&self) -> ProviderKind;
    fn capabilities(&self) -> ProviderCapabilities;
    fn session(&self) -> Option<&ProviderSession>;
    async fn initialize(&mut self) -> Result<(), ProviderError>;
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError>;
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError>;
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
