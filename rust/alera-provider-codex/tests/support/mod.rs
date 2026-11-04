use alera_provider_protocol::{EventKind, Provider, ProviderError, ProviderEvent};

/// The next event other than `session.commands.updated`, which every
/// session start queues and which these scenarios do not exercise.
pub async fn next_event(
    provider: &mut impl Provider,
) -> Result<Option<ProviderEvent>, ProviderError> {
    loop {
        let event = provider.next_event().await?;
        if !event
            .as_ref()
            .is_some_and(|event| event.kind == EventKind::SessionCommandsUpdated)
        {
            return Ok(event);
        }
    }
}
