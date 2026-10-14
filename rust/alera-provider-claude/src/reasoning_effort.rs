use alera_provider_protocol::{ProviderError, ReasoningEffortCapabilities};

pub(super) fn capabilities() -> ReasoningEffortCapabilities {
    ReasoningEffortCapabilities {
        session: true,
        turn: false,
        model_specific: true,
        values: ["low", "medium", "high", "xhigh", "max"]
            .map(str::to_owned)
            .to_vec(),
        session_wire_field: Some("ClaudeAgentOptions.effort -> --effort".into()),
        turn_wire_field: None,
    }
}

pub(super) fn validate(effort: &str, model: Option<&str>) -> Result<(), ProviderError> {
    if !matches!(effort, "low" | "medium" | "high" | "xhigh" | "max") {
        return Err(ProviderError::Unsupported(format!(
            "unsupported Claude reasoning effort: {effort}"
        )));
    }
    // Upstream falls back to high elsewhere, which cannot satisfy an explicit xhigh request.
    if effort == "xhigh"
        && !model.is_some_and(|model| model.contains("opus-4-7") || model.contains("opus-4.7"))
    {
        return Err(ProviderError::Unsupported(
            "Claude xhigh effort requires an explicitly selected Opus 4.7 model".into(),
        ));
    }
    Ok(())
}
