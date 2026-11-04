use alera_provider_protocol::{
    reasoning_effort, ProviderError, ReasoningEffortCapabilities, REASONING_EFFORT_OPTION,
};
use serde_json::{Map, Value};

pub(crate) fn capabilities() -> ReasoningEffortCapabilities {
    ReasoningEffortCapabilities {
        session: true,
        turn: true,
        model_specific: true,
        values: Vec::new(),
        session_wire_field: Some("config.model_reasoning_effort".into()),
        turn_wire_field: Some("effort / collaborationMode.settings.reasoning_effort".into()),
    }
}

pub(crate) fn thread_options(params: &mut Map<String, Value>) -> Result<(), ProviderError> {
    let effort = reasoning_effort(params)?.map(str::to_owned);
    params.remove(REASONING_EFFORT_OPTION);
    if let Some(effort) = effort {
        let config = params
            .entry("config")
            .or_insert_with(|| Value::Object(Map::new()))
            .as_object_mut()
            .ok_or_else(|| {
                ProviderError::Validation("Codex thread config must be a JSON object".into())
            })?;
        insert_exact(config, "model_reasoning_effort", &effort)?;
    }
    Ok(())
}

pub(crate) fn turn_options(
    params: &mut Map<String, Value>,
) -> Result<Option<String>, ProviderError> {
    let effort = reasoning_effort(params)?.map(str::to_owned);
    params.remove(REASONING_EFFORT_OPTION);
    if let Some(effort) = &effort {
        insert_exact(params, "effort", effort)?;
    }
    Ok(effort.or_else(|| {
        params
            .get("effort")
            .and_then(Value::as_str)
            .map(str::to_owned)
    }))
}

fn insert_exact(
    params: &mut Map<String, Value>,
    key: &str,
    effort: &str,
) -> Result<(), ProviderError> {
    let value = Value::String(effort.into());
    if params.get(key).is_some_and(|existing| existing != &value) {
        return Err(ProviderError::Validation(format!(
            "reasoningEffort conflicts with Codex {key}"
        )));
    }
    params.insert(key.into(), value);
    Ok(())
}
